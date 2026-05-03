# Plan: Rename Internal Converter and Strengthen Test Validation

## Objective
1. Rename the internal converter `as_zs_stream()` to `as_arrow_stream()` for better technical accuracy.
2. Enhance test suite to explicitly verify that spatial metadata (GeoArrow extension headers) is present when serving `sf` objects and absent when serving regular tables.

## Key Files & Context
- `R/utils-arrow.R`: Rename the function and update logic.
- `R/serve.R`: Update internal calls.
- `tests/testthat/test-serve.R`: Update tests to use `nanoarrow` to inspect downloaded stream metadata.

## Implementation Steps
1. **Refactor Function Name**: Rename `as_zs_stream` to `as_arrow_stream`.
2. **Enhance `as_arrow_stream`**: Ensure it explicitly uses `nanoarrow` to wrap the stream even for non-spatial data, ensuring a consistent return type.
3. **Deep Validation Tests**:
   - Update `zs_serve_arrow` tests.
   - Use `curl::curl_download` to fetch the stream.
   - Open the downloaded file using `nanoarrow::read_nanoarrow_array_stream()`.
   - Inspect `stream$get_schema()`.
   - **Assertion 1**: For `sf` inputs, verify that the `geometry` column has the `ARROW:extension:name` attribute set to a `geoarrow.*` value.
   - **Assertion 2**: For standard `data.frame` inputs, verify that no such spatial extension metadata exists.

## Verification & Testing
- Run `devtools::test()` and ensure the new metadata assertions pass.
- Run `devtools::check()` to ensure no regressions.