A high-performance, frontend-agnostic transport layer that streams large
datasets directly to the browser for use in htmlwidgets, Shiny apps, or
custom web frontends. It leverages zero-copy Arrow IPC streams (via
shared memory) or HTTP Range requests (for disk-based files) to bypass
the bottlenecks of JSON serialization. While general-purpose, it
provides specialized support for DuckDB, sf, and Arrow objects, bridging
R memory to web visualizations with minimal overhead.
