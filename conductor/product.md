# Initial Concept
A high-performance, frontend-agnostic interoperability layer for R. It bridges R memory to web-based frontends (htmlwidgets, Shiny, etc.) by serving zero-copy Arrow IPC streams and disk-based files (via HTTP Range requests). While general-purpose, it provides specialized support for the spatial ecosystem (DuckDB, sf, geoarrow) to achieve comparable results to Python's lonboard.

# Target Audience
- Data Scientists: R users analyzing large datasets (spatial or otherwise) who need fast visual feedback.
- Package Developers: Developers building downstream visualization tools or dashboards in R.
- GIS Analysts: Professionals working with massive spatial data via DuckDB.

# Primary Workflow
**High-Throughput Data Transport:** The tool provides a low-latency bridge that delivers massive datasets directly to browser-based renderers without the overhead of JSON serialization or full-file downloads.

# Key Differentiator
**Zero-Overhead Serving:** By leveraging shared memory and HTTP Range requests, it allows browsers to stream exactly what they need from R memory or disk, bypassing standard R bottlenecks.