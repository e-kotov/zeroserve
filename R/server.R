#' @importFrom rlang %||%
#' @importFrom utils tail
NULL

#' Read bytes from the system CSPRNG
#'
#' @param n_bytes Number of bytes to read.
#' @return A raw vector of `n_bytes`, or `NULL` when unavailable.
#' @noRd
.zs_urandom_bytes <- function(n_bytes) {
  if (!file.exists("/dev/urandom")) {
    return(NULL)
  }

  tryCatch(
    {
      # `raw = TRUE` is required: /dev/urandom is a character device, and
      # without it file() signals "'raw = FALSE' but ... is not a regular
      # file", which would divert every token to the weak fallback below.
      con <- file("/dev/urandom", "rb", raw = TRUE)
      on.exit(close(con), add = TRUE)
      bytes <- readBin(con, "raw", n = n_bytes)
      if (length(bytes) == n_bytes) bytes else NULL
    },
    error = function(e) NULL
  )
}

#' Generate an unguessable token
#'
#' Returns 16 random bytes as 32 lowercase hexadecimal characters.
#'
#' @note The `rlang::hash(runif(1))` idiom previously used for the IPC token is
#'   seeded by R's RNG and is therefore reproducible after `set.seed()`. Use
#'   this helper for anything that must be unguessable by a third party.
#' @param n_bytes Number of random bytes behind the token.
#' @return A length-1 character vector of `2 * n_bytes` hexadecimal characters.
#' @noRd
.zs_random_token <- function(n_bytes = 16L) {
  # Portable and dependency-free on macOS, Linux and other unices.
  bytes <- .zs_urandom_bytes(n_bytes)

  # Windows, or any system without /dev/urandom. `openssl` is a hard
  # dependency precisely so that this path always exists: there is no weak
  # fallback, because a guessable token is worse than a clear failure.
  if (length(bytes) != n_bytes) {
    bytes <- tryCatch(
      openssl::rand_bytes(n_bytes),
      error = function(e) NULL
    )
  }

  if (length(bytes) != n_bytes) {
    stop(
      "Could not read ",
      n_bytes,
      " bytes from a cryptographic random source: neither '/dev/urandom' nor ",
      "openssl::rand_bytes() is usable in this session. zeroserve refuses to ",
      "serve data behind a guessable token.",
      call. = FALSE
    )
  }

  # Deliberately avoids runif() so that serving data never perturbs the
  # caller's RNG stream.
  paste(as.character(bytes), collapse = "")
}

#' Build the browser-facing URL for a registered resource
#'
#' `127.0.0.1` is only reachable by the browser when R runs on the same machine.
#' On RStudio Server, Posit Workbench, Connect, containers or over SSH the
#' address must be rewritten, either explicitly through the
#' `zeroserve.base_url` option or by the RStudio proxy helper.
#'
#' @param port Integer port the background server listens on.
#' @param token The resource's data-plane capability token.
#' @param path The registered resource path, e.g. `"/stream.arrow"`.
#' @return A length-1 character vector with the full URL.
#' @noRd
.zs_public_url <- function(port, token, path) {
  base_url <- getOption("zeroserve.base_url")
  if (is.character(base_url) && length(base_url) == 1L && !is.na(base_url)) {
    base_url <- trimws(base_url)
    if (nzchar(base_url)) {
      return(paste0(sub("/+$", "", base_url), "/", token, path))
    }
  }

  local_url <- sprintf("http://127.0.0.1:%s/%s%s", port, token, path)

  # Posit Workbench and RStudio Server proxy localhost ports as /p/<hash>/;
  # the whole URL has to be translated, not just the authority.
  if (
    requireNamespace("rstudioapi", quietly = TRUE) &&
      isTRUE(tryCatch(rstudioapi::isAvailable(), error = function(e) FALSE))
  ) {
    translated <- tryCatch(
      rstudioapi::translateLocalUrl(local_url, absolute = TRUE),
      error = function(e) NULL
    )
    if (
      is.character(translated) &&
        length(translated) == 1L &&
        !is.na(translated) &&
        grepl("^https?://", translated)
    ) {
      return(translated)
    }
  }

  local_url
}

#' Start the background server for zeroserve
#'
#' @return Logical; TRUE if server is running.
#' @noRd
start_server <- function() {
  if (zs_server_status()) {
    return(TRUE)
  }

  # Port logic
  port <- getOption("zeroserve.port")
  if (is.null(port)) {
    port <- tryCatch(
      httpuv::randomPort(min = 8000L, max = 9000L, n = 20),
      error = function(e) {
        # Fallback if randomPort fails (common in some sandboxed environments)
        base_port <- 8000L + (as.integer(Sys.time()) %% 1000L)
        base_port
      }
    )
  }

  # The control-plane token never reaches a browser. Data-plane capability
  # tokens are minted per resource in register_resource().
  ipc_token <- .zs_random_token() # Shared secret for control plane
  max_chunk <- getOption("zeroserve.max_chunk", 104857600L) # Default 100MB

  log_file <- tempfile("zeroserve_server_", fileext = ".log")

  server <- callr::r_bg(
    func = function(port, ipc_token, log_file, max_chunk) {
      tryCatch(
        {
          write(
            sprintf("[%s] Background Process Started", Sys.time()),
            log_file
          )

          # Shared state for the registry
          registry <- new.env(parent = emptyenv())

          # Every data-plane rejection is this exact response: status 404, no
          # headers at all, body "Not Found". A token-less probe therefore
          # cannot tell a zeroserve instance from a closed port, and cannot
          # read the rejection cross-origin either.
          not_found <- list(
            status = 404L,
            headers = list(),
            body = "Not Found"
          )

          # Backing files that have gone missing, so that the log line below
          # is written once per file rather than once per request: a saved
          # widget retrying a fetch would otherwise grow the log without
          # bound on the single-threaded event loop.
          missing_logged <- new.env(parent = emptyenv())

          # Resolve a data-plane path to its resource, or NULL.
          #
          # Served URLs are "/<32 hex>/<registered path>", where the first
          # segment is that resource's own capability token. A malformed
          # segment, an unknown path and a token belonging to a different
          # resource are all indistinguishable from each other: they return
          # NULL, never an error and never a different status, so the endpoint
          # is not an oracle for token or resource existence.
          resolve_resource <- function(path) {
            # Sliced on raw bytes because httpuv does not decode PATH_INFO, so
            # an invalid UTF-8 path would make substr() throw and turn the
            # uniform 404 into a 500. The hex segment is validated by byte
            # code for the same reason: a regexp on an invalid multibyte
            # string signals an error.
            bytes <- charToRaw(path)

            # "/" + 32 hex + "/", where that last "/" already begins the
            # registered path: a path of exactly "/" is 34 bytes and must stay
            # reachable, so the guard is 34 and not 35.
            if (length(bytes) < 34L) {
              return(NULL)
            }
            codes <- as.integer(bytes)
            if (codes[1L] != 47L || codes[34L] != 47L) {
              return(NULL)
            }
            hex <- codes[2:33]
            if (
              !all((hex >= 48L & hex <= 57L) | (hex >= 97L & hex <= 102L))
            ) {
              return(NULL)
            }

            candidate <- rawToChar(bytes[2:33])
            # Keeps the leading "/" of the registered path.
            data_path <- rawToChar(bytes[-seq_len(33L)])

            resource <- registry[[data_path]]
            if (is.null(resource)) {
              return(NULL)
            }

            stored <- resource$token
            if (length(stored) != 1L) {
              return(NULL)
            }
            if (!identical(as.character(stored)[[1L]], candidate)) {
              return(NULL)
            }

            resource
          }

          # Unified Handler
          app <- list(
            call = function(req) {
              path <- req$PATH_INFO
              method <- req$REQUEST_METHOD

              # 1. CORS Preflight (OPTIONS)
              #
              # Gated on the capability token: answering 204 for any path made
              # the instance fingerprintable cross-origin, which is exactly
              # what the token exists to prevent. A real client always
              # preflights the tokenised URL it was handed, and a browser
              # never calls the control plane.
              if (method == "OPTIONS") {
                if (is.null(resolve_resource(path))) {
                  return(not_found)
                }
                return(list(
                  status = 204L,
                  headers = list(
                    "Access-Control-Allow-Origin" = "*",
                    "Access-Control-Allow-Methods" = "GET, HEAD, OPTIONS",
                    "Access-Control-Allow-Headers" = "Range",
                    "Access-Control-Max-Age" = "86400",
                    "Referrer-Policy" = "no-referrer",
                    "Content-Length" = "0",
                    "Connection" = "close"
                  ),
                  body = raw(0)
                ))
              }

              # 2. Control Plane (/__zs__/)
              if (startsWith(path, "/__zs__/")) {
                token <- req$HTTP_X_ZEROSERVE_TOKEN
                if (is.null(token) || token != ipc_token) {
                  return(list(
                    status = 403L,
                    headers = list(),
                    body = "Forbidden"
                  ))
                }

                ctrl_path <- sub("^/__zs__", "", path)

                if (ctrl_path != "/ping") {
                  write(
                    sprintf(
                      "[%s] Control Request: %s %s",
                      Sys.time(),
                      method,
                      ctrl_path
                    ),
                    log_file,
                    append = TRUE
                  )
                }

                if (method == "POST" && ctrl_path == "/register") {
                  tryCatch(
                    {
                      body_raw <- req$rook.input$read()
                      resource_info <- jsonlite::fromJSON(
                        rawToChar(body_raw),
                        simplifyVector = FALSE
                      )
                      registry[[resource_info$path]] <- resource_info$resource
                      list(
                        status = 200L,
                        headers = list("Content-Type" = "application/json"),
                        body = "{\"status\": \"ok\"}"
                      )
                    },
                    error = function(e) {
                      list(
                        status = 500L,
                        headers = list("Content-Type" = "text/plain"),
                        body = as.character(e)
                      )
                    }
                  )
                } else if (ctrl_path == "/ping") {
                  list(
                    status = 200L,
                    headers = list("Content-Type" = "application/json"),
                    body = "{\"status\": \"alive\"}"
                  )
                } else if (ctrl_path == "/list") {
                  # Strip the capability tokens: /list output ends up in bug
                  # reports, and the registry keys are what callers need.
                  reg_list <- lapply(as.list(registry), function(r) {
                    r$token <- NULL
                    r
                  })
                  list(
                    status = 200L,
                    headers = list("Content-Type" = "application/json"),
                    body = jsonlite::toJSON(reg_list, auto_unbox = TRUE)
                  )
                } else if (ctrl_path == "/clear") {
                  rm(list = names(registry), envir = registry)
                  list(
                    status = 200L,
                    headers = list("Content-Type" = "application/json"),
                    body = "{\"status\": \"cleared\"}"
                  )
                } else {
                  list(status = 404L, headers = list(), body = "Not Found")
                }
              } else {
                # 3. Data Plane
                resource <- resolve_resource(path)
                if (is.null(resource)) {
                  return(not_found)
                }

                tryCatch(
                  {
                    # Helper for data requests (to be hardened in next tier).
                    # identical() rather than ==: a record with a missing or
                    # malformed `type` must fall through to the uniform 404,
                    # not raise "argument is of length zero" and answer 500.
                    if (identical(resource$type, "file")) {
                      if (!file.exists(resource$path)) {
                        # Kept off the wire, on purpose: the response has to be
                        # byte-identical to every other rejection. The log is
                        # where this case is debuggable.
                        # Never log `path`: it carries the capability token,
                        # and logs get pasted into bug reports.
                        if (!exists(resource$path, envir = missing_logged)) {
                          assign(resource$path, TRUE, envir = missing_logged)
                          write(
                            sprintf(
                              "[%s] Backing file gone: %s",
                              Sys.time(),
                              resource$path
                            ),
                            log_file,
                            append = TRUE
                          )
                        }
                        return(not_found)
                      }
                      file_size <- file.info(resource$path)$size
                      range_header <- req$HTTP_RANGE
                      common_headers <- list(
                        "Access-Control-Allow-Origin" = "*",
                        "Access-Control-Allow-Methods" = "GET, HEAD, OPTIONS",
                        "Access-Control-Allow-Headers" = "Range",
                        "Access-Control-Expose-Headers" = "Content-Length, Content-Range",
                        "Content-Encoding" = "identity",
                        "Referrer-Policy" = "no-referrer",
                        "Accept-Ranges" = "bytes"
                      )

                      if (is.null(range_header) || range_header == "") {
                        res_200 <- list(
                          status = 200L,
                          headers = c(
                            list(
                              "Content-Type" = "application/octet-stream",
                              "Content-Length" = format(file_size, scientific = FALSE)
                            ),
                            common_headers
                          ),
                          body = list(file = resource$path)
                        )
                        if (method == "HEAD") {
                          res_200$headers[["Connection"]] <- "close"
                          res_200$body <- raw(0)
                        }
                        return(res_200)
                      } else {
                        # Robust Range parsing
                        range_val <- gsub("\\s+", "", range_header)

                        # Reject multipart ranges
                        if (grepl(",", range_val)) {
                          return(list(
                            status = 416L,
                            headers = common_headers,
                            body = "Multipart ranges not supported"
                          ))
                        }

                        range_match <- regexec(
                          "^bytes=(\\d*)-(\\d*)$",
                          range_val
                        )
                        matches <- regmatches(range_val, range_match)[[1]]

                        if (length(matches) < 3) {
                          return(list(
                            status = 416L,
                            headers = common_headers,
                            body = "Range Not Satisfiable"
                          ))
                        }

                        start_str <- matches[2]
                        end_str <- matches[3]

                        if (start_str == "" && end_str == "") {
                          return(list(
                            status = 416L,
                            headers = common_headers,
                            body = "Range Not Satisfiable"
                          ))
                        }

                        if (start_str == "") {
                          # Suffix-byte: last N bytes
                          suffix_len <- as.numeric(end_str)
                          start <- max(0, file_size - suffix_len)
                          end <- file_size - 1
                        } else {
                          start <- as.numeric(start_str)
                          end <- if (end_str == "") {
                            file_size - 1
                          } else {
                            as.numeric(end_str)
                          }
                        }

                        if (
                          start >= file_size || end >= file_size || start > end
                        ) {
                          return(list(
                            status = 416L,
                            headers = common_headers,
                            body = "Range Not Satisfiable"
                          ))
                        }

                        chunk_size <- end - start + 1
                        # OOM Protection
                        if (chunk_size > max_chunk) {
                          end <- start + max_chunk - 1
                          chunk_size <- max_chunk
                        }

                        if (method == "HEAD") {
                          return(list(
                            status = 206L,
                            headers = c(
                              list(
                                "Content-Type" = "application/octet-stream",
                                "Content-Range" = sprintf(
                                  "bytes %s-%s/%s",
                                  start,
                                  end,
                                  file_size
                                ),
                                "Content-Length" = format(chunk_size, scientific = FALSE),
                                "Connection" = "close"
                              ),
                              common_headers
                            ),
                            body = raw(0)
                          ))
                        }

                        con <- file(resource$path, "rb")
                        on.exit(close(con))
                        seek(con, start)
                        chunk <- readBin(con, "raw", chunk_size)
                        return(list(
                          status = 206L,
                          headers = c(
                            list(
                              "Content-Type" = "application/octet-stream",
                              "Content-Range" = sprintf(
                                "bytes %s-%s/%s",
                                start,
                                end,
                                file_size
                              ),
                              "Content-Length" = format(chunk_size, scientific = FALSE)
                            ),
                            common_headers
                          ),
                          body = chunk
                        ))
                      }
                    } else if (identical(resource$type, "mori")) {
                      mapped_buf <- mori::map_shared(resource$shm_name)
                      return(list(
                        status = 200L,
                        headers = list(
                          "Content-Type" = "application/vnd.apache.arrow.stream",
                          "Content-Encoding" = "identity",
                          "Access-Control-Allow-Origin" = "*",
                          "Referrer-Policy" = "no-referrer"
                        ),
                        body = mapped_buf
                      ))
                    }
                    not_found
                  },
                  error = function(e) {
                    write(
                      sprintf(
                        "[%s] Data Request Error: %s",
                        Sys.time(),
                        e$message
                      ),
                      log_file,
                      append = TRUE
                    )
                    list(
                      status = 500L,
                      headers = list("Access-Control-Allow-Origin" = "*"),
                      body = "Internal Server Error"
                    )
                  }
                )
              }
            }
          )

          write(
            sprintf(
              "[%s] Starting HTTP server on port %s...",
              Sys.time(),
              port
            ),
            log_file,
            append = TRUE
          )
          httpuv::startServer("127.0.0.1", port, app = app)

          while (TRUE) {
            httpuv::service(1000)
          }
        },
        error = function(e) {
          write(
            sprintf("[%s] FATAL BACKGROUND ERROR: %s", Sys.time(), e$message),
            log_file,
            append = TRUE
          )
        }
      )
    },
    args = list(
      port = port,
      ipc_token = ipc_token,
      log_file = log_file,
      max_chunk = max_chunk
    ),
    stderr = log_file,
    stdout = log_file
  )

  .zeroserve_env$server <- server
  .zeroserve_env$ipc_token <- ipc_token
  .zeroserve_env$log_file <- log_file
  .zeroserve_env$port <- port

  # Wait and verify
  success <- FALSE
  last_error <- "No error recorded"
  for (i in 1:20) {
    # Check if process is still alive first
    if (!server$is_alive()) {
      last_error <- "Background process died"
      break
    }

    res <- tryCatch(.send_ipc("/ping"), error = function(e) {
      last_error <<- e$message
      NULL
    })
    if (!is.null(res) && res$status == "alive") {
      success <- TRUE
      break
    }
    Sys.sleep(0.5)
  }

  if (!success) {
    msg <- if (file.exists(log_file)) {
      tail(readLines(log_file, warn = FALSE), 20)
    } else {
      "No logs found."
    }
    stop(sprintf(
      "Failed to start background IPC server.\nLast IPC Error: %s\nBackground Logs:\n%s",
      last_error,
      paste(msg, collapse = "\n")
    ))
  }
  return(TRUE)
}

#' Send a command to the background IPC server
#' @param stop_on_error Logical; if TRUE, stop() on error.
#' @noRd
.send_ipc <- function(endpoint, payload = NULL, stop_on_error = TRUE) {
  h <- curl::new_handle()

  # Set a short timeout for internal IPC and bypass proxies
  curl::handle_setopt(
    h,
    connecttimeout = 2,
    timeout = 5,
    noproxy = "127.0.0.1,localhost"
  )

  headers <- list("X-Zeroserve-Token" = .zeroserve_env$ipc_token)

  # Single port architecture - control endpoints live under /__zs__/
  url <- sprintf("http://127.0.0.1:%s/__zs__%s", .zeroserve_env$port, endpoint)

  if (!is.null(payload)) {
    curl::handle_setopt(
      h,
      post = TRUE,
      postfields = jsonlite::toJSON(payload, auto_unbox = TRUE)
    )
    headers["Content-Type"] <- "application/json"
  }

  do.call(curl::handle_setheaders, c(list(h), headers))

  result <- tryCatch(
    {
      res <- curl::curl_fetch_memory(url, handle = h)
      if (res$status_code >= 400) {
        msg <- sprintf(
          "IPC Request Failed (%s): %s",
          res$status_code,
          rawToChar(res$content)
        )
        if (stop_on_error) stop(msg) else return(NULL)
      }
      jsonlite::fromJSON(rawToChar(res$content))
    },
    error = function(e) {
      if (stop_on_error) stop(e) else NULL
    }
  )

  return(result)
}

#' Internal data request handler (Test Helper)
#'
#' @note This must be kept in sync with the inline handler in start_server().
#' @noRd
.handle_data_request <- function(
  req,
  resource,
  log_file,
  max_chunk = 104857600L
) {
  method <- req$REQUEST_METHOD %||% "GET"

  # Identical to the inline handler's uniform rejection.
  not_found <- list(
    status = 404L,
    headers = list(),
    body = "Not Found"
  )

  if (identical(resource$type, "file")) {
    if (!file.exists(resource$path)) {
      # The inline handler writes this once per backing file rather than once
      # per request; here there is no event loop to protect.
      write(
        sprintf("[%s] Backing file gone: %s", Sys.time(), resource$path),
        log_file,
        append = TRUE
      )
      return(not_found)
    }

    file_size <- file.info(resource$path)$size
    range_header <- req$HTTP_RANGE

    common_headers <- list(
      "Access-Control-Allow-Origin" = "*",
      "Access-Control-Allow-Methods" = "GET, HEAD, OPTIONS",
      "Access-Control-Allow-Headers" = "Range",
      "Access-Control-Expose-Headers" = "Content-Length, Content-Range",
      "Content-Encoding" = "identity",
      "Referrer-Policy" = "no-referrer",
      "Accept-Ranges" = "bytes"
    )

    if (is.null(range_header) || range_header == "") {
      res_200 <- list(
        status = 200L,
        headers = c(
          list(
            "Content-Type" = "application/octet-stream",
            "Content-Length" = format(file_size, scientific = FALSE)
          ),
          common_headers
        ),
        body = list(file = resource$path)
      )
      if (method == "HEAD") {
        res_200$headers[["Connection"]] <- "close"
        res_200$body <- raw(0)
      }
      return(res_200)
    } else {
      # Robust Range parsing
      range_val <- gsub("\\s+", "", range_header)

      # Reject multipart ranges
      if (grepl(",", range_val)) {
        return(list(
          status = 416L,
          headers = common_headers,
          body = "Multipart ranges not supported"
        ))
      }

      range_match <- regexec("^bytes=(\\d*)-(\\d*)$", range_val)
      matches <- regmatches(range_val, range_match)[[1]]

      if (length(matches) < 3) {
        return(list(
          status = 416L,
          headers = common_headers,
          body = "Range Not Satisfiable"
        ))
      }

      start_str <- matches[2]
      end_str <- matches[3]

      if (start_str == "" && end_str == "") {
        return(list(
          status = 416L,
          headers = common_headers,
          body = "Range Not Satisfiable"
        ))
      }

      if (start_str == "") {
        # Suffix-byte: last N bytes
        suffix_len <- as.numeric(end_str)
        start <- max(0, file_size - suffix_len)
        end <- file_size - 1
      } else {
        start <- as.numeric(start_str)
        end <- if (end_str == "") file_size - 1 else as.numeric(end_str)
      }

      if (start >= file_size || end >= file_size || start > end) {
        return(list(
          status = 416L,
          headers = common_headers,
          body = "Range Not Satisfiable"
        ))
      }

      chunk_size <- end - start + 1
      # OOM Protection
      if (chunk_size > max_chunk) {
        end <- start + max_chunk - 1
        chunk_size <- max_chunk
      }

      if (method == "HEAD") {
        return(list(
          status = 206L,
          headers = c(
            list(
              "Content-Type" = "application/octet-stream",
              "Content-Range" = sprintf(
                "bytes %s-%s/%s",
                start,
                end,
                file_size
              ),
              "Content-Length" = format(chunk_size, scientific = FALSE),
              "Connection" = "close"
            ),
            common_headers
          ),
          body = raw(0)
        ))
      }

      con <- file(resource$path, "rb")
      on.exit(close(con))
      seek(con, start)
      chunk <- readBin(con, "raw", chunk_size)

      return(list(
        status = 206L,
        headers = c(
          list(
            "Content-Type" = "application/octet-stream",
            "Content-Range" = sprintf("bytes %s-%s/%s", start, end, file_size),
            "Content-Length" = format(chunk_size, scientific = FALSE)
          ),
          common_headers
        ),
        body = chunk
      ))
    }
  } else if (identical(resource$type, "mori")) {
    # map buffer using mori
    mapped_buf <- mori::map_shared(resource$shm_name)
    return(list(
      status = 200L,
      headers = list(
        "Content-Type" = "application/vnd.apache.arrow.stream",
        "Content-Encoding" = "identity",
        "Access-Control-Allow-Origin" = "*",
        "Referrer-Policy" = "no-referrer"
      ),
      body = mapped_buf
    ))
  }

  not_found
}

#' Check if the zeroserve background server is running
#'
#' @param ping Logical; if TRUE, also send an IPC ping to verify the event loop.
#' @return Logical; TRUE if the server process is alive (and responsive if ping=TRUE).
#' @export
#'
#' @examples
#' zs_server_status()
zs_server_status <- function(ping = FALSE) {
  if (is.null(.zeroserve_env$server)) {
    return(FALSE)
  }

  if (inherits(.zeroserve_env$server, "process")) {
    alive <- .zeroserve_env$server$is_alive()
    if (!alive) {
      return(FALSE)
    }
    if (!ping) {
      return(TRUE)
    }

    res <- .send_ipc("/ping", stop_on_error = FALSE)
    return(!is.null(res) && identical(res$status, "alive"))
  }

  FALSE
}

#' Get the background server logs
#'
#' @param n Number of lines to return from the end of the log.
#' @return A character vector of log lines.
#' @export
#'
#' @examples
#' \dontrun{
#' zs_server_logs()
#' }
zs_server_logs <- function(n = 20) {
  log_file <- .zeroserve_env$log_file

  if (is.null(log_file) || !file.exists(log_file)) {
    message("No server logs found.")
    return(invisible(character(0)))
  }

  tail(readLines(log_file, warn = FALSE), n = n)
}

#' Stop the background zeroserve server
#'
#' @return Logical; TRUE if server was stopped, FALSE if it wasn't running.
#' @export
#'
#' @examples
#' \dontrun{
#' zs_stop_server()
#' }
zs_stop_server <- function() {
  if (!zs_server_status()) {
    return(FALSE)
  }

  if (inherits(.zeroserve_env$server, "process")) {
    .zeroserve_env$server$kill()
  }

  # Clean up temp files
  if (length(.zeroserve_env$temp_files) > 0) {
    unlink(.zeroserve_env$temp_files, recursive = TRUE)
    .zeroserve_env$temp_files <- character(0)
  }

  .zeroserve_env$server <- NULL
  .zeroserve_env$port <- NULL
  .zeroserve_env$ipc_token <- NULL

  return(TRUE)
}

#' Clear the zeroserve resource registry
#'
#' This stops serving all currently registered resources and frees
#' associated memory buffers, which revokes every URL handed out so far.
#'
#' @return Logical; `TRUE` if the registry was cleared. `FALSE`, with a
#'   warning, when the background server is running but could not be reached
#'   to clear it: the served URLs are then still live.
#' @export
#'
#' @examples
#' \dontrun{
#' zs_clear_registry()
#' }
zs_clear_registry <- function() {
  # Free shared memory buffers in the main process
  .zeroserve_env$mori_buffers <- list()

  # Clean up temp files
  if (length(.zeroserve_env$temp_files) > 0) {
    unlink(.zeroserve_env$temp_files, recursive = TRUE)
    .zeroserve_env$temp_files <- character(0)
  }

  # Tell the background server to clear its in-memory registry. This is the
  # documented way to revoke a URL, so a request that never landed -- the
  # event loop is single-threaded and .send_ipc() times out after 5s -- must
  # not be reported as a successful revocation.
  if (zs_server_status()) {
    cleared <- tryCatch(
      !is.null(.send_ipc("/clear")),
      error = function(e) FALSE
    )
    if (!isTRUE(cleared)) {
      warning(
        "Could not reach the background server to clear its registry: the ",
        "URLs served so far may still be live. Use zs_stop_server() to ",
        "revoke them unconditionally.",
        call. = FALSE
      )
      return(FALSE)
    }
  }

  return(TRUE)
}

#' Register a resource with the background server
#'
#' A fresh capability token is minted for every registration and stored on the
#' resource record, so a leaked URL exposes that one resource rather than the
#' whole session. Re-registering the same `path` overwrites the record with a
#' new token, which is what revokes the URL returned earlier for it;
#' [zs_clear_registry()] drops the records outright.
#'
#' @param path The URL path (e.g., "/layer_1.arrow").
#' @param resource A list describing the resource (type, and path or shm_name).
#' @return The full localhost URL, including the resource's token.
#' @noRd
register_resource <- function(path, resource) {
  if (startsWith(path, "/__zs__/")) {
    stop("Path prefix '/__zs__/' is reserved for internal control endpoints.")
  }

  start_server()

  resource$token <- .zs_random_token()

  .send_ipc("/register", list(path = path, resource = resource))

  .zs_public_url(.zeroserve_env$port, resource$token, path)
}
