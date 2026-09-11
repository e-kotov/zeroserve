# Server Improvements based on httpuv

Based on an analysis of the `httpuv` package documentation and source code, we can leverage several built-in features to improve server management in the `zeroserve` package.

## 1. Auto Port Selection & Fail-Safes

`httpuv` provides a built-in `randomPort()` function which we can use to automatically find an available port.

- **Function:** `httpuv::randomPort(min = 1024L, max = 49151L, host = "127.0.0.1", n = 20)`
- **Fail-safe:** We can allow the user to specify a port. If they specify `NULL` or if we want to fallback securely, we can use `randomPort()` to guarantee an open port instead of a blind `sample()` that might collide with an in-use port.

## 2. Server Registry

`httpuv` internally tracks all running servers.
- **Function:** `httpuv::listServers()` returns a list of all currently running `httpuv` server applications in the R session.
- **Function:** `httpuv::stopAllServers()` can be used as an emergency fallback to kill all running servers.

Instead of solely relying on `.zeroserve_env$server` to check if a server is running, we can cross-reference with `httpuv::listServers()` or even use it to manage multiple servers if the package evolves.

## 3. Server Status

Each server object created by `httpuv::startServer()` is an R6 object inheriting from `Server`.
- **Status Check:** We can check if a server is running by calling the `$isRunning()` method on the server object.
- **Implementation Note:**
  ```r
  zs_server_status <- function() {
    if (is.null(.zeroserve_env$server)) return(FALSE)
    return(.zeroserve_env$server$isRunning())
  }
  ```

## 4. Server Logs

`httpuv` has a built-in logging system that can be configured.
- **Function:** `httpuv::logLevel(level = NULL)` allows setting the logging level to `"OFF"`, `"ERROR"`, `"WARN"`, `"INFO"`, or `"DEBUG"`.
- By default, these logs are likely emitted to standard error. In the background process (`callr::r_bg`), we can capture `stderr` (which `zeroserve` already does by specifying `log_file`). We can improve the developer experience by exposing a function to read these logs easily and perhaps adjusting the `logLevel` for debugging.
- **Implementation Note:**
  ```r
  zs_server_logs <- function(n = 20) {
    if (is.null(.zeroserve_env$log_file) || !file.exists(.zeroserve_env$log_file)) {
      message("No server logs found.")
      return(invisible(NULL))
    }
    ## 5. Comparison with `servr`

An analysis of the `servr` package (`https://github.com/yihui/servr`) reveals:
- **Range Requests:** `servr` implements robust Range request support using `seek()` and `readBin()`, including handling for open-ended ranges (e.g., `bytes=0-`).
- **Execution Model:** `servr` uses `httpuv`'s native daemonized mode. However, its own documentation notes that this is still subject to blocking by the main R thread.
- **Differentiator:** `zeroserve` provides **true isolation** by defaulting to a separate `callr` process. This ensures that data streaming (especially large Arrow buffers and Parquet files) is never interrupted by heavy analytical work in the main R session.
- **Specialization:** `zeroserve` is optimized for zero-copy Arrow transport and spatial data types, whereas `servr` is a general-purpose file server.

## Implementation Plan

1.  **Port Management:** Update `start_server()` to use `httpuv::randomPort()` to avoid collisions.
2.  **Status Check:** Add `zs_server_status()` wrapping the `callr` process `$is_alive()` check.
3.  **Logging:** Add `zs_server_logs()` to expose the background process log file.
4.  **Range Requests:** Refine `zeroserve` Range parsing to support open-ended ranges (learned from `servr`).
5.  **Exposed Options:** Add a way to set a specific port if desired (e.g., via `options(zeroserve.port)`).