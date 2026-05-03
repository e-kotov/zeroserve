# Plan: core_transport_20260503

## Phase 1: Background Server Infrastructure
- [x] Task: Research - Analyze existing prototype logic in `R_drafts/` to identify reusable patterns
- [x] Task: Infrastructure - Set up `httpuv` server logic for serving binary blobs
- [x] Task: Infrastructure - Implement background process management using `callr`
- [x] Task: Infrastructure - Implement manual HTTP Range parsing for partial content serving
- [x] Task: Infrastructure - Implement user controls (`zs_stop_server`, `zs_clear_registry`)
- [x] Task: Conductor - User Manual Verification 'Background Server Infrastructure' (Protocol in workflow.md)

## Phase 2: In-Memory Transport (zs_serve_arrow)
- [x] Task: Implementation - Develop `zs_serve_arrow()` to convert `sf`/Arrow objects to streams
- [x] Task: Implementation - Create `as_arrow_stream()` internal converter with spatial auto-detection
- [x] Task: Verification - Write unit tests for `zs_serve_arrow()` using `testthat`
- [x] Task: Verification - Add deep validation tests for Arrow IPC metadata and schemas
- [x] Task: Conductor - User Manual Verification 'In-Memory Transport' (Protocol in workflow.md)

## Phase 3: Out-of-Core Transport (zs_serve_parquet)
- [x] Task: Implementation - Develop `zs_serve_parquet()` leveraging DuckDB's Parquet export
- [x] Task: Implementation - Add `arrow` engine support for Parquet generation
- [x] Task: Implementation - Implement `zs_serve_file()` for generic file serving
- [x] Task: Verification - Write unit tests for `zs_serve_parquet()` and `zs_serve_file()`
- [x] Task: Verification - Write tests specifically for HTTP Range requests (206 status)
- [x] Task: Conductor - User Manual Verification 'Out-of-Core Transport' (Protocol in workflow.md)

## Phase 4: Package Refinement
- [x] Task: Refactoring - Rename package to `zeroserve`
- [x] Task: Dependencies - Minimize dependency tree (move `sf`, `duckdb` to Suggests)
- [x] Task: Validation - Ensure clean `R CMD check` and complete test coverage
