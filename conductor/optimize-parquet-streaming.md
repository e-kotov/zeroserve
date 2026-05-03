# Plan: Optimize Parquet Streaming with HTTP Range Requests

## Objective
The current implementation of `zs_serve_parquet` correctly uses DuckDB to dump massive datasets to a Parquet file on disk. However, the background `httpuv` server reads the *entire* file into memory (`readBin`) to serve it, completely defeating the purpose of out-of-core storage. We need to refactor the background server to handle HTTP Range requests efficiently, allowing the browser (via `parquet-wasm`) to fetch only specific byte ranges (like metadata footers or specific row groups) without loading the whole file into R's memory.

## Key Files & Context
- `R/server.R`: The `app$call` logic needs to be updated to parse `req$HTTP_RANGE`.

## Implementation Steps
1. **Refactor `server.R` Parquet Route**:
   - Check for `req$HTTP_RANGE`.
   - **If no Range header**: Use `httpuv`'s efficient file serving capability by returning `body = list(file = res$path)` instead of reading the file into memory. Set status to `200`.
   - **If Range header exists**:
     - Parse the `bytes=start-end` format.
     - Handle cases like `bytes=start-` (to end of file).
     - Seek to the `start` byte using a binary file connection.
     - Read only the requested chunk size.
     - Return status `206 Partial Content`.
     - Include `Content-Range: bytes start-end/total_size` and `Content-Length: chunk_size` headers.
2. **Add CORS support for Ranges**:
   - Ensure `Access-Control-Expose-Headers: Content-Length, Content-Range` is included so the browser JS can see the response headers.

## Verification & Testing
1. Add a unit test in `tests/testthat/test-serve.R` that makes a manual HTTP Range request (e.g., using `curl::curl_fetch_memory` with a `Range` header) to the parquet URL and verifies a `206` status and correct chunk size.
2. Run `devtools::test()` to confirm the implementation.