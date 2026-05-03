# Plan: core_transport_20260503

## Phase 1: Background Server Infrastructure
- [ ] Task: Research - Analyze existing prototype logic in `R_drafts/` to identify reusable patterns
- [ ] Task: Infrastructure - Set up `httpuv` server logic for serving binary blobs
- [ ] Task: Infrastructure - Implement background process management using `callr`
- [ ] Task: Conductor - User Manual Verification 'Background Server Infrastructure' (Protocol in workflow.md)

## Phase 2: In-Memory Transport (serve_mori)
- [ ] Task: Implementation - Develop `serve_mori()` to convert `sf`/Arrow objects to streams
- [ ] Task: Verification - Write unit tests for `serve_mori()` using `testthat`
- [ ] Task: Conductor - User Manual Verification 'In-Memory Transport' (Protocol in workflow.md)

## Phase 3: Out-of-Core Transport (serve_parquet)
- [ ] Task: Implementation - Develop `serve_parquet()` leveraging DuckDB's Parquet export
- [ ] Task: Verification - Write unit tests for `serve_parquet()` using `testthat`
- [ ] Task: Conductor - User Manual Verification 'Out-of-Core Transport' (Protocol in workflow.md)
