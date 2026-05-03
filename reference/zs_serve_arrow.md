# Serve an object via In-Memory Arrow IPC (mori)

Serve an object via In-Memory Arrow IPC (mori)

## Usage

``` r
zs_serve_arrow(x, layer_id = "stream", crs = NULL)
```

## Arguments

- x:

  A spatial object (e.g. `sf`, `duckspatial_df`).

- layer_id:

  A unique identifier for this data stream.

- crs:

  Optional Coordinate Reference System.

## Value

A URL string pointing to the localhost background server.
