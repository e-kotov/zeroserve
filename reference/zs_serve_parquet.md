# Serve data via Out-Of-Core Parquet export

Serve data via Out-Of-Core Parquet export

## Usage

``` r
zs_serve_parquet(
  data,
  query = NULL,
  engine = c("duckdb", "arrow"),
  layer_id = "stream",
  crs = NULL
)
```

## Arguments

- data:

  A DuckDB connection OR a spatial object (sf, data.frame, etc.).

- query:

  A SQL query string or table name (required if 'data' is a connection).

- engine:

  The engine to use for writing Parquet: "duckdb" or "arrow".

- layer_id:

  A unique identifier for this data stream.

- crs:

  Optional Coordinate Reference System.

## Value

A URL string pointing to the localhost background server.
