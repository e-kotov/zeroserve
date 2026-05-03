# Global environment to store background process state
.zeroserve_env <- new.env(parent = emptyenv())
.zeroserve_env$server <- NULL
.zeroserve_env$registry_file <- NULL
.zeroserve_env$log_file <- NULL
.zeroserve_env$port <- NULL
.zeroserve_env$mori_buffers <- list()

# nocov start
.onUnload <- function(libpath) {
  # Clean up server on package unload
  if (!is.null(.zeroserve_env$server) && inherits(.zeroserve_env$server, "process")) {
    .zeroserve_env$server$kill()
  }
}
# nocov end
