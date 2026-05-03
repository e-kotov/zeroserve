

<!-- README.md is generated from README.qmd. Please edit that file -->

# zeroserve: High-Performance Inter-Process Communication and Data Serving <a href="https://e-kotov.github.io/zeroserve/"><img src="man/figures/logo.png" align="right" width="200" alt="zeroserve website" /></a>

<!-- badges: start -->

[![Project Status:
Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/e-kotov/zeroserve/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/e-kotov/zeroserve/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

A high-performance, frontend-agnostic transport layer that streams large
datasets directly to the browser for use in `htmlwidgets`, `Shiny` apps,
or custom web frontends.

`zeroserve` leverages zero-copy **Arrow IPC** streams (via shared
memory) or **HTTP Range requests** (for disk-based files) to bypass the
bottlenecks of JSON serialization. While general-purpose, it provides
specialized support for DuckDB, sf, and Arrow objects, bridging R memory
to web visualizations with minimal overhead.

## Installation

You can install the development version of `zeroserve` from GitHub with:

``` r
# install.packages("pak")
pak::pak("e-kotov/zeroserve")
```

## Example

### Serving an Arrow Stream (In-Memory)

Serve an `sf` object directly from R memory to a local URL with zero
copies.

``` r
library(zeroserve)

# Load some spatial data
nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)

# Serve it!
url <- zs_serve_arrow(nc)
# [1] "http://127.0.0.1:8080/stream.arrow"
```

### Serving a Parquet File (Out-of-Core)

Serve a massive DuckDB table as a Parquet stream supporting HTTP Range
requests.

``` r
library(DBI)
con <- dbConnect(duckdb::duckdb())

# ... perform massive DuckDB operations ...

# Serve the result as a streamable Parquet file
url <- zs_serve_parquet(con, "SELECT * FROM massive_table")
# [1] "http://127.0.0.1:8080/stream.parquet"
```

## How it works

1.  **The Server:** When you call a `zs_serve_*` function, `zeroserve`
    spawns a lightweight background R process (via `{callr}`) running an
    `{httpuv}` server.
2.  **The Data:**
    - For **Arrow**, data is shared via POSIX shared memory (using
      `{mori}`), allowing the background server to read R’s memory with
      zero overhead.
    - For **Parquet**, data is written to a temporary file, which the
      server then hosts with support for partial content requests.
3.  **The Lifecycle:** The background server and its associated
    resources are automatically cleaned up when the R session ends or
    the package is unloaded.

## Citation

Kotov E (2026). *zeroserve: High-Performance Inter-Process Communication
and Data Serving*. R package version 0.1.0.

BibTeX:

    @Manual{zeroserve,
      title = {zeroserve: High-Performance Inter-Process Communication and Data Serving},
      author = {Egor Kotov},
      year = {2026},
      note = {R package version 0.1.0},
    }

## License

MIT + file LICENSE
