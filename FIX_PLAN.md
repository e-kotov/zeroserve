# Dual-Server IPC Hardening Plan

## Context
Following an architectural review of the new Dual-Server IPC implementation, several critical vulnerabilities were identified. This plan outlines the engineered solutions to harden the server, ensuring production readiness.

## Detailed Implementation Plan

### 1. Robust HTTP Range Parsing
**Vulnerability:** The regex `bytes=([0-9]+)-([0-9]*)` fails on whitespace, multipart ranges, and suffix-byte requests (e.g., `bytes=-500`), leading to malformed responses or incorrect data slices.
**Solution:**
*   **Strip Whitespace:** Immediately sanitize the header: `range_header <- gsub("\\s+", "", req$HTTP_RANGE)`.
*   **Reject Multipart:** Explicitly reject multipart ranges (which are overly complex for this server and rarely used by analytical clients) by checking for commas: `if (grepl(",", range_header)) return(list(status = 416L, ...))`.
*   **Strict Regex & Suffix Support:** Use `^bytes=(\\d*)-(\\d*)$`. 
    *   If `start` is empty and `end` has a value: Treat as "last `end` bytes".
    *   If `start` has a value and `end` is empty: Treat as "from `start` to EOF".
    *   If both are empty or malformed: Return `416 Range Not Satisfiable`.

### 2. OOM / DoS Protection for Large Files
**Vulnerability:** `readBin(..., chunk_size)` reads the entire requested range into R's memory. A 10GB range request will instantly crash the background process.
**Solution:**
*   **Implement a Max Chunk Cap:** Cap the maximum readable chunk to 100MB: `MAX_CHUNK <- 100 * 1024^2`.
*   **Truncate `end` & `chunk_size`:** 
    ```r
    chunk_size <- min(chunk_size, MAX_CHUNK)
    end <- start + chunk_size - 1
    ```
*   **Standard-Compliant `Content-Range`:** HTTP/1.1 206 semantics explicitly allow servers to return a smaller range than requested. The client (e.g., DuckDB) will read the returned `Content-Range` header and automatically issue a subsequent request for the remainder.

### 3. Active "Zombie Process" Health Checks
**Vulnerability:** `zs_server_status()` only checks if the OS process exists (`is_alive()`), completely missing scenarios where the R event loop is hung (e.g., stuck in an infinite loop or blocked I/O).
**Solution:**
*   **Ping-based Verification:** Update `zs_server_status(ping = TRUE)` to optionally send a highly-timeout-restricted IPC ping (`/ping`).
*   **Startup Validation:** In `start_server()`, use the ping-enabled status check. If the process is alive but unresponsive, it's a zombie—kill it and restart cleanly.

### 4. IPC Token Security
**Vulnerability:** `rlang::hash(runif(1))` relies on R's global RNG state, which is predictable.
**Solution:**
*   **Cryptographically Stronger Token:** Generate a 64-character alphanumeric string to achieve high entropy:
    ```r
    ipc_token <- paste(sample(c(letters, LETTERS, 0:9), 64, replace = TRUE), collapse = "")
    ```

### 5. Graceful IPC Error Handling
**Vulnerability:** `.send_ipc()` calls `stop()` immediately on any failure, crashing the user's main analysis session if the background server blips.
**Solution:**
*   **Fail-Safe IPC:** Add a `stop_on_error = TRUE` flag to `.send_ipc()`. 
*   When checking status via `zs_server_status()`, set `stop_on_error = FALSE` and use a short timeout. If it fails, gracefully return `FALSE` rather than crashing the parent session.

### 6. Process Lifecycle Management
**Vulnerability:** The background process stays alive if the package is unloaded or if the main R session crashes unexpectedly without triggering the `callr` supervisor correctly.
**Solution:**
*   **`.onUnload` Hook:** Create an `R/zzz.R` file and add an `.onUnload` hook that explicitly calls `zs_stop_server()`.

### 7. Reduce Log Spam
**Vulnerability:** The server logs *every* successful IPC ping and route check, causing the log file to balloon in size rapidly.
**Solution:**
*   **Targeted Logging:** Remove the verbose logging for successful `/ping` and `/register` requests. Only log server startup, shutdown, warnings, and explicit `500` errors.