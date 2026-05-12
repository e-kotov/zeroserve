# Global environment to store background process state
.zeroserve_env <- new.env(parent = emptyenv())
.zeroserve_env$server <- NULL
.zeroserve_env$log_file <- NULL
.zeroserve_env$port <- NULL
.zeroserve_env$ipc_token <- NULL
.zeroserve_env$mori_buffers <- list()
.zeroserve_env$temp_files <- character(0)

# nocov start
.onUnload <- function(libpath) {
  # Clean up server on package unload
  zs_stop_server()
}
# nocov end
