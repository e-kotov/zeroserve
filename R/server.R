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

  # Windows, or a system without /dev/urandom, when openssl is installed.
  if (
    length(bytes) != n_bytes && requireNamespace("openssl", quietly = TRUE)
  ) {
    bytes <- tryCatch(
      openssl::rand_bytes(n_bytes),
      error = function(e) NULL
    )
  }

  if (length(bytes) == n_bytes) {
    return(paste(as.character(bytes), collapse = ""))
  }

  # Last resort: NOT a CSPRNG. Mixes wall clock, process id and a temporary
  # file name, so `set.seed()` does not reproduce it, but it is worth only a
  # few tens of bits. Deliberately avoids runif() so that serving data never
  # perturbs the caller's RNG stream.
  warning(
    "No cryptographic random source available (no /dev/urandom and the ",
    "'openssl' package is not installed): zeroserve URLs are protected by a ",
    "weak token. Install 'openssl' to get unguessable URLs.",
    call. = FALSE
  )
  substr(
    rlang::hash(list(Sys.time(), Sys.getpid(), tempfile())),
    1L,
    2L * n_bytes
  )
}

#' Build the browser-facing URL for a registered resource
#'
#' `127.0.0.1` is only reachable by the browser when R runs on the same machine.
#' On RStudio Server, Posit Workbench, Connect, containers or over SSH the
#' address must be rewritten, either explicitly through the
#' `zeroserve.base_url` option or by the RStudio proxy helper.
#'
#' @param port Integer port the background server listens on.
#' @param token The per-session data-plane capability token.
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

  # Two distinct secrets: the control-plane token never reaches a browser.
  ipc_token <- .zs_random_token() # Shared secret for control plane
  data_token <- .zs_random_token() # Capability token carried in served URLs
  max_chunk <- getOption("zeroserve.max_chunk", 104857600L) # Default 100MB

  log_file <- tempfile("zeroserve_server_", fileext = ".log")

  server <- callr::r_bg(
    func = function(port, ipc_token, data_token, log_file, max_chunk) {
      tryCatch(
        {
          write(
            sprintf("[%s] Background Process Started", Sys.time()),
            log_file
          )

          # Shared state for the registry
          registry <- new.env(parent = emptyenv())

          # Unified Handler
          app <- list(
            call = function(req) {
              path <- req$PATH_INFO
              method <- req$REQUEST_METHOD

              # 1. CORS Preflight (OPTIONS)
              if (method == "OPTIONS") {
                return(list(
                  status = 204L,
                  headers = list(
                    "Access-Control-Allow-Origin" = "*",
                    "Access-Control-Allow-Methods" = "GET, HEAD, OPTIONS",
                    "Access-Control-Allow-Headers" = "Range",
                    "Access-Control-Max-Age" = "86400",
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
                  reg_list <- as.list(registry)
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
                # Served URLs carry a per-session capability token as their
                # first path segment. A missing, malformed or wrong token is
                # answered with exactly the same 404 as an unknown path, so the
                # endpoint is not an oracle for either. That 404 carries no
                # CORS header, so a token-less cross-origin probe cannot even
                # read the rejection.
                not_found <- list(
                  status = 404L,
                  headers = list(),
                  body = "Not Found"
                )

                token_prefix <- paste0("/", data_token, "/")
                if (!startsWith(path, token_prefix)) {
                  return(not_found)
                }
                # Keep the leading "/" of the registered path. Sliced on raw
                # bytes because httpuv does not decode PATH_INFO, so an invalid
                # UTF-8 path would make substr() throw and turn the uniform 404
                # into a 500.
                data_path <- rawToChar(
                  charToRaw(path)[-seq_len(nchar(token_prefix, type = "bytes") - 1L)]
                )

                resource <- registry[[data_path]]
                if (is.null(resource)) {
                  return(not_found)
                }

                tryCatch(
                  {
                    # Helper for data requests (to be hardened in next tier)
                    if (resource$type == "file") {
                      if (!file.exists(resource$path)) {
                        return(list(
                          status = 404L,
                          headers = list("Access-Control-Allow-Origin" = "*"),
                          body = "File Not Found"
                        ))
                      }
                      file_size <- file.info(resource$path)$size
                      range_header <- req$HTTP_RANGE
                      common_headers <- list(
                        "Access-Control-Allow-Origin" = "*",
                        "Access-Control-Allow-Methods" = "GET, HEAD, OPTIONS",
                        "Access-Control-Allow-Headers" = "Range",
                        "Access-Control-Expose-Headers" = "Content-Length, Content-Range",
                        "Content-Encoding" = "identity",
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
                    } else if (resource$type == "mori") {
                      mapped_buf <- mori::map_shared(resource$shm_name)
                      return(list(
                        status = 200L,
                        headers = list(
                          "Content-Type" = "application/vnd.apache.arrow.stream",
                          "Content-Encoding" = "identity",
                          "Access-Control-Allow-Origin" = "*"
                        ),
                        body = mapped_buf
                      ))
                    }
                    list(
                      status = 404L,
                      headers = list("Access-Control-Allow-Origin" = "*"),
                      body = "Not Found"
                    )
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
      data_token = data_token,
      log_file = log_file,
      max_chunk = max_chunk
    ),
    stderr = log_file,
    stdout = log_file
  )

  .zeroserve_env$server <- server
  .zeroserve_env$ipc_token <- ipc_token
  .zeroserve_env$data_token <- data_token
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

  if (resource$type == "file") {
    if (!file.exists(resource$path)) {
      return(list(
        status = 404L,
        headers = list("Access-Control-Allow-Origin" = "*"),
        body = "File Not Found"
      ))
    }

    file_size <- file.info(resource$path)$size
    range_header <- req$HTTP_RANGE

    common_headers <- list(
      "Access-Control-Allow-Origin" = "*",
      "Access-Control-Allow-Methods" = "GET, HEAD, OPTIONS",
      "Access-Control-Allow-Headers" = "Range",
      "Access-Control-Expose-Headers" = "Content-Length, Content-Range",
      "Content-Encoding" = "identity",
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
  } else if (resource$type == "mori") {
    # map buffer using mori
    mapped_buf <- mori::map_shared(resource$shm_name)
    return(list(
      status = 200L,
      headers = list(
        "Content-Type" = "application/vnd.apache.arrow.stream",
        "Content-Encoding" = "identity",
        "Access-Control-Allow-Origin" = "*"
      ),
      body = mapped_buf
    ))
  }

  list(
    status = 404L,
    headers = list("Access-Control-Allow-Origin" = "*"),
    body = "Not Found"
  )
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
  .zeroserve_env$data_token <- NULL

  return(TRUE)
}

#' Clear the zeroserve resource registry
#'
#' This stops serving all currently registered resources and frees
#' associated memory buffers.
#'
#' @return Logical; TRUE if registry was cleared.
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

  # Tell the background server to clear its in-memory registry
  if (zs_server_status()) {
    tryCatch(.send_ipc("/clear"), error = function(e) NULL)
  }

  return(TRUE)
}

#' Register a resource with the background server
#'
#' @param path The URL path (e.g., "/layer_1.arrow").
#' @param resource A list describing the resource (type, and path or shm_name).
#' @return The full localhost URL.
#' @noRd
register_resource <- function(path, resource) {
  if (startsWith(path, "/__zs__/")) {
    stop("Path prefix '/__zs__/' is reserved for internal control endpoints.")
  }

  start_server()

  .send_ipc("/register", list(path = path, resource = resource))

  .zs_public_url(.zeroserve_env$port, .zeroserve_env$data_token, path)
}
