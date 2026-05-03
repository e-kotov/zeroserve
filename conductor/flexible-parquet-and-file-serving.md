# Plan: Flexible Parquet and File Serving

## Objective
1. Implement `zs_serve_file()` to allow users to directly serve any existing file (e.g., pre-computed `.parquet`, `.pmtiles`, or `.tif` files) with HTTP Range request support, bypassing R memory and database engines entirely.
2. Refactor `zs_serve_parquet()` to support two distinct backends (`arrow` and `duckdb`) for exporting R objects to Parquet on-the-fly. This flexibility allows users without DuckDB to use the package, and allows us to benchmark the two approaches.

## Key Files & Context
- `R/serve.R`: Add `zs_serve_file()`. Refactor `zs_serve_parquet()` to accept an `engine` argument.
- `R/server.R`: Generalize the `res$type == "parquet"` branch in the background server to handle any `res$type == "file"`, as the Range request logic applies to any file on disk.
- `DESCRIPTION`: Add `arrow` to `Suggests`.
- `tests/testthat/test-serve.R`: Add tests for `zs_serve_file()` and both engines of `zs_serve_parquet()`.

## Implementation Steps
1. **Generalize Server Logic (`R/server.R`)**:
   - Change the check `if (res$type == "parquet")` to `if (res$type == "file")`. The efficient range-serving logic applies equally well to any file on disk.

2. **Implement `zs_serve_file()` (`R/serve.R`)**:
   - Signature: `zs_serve_file(file_path, layer_id = "stream")`
   - Validates that `file_path` exists.
   - Registers it with the background server as `type = "file"`.
   - Returns the URL.

3. **Refactor `zs_serve_parquet()` (`R/serve.R`)**:
   - Change signature to: `zs_serve_parquet(data, query = NULL, engine = c("duckdb", "arrow"), layer_id = "stream", crs = NULL)`
   - **DuckDB Engine**:
     - If `data` is a connection, require `query`.
     - Execute the existing `COPY (...) TO ... (FORMAT PARQUET)` logic.
   - **Arrow Engine**:
     - If `data` is a `data.frame` or `sf` object:
       - Apply CRS transformation to EPSG:4326 if a geometry column exists (using `sf`).
       - Use `arrow::write_parquet()` to write the object directly to disk.
   - Both branches will register the resulting temporary file via `zs_serve_file()` internally or manually register it as `type = "file"`.

4. **Update `DESCRIPTION`**:
   - Add `arrow` to the `Suggests` field.

5. **Testing (`tests/testthat/test-serve.R`)**:
   - Write a test for `zs_serve_file()` using a dummy text file.
   - Write a test for `zs_serve_parquet()` using the `arrow` engine with both spatial (`sf`) and non-spatial (`data.frame`) inputs.
   - Verify existing DuckDB tests still pass.

## Verification & Testing
- Run `devtools::document()` and `devtools::check()`.
- Compare performance/usability of the two engines in a separate scratch script later.