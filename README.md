

<!-- README.md is generated from README.qmd. Please edit that file -->

# zeroserve: High-Performance Inter-Process Communication and Data Serving <a href="https://e-kotov.github.io/zeroserve/"><img src="man/figures/logo.png" align="right" width="200" alt="zeroserve website" /></a>

<!-- badges: start -->

[![Project Status:
Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/e-kotov/zeroserve/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/e-kotov/zeroserve/actions/workflows/R-CMD-check.yaml)
[![codecov](https://codecov.io/gh/e-kotov/zeroserve/branch/main/graph/badge.svg)](https://app.codecov.io/gh/e-kotov/zeroserve)
<!-- badges: end -->

A high-performance, frontend-agnostic transport layer that serves data
to browsers for use in `htmlwidgets`, `Shiny` apps, or custom web
frontends.

`zeroserve` provides disk-free, copy-minimized **Arrow IPC** transport
(via shared memory) or **HTTP Range requests** for disk-backed files.
Arrow inputs are serialized to one in-memory IPC buffer and copied once
into Mori shared memory; the complete result is materialized before the
URL is returned.

## Installation

You can install the development version of `zeroserve` from GitHub with:

``` r
# install.packages("pak")
pak::pak("e-kotov/zeroserve")
```

## Example

### Serving an Arrow Stream (In-Memory)

Serve an `sf` object from R memory at a local URL without a temporary
Arrow payload file.

``` r
library(zeroserve)

# Load some spatial data
nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)

# Serve it!
url <- zs_serve_arrow(nc)
# [1] "http://127.0.0.1:8080/stream.arrow"
```

DuckSpatial queries use their native GeoArrow stream. The URL-based
integration avoids a data attachment file:

``` r
countries <- duckspatial::ddbs_open_dataset(
  system.file("spatial/countries.geojson", package = "duckspatial")
)
url <- zs_serve_arrow(countries, layer_id = "countries")

mapgl::maplibre(projection = "mercator") |>
  deckglgeoarrow::addSource(id = "countries", url = url) |>
  deckglgeoarrow::addGeoArrowPolygonLayer(
    source = "countries",
    layer_id = "countries",
    geom_column_name = attr(countries, "sf_column"),
    tooltip = "NAME_ENGL"
  )
```

In contrast, passing an object through `geoarrowWidget(data =)` writes
an attachment file. For web maps, transform coordinates lazily in
DuckSpatial to the longitude/latitude CRS expected by the renderer
before serving.

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
    - For **Arrow**, the complete result is serialized into an R raw
      vector, copied once into POSIX shared memory using `{mori}`, and
      retained for the URL lifetime. The background server maps that
      shared buffer without another parent-to-server R copy.
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
