# Plan: Improve Test Coverage and Server Management

## Objective
1. Improve test coverage by addressing edge cases (non-spatial data, empty objects, invalid queries).
2. Implement user controls for background server management (`zs_stop_server()` and `zs_clear_registry()`).
3. Refactor all exported functions to use a consistent `zs_` prefix to prevent namespace collisions and improve discoverability.

## Key Files & Context
- `R/serve.R`: Rename `serve_arrow` and `serve_parquet` to `zs_serve_arrow` and `zs_serve_parquet`.
- `R/server.R`: Add `zs_stop_server()` and `zs_clear_registry()` functions.
- `R/utils-arrow.R`: Verify behavior with non-spatial and empty data.
- `tests/testthat/test-serve.R`: Update test function names and add edge case tests.
- `NAMESPACE`: Update exports.
- `private/test_geoarrowWidget.R`: Update function names.

## Implementation Steps
1. **API Prefix Refactoring**:
   - Rename `serve_arrow()` to `zs_serve_arrow()`.
   - Rename `serve_parquet()` to `zs_serve_parquet()`.
   - Update all internal calls and documentation.
2. **Server Management Functions**:
   - Implement `zs_stop_server()`: Kills the background `callr` process and sets `.zeroserve_env$server <- NULL`.
   - Implement `zs_clear_registry()`: Clears `.zeroserve_env$mori_buffers`, overwrites the registry `.rds` file with an empty list, and frees up memory.
3. **Edge Case Test Coverage**:
   - Add test for `zs_serve_arrow()` with a non-spatial standard `data.frame`.
   - Add test for `zs_serve_arrow()` with an empty `sf` object (0 rows).
   - Add test for `zs_serve_parquet()` with a non-spatial DuckDB table.
   - Add test for `zs_serve_parquet()` with an invalid SQL query (expecting graceful error).
   - Add test verifying `zs_stop_server()` actually terminates the process.

## Verification & Testing
- Run `devtools::document()` to update namespaces and help files.
- Run `devtools::test()` to ensure all new edge case tests pass and server management functions work as intended.
- Ensure package still passes `R CMD check`.