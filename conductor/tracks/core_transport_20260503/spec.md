# Specification: core_transport_20260503

## Overview
Implement the minimal core transport layer for `streamdeck`. This layer will provide a mechanism to stream spatial data from R/DuckDB to a frontend renderer (like `geoarrowWidget`) using zero-copy binary formats (Arrow/Parquet) served over a local background server.

## Goals
- Create a background server using `httpuv` and `callr`.
- Implement `serve_mori()` for streaming in-memory objects via `mori` (ALTREP).
- Implement `serve_parquet()` for streaming out-of-core data via DuckDB's Parquet export.
- Return a stable localhost URL that can be consumed by frontend renderers.

## Technical Details
- **Server:** Use `httpuv` to handle HTTP Range requests. Run in a background process via `callr` to prevent blocking the R session.
- **Reference Logic:** Use the prototype code in `R_drafts/` (specifically `add_streaming_layer.R` and `streamdeck_interceptor.R`) as a reference for the server and transport logic.
- **Data Formats:** Arrow IPC for in-memory data, Parquet for out-of-core data.
- **URL Structure:** `http://localhost:<port>/<session_id>/<data_id>`

## Success Criteria
- `serve_mori(sf_object)` returns a valid URL.
- `serve_parquet(duckdb_table)` returns a valid URL.
- Localhost URLs are accessible and return the correct binary payload.
- Automated tests verify the streaming functionality.
