# Technology Stack

## Core Language
- **R:** The primary development environment and user-facing API language.

## Data Backends & Structures
- **duckdb / duckspatial:** Used for massive out-of-core spatial data processing and Parquet generation.
- **arrow / nanoarrow / geoarrow:** Provides zero-copy, binary-oriented data structures for efficient memory handling and transport.
- **sf:** Standard library for working with simple features in R.

## Transport & Interoperability
- **mori:** Facilitates in-memory Inter-Process Communication (IPC) and zero-copy binary arrays via ALTREP.
- **httpuv / callr:** Powers the lightweight background server for streaming data over HTTP with manual Range request support.
- **curl:** Used for high-performance validation and automated testing of the transport layer.

## Frontend & Rendering
- **htmlwidgets:** Bridges R and JavaScript for browser-based rendering.
- **mapgl / geoarrowWidget / geoarrowDeckglLayers:** Handles the actual GPU-accelerated frontend rendering and styling in the browser, driven by the binary streams delivered by the package.