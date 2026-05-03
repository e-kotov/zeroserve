# Specification: core_transport_20260503

## Overview
Implement the minimal core transport layer for `zeroserve`. This layer will provide a mechanism to stream data from R/DuckDB to a frontend renderer (like `geoarrowWidget`) using zero-copy binary formats (Arrow/Parquet) served over a local background server.

## Goals
- Create a background server using `httpuv` and `callr`.
- Implement `zs_serve_arrow()` for streaming in-memory objects via `mori` (ALTREP).
- Implement `zs_serve_parquet()` for streaming data via DuckDB or Arrow engines.
- Implement `zs_serve_file()` for serving any existing file directly.
- Support HTTP Range requests for efficient out-of-core streaming.
- Return a stable localhost URL that can be consumed by frontend renderers.

## Technical Details
- **Server:** Use `httpuv` to handle HTTP Range requests. Run in a background process via `callr` to prevent blocking the R session.
- **Data Formats:** Arrow IPC for in-memory data, Parquet for out-of-core data, or any binary file.
- **URL Structure:** `http://localhost:<port>/<data_id>`
- **Optimizations:** Use `httpuv` optimized file serving for full downloads and binary connections with `seek()` for partial Range requests.

## Success Criteria
- `zs_serve_arrow(sf_object)` returns a valid URL.
- `zs_serve_parquet(duckdb_table)` returns a valid URL.
- `zs_serve_file(path)` returns a valid URL.
- Localhost URLs are accessible and return the correct binary payload (verified via deep validation of schemas/metadata).
- HTTP Range requests (206 Partial Content) are supported and verified by tests.
