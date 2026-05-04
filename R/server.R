#' @importFrom rlang %||%
NULL

#' Start the background server for zeroserve
#'
#' @return Logical; TRUE if server is running.
#' @noRd
start_server <- function() {
  if (!is.null(.zeroserve_env$server) && .zeroserve_env$server$is_alive()) {
    return(TRUE)
  }

  port <- sample(8000:9000, 1)
  registry_file <- tempfile("zeroserve_registry_", fileext = ".rds")
  log_file <- tempfile("zeroserve_server_", fileext = ".log")

  # Initialize empty registry
  saveRDS(list(), registry_file)

  server <- callr::r_bg(
    func = function(port, registry_file, log_file, handle_request) {
      write(sprintf("Starting server on port %s", port), log_file)
      
      app <- list(
        call = function(req) {
          tryCatch({
            handle_request(req, registry_file, log_file)
          }, error = function(e) {
            write(sprintf("Error in request handler: %s", as.character(e)), log_file, append = TRUE)
            list(status = 500L, headers = list(), body = "Internal Server Error")
          })
        }
      )
      
      httpuv::runServer("127.0.0.1", port, app)
      while (TRUE) {
        Sys.sleep(1)
      }
    },
    args = list(
      port = port, 
      registry_file = registry_file, 
      log_file = log_file, 
      handle_request = .handle_request
    )
  )

  .zeroserve_env$server <- server
  .zeroserve_env$registry_file <- registry_file
  .zeroserve_env$log_file <- log_file
  .zeroserve_env$port <- port

  # Wait a brief moment for the server to bind to the port
  Sys.sleep(1.0)
  return(TRUE)
}

#' Internal request handler
#'
#' @param req httpuv request object.
#' @param registry_file Path to registry RDS.
#' @param log_file Path to log file.
#' @return httpuv response list.
#' @noRd
.handle_request <- function(req, registry_file, log_file) {
  # Read registry to find available endpoints
  registry <- readRDS(registry_file)
  path <- req$PATH_INFO
  
  if (!is.null(registry[[path]])) {
    res <- registry[[path]]
    
    if (res$type == "file") {
      if (!file.exists(res$path)) {
        return(list(status = 404L, headers = list(), body = "File Not Found"))
      }

      file_size <- file.info(res$path)$size
      range_header <- req$HTTP_RANGE
      
      common_headers <- list(
        "Access-Control-Allow-Origin" = "*",
        "Access-Control-Allow-Methods" = "GET, OPTIONS",
        "Access-Control-Allow-Headers" = "Range",
        "Access-Control-Expose-Headers" = "Content-Length, Content-Range"
      )
      
      if (is.null(range_header)) {
        write(sprintf("Serving full file: %s", res$path), log_file, append = TRUE)
        return(list(
          status = 200L,
          headers = c(list("Content-Type" = "application/octet-stream"), common_headers),
          body = list(file = res$path)
        ))
      } else {
        # Simple Range Parsing: bytes=START-END
        write(sprintf("Serving partial file (%s): %s", range_header, res$path), log_file, append = TRUE)
        
        range_match <- regexec("bytes=([0-9]+)-([0-9]*)", range_header)
        matches <- regmatches(range_header, range_match)[[1]]
        
        if (length(matches) < 2) {
          return(list(status = 416L, headers = list(), body = "Requested Range Not Satisfiable"))
        }
        
        start <- as.numeric(matches[2])
        end <- if (matches[3] == "") file_size - 1 else as.numeric(matches[3])
        
        if (start >= file_size || end >= file_size || start > end) {
          return(list(status = 416L, headers = list(), body = "Requested Range Not Satisfiable"))
        }
        
        chunk_size <- end - start + 1
        
        con <- file(res$path, "rb")
        on.exit(close(con))
        seek(con, start)
        chunk <- readBin(con, "raw", chunk_size)
        
        return(list(
          status = 206L,
          headers = c(list(
            "Content-Type" = "application/octet-stream",
            "Content-Range" = sprintf("bytes %s-%s/%s", start, end, file_size),
            "Content-Length" = as.character(chunk_size)
          ), common_headers),
          body = chunk
        ))
      }
    } else if (res$type == "mori") {
      write(sprintf("Serving mori: %s", res$shm_name), log_file, append = TRUE)
      # map buffer using mori
      mapped_buf <- mori::map_shared(res$shm_name)
      return(list(
        status = 200L,
        headers = list(
          "Content-Type" = "application/vnd.apache.arrow.stream",
          "Access-Control-Allow-Origin" = "*"
        ),
        body = mapped_buf
      ))
    }
  }
  
  list(status = 404L, headers = list(), body = "Not Found")
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
  if (is.null(.zeroserve_env$server)) {
    return(FALSE)
  }

  if (inherits(.zeroserve_env$server, "process")) {
    .zeroserve_env$server$kill()
  }

  .zeroserve_env$server <- NULL
  .zeroserve_env$port <- NULL
  .zeroserve_env$registry_file <- NULL
  
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
  # Free shared memory buffers
  .zeroserve_env$mori_buffers <- list()
  
  # Update registry file if it exists
  if (!is.null(.zeroserve_env$registry_file)) {
    saveRDS(list(), .zeroserve_env$registry_file)
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
  start_server()
  
  reg <- readRDS(.zeroserve_env$registry_file)
  reg[[path]] <- resource
  saveRDS(reg, .zeroserve_env$registry_file)
  
  sprintf("http://127.0.0.1:%s%s", .zeroserve_env$port, path)
}
