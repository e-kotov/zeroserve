# Introduction to zeroserve

`zeroserve` provides a high-performance transport layer for streaming
large datasets from R to web frontends. It is designed to be
frontend-agnostic and supports various data formats and sources.

## Core Concepts

The package focuses on two main methods of serving data:

1.  **Arrow IPC Streams:** Best for in-memory data that should be shared
    with minimal overhead using shared memory.
2.  **Parquet Files:** Best for larger-than-memory data or data already
    on disk, served via HTTP with support for range requests.

## Basic Usage

### Serving an Arrow Stream

To serve an `sf` object as an Arrow stream:

``` r

library(zeroserve)
library(sf)
```

    Linking to GEOS 3.12.1, GDAL 3.8.4, PROJ 9.4.0; sf_use_s2() is TRUE

``` r

# Create some sample data
nc <- st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)

# Serve the data
url <- zs_serve_arrow(nc)
print(url)
```

    [1] "http://127.0.0.1:8045/stream.arrow"

``` r

# Verify the data (e.g., using curl)
# This simulates what a frontend would do
res <- curl::curl_fetch_memory(url)
cat("Fetched", length(res$content), "bytes of Arrow IPC data\n")
```

    Fetched 56656 bytes of Arrow IPC data

``` r

# Clean up when done
zs_stop_server()
```

    [1] TRUE

### Serving a Parquet File

To serve a DuckDB table as a streamable Parquet file:

``` r

library(zeroserve)
library(DBI)

# Connect to DuckDB
con <- dbConnect(duckdb::duckdb())

# Load built-in data into DuckDB
dbWriteTable(con, "mtcars", mtcars)

# Serve a query result
url <- zs_serve_parquet(con, "SELECT * FROM mtcars", layer_id = "cars")
print(url)
```

    [1] "http://127.0.0.1:8305/cars.parquet"

``` r

# Verify the data
# The arrow package can read directly from the URL
df <- arrow::read_parquet(url)
head(df)
```

    # A data frame: 6 × 11
        mpg   cyl  disp    hp  drat    wt  qsec    vs    am  gear  carb
    * <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl>
    1  21       6   160   110  3.9   2.62  16.5     0     1     4     4
    2  21       6   160   110  3.9   2.88  17.0     0     1     4     4
    3  22.8     4   108    93  3.85  2.32  18.6     1     1     4     1
    4  21.4     6   258   110  3.08  3.22  19.4     1     0     3     1
    5  18.7     8   360   175  3.15  3.44  17.0     0     0     3     2
    6  18.1     6   225   105  2.76  3.46  20.2     1     0     3     1

``` r

# Clean up
zs_stop_server()
```

    [1] TRUE

``` r

dbDisconnect(con, shutdown = TRUE)
```

## Advanced: HTTP Range Requests

One of the key features of `zeroserve` is its support for HTTP Range
requests. This allows client-side applications (like those using
[DuckDB-Wasm](https://duckdb.org/docs/api/wasm/overview)) to fetch only
the specific parts of a Parquet file they need, rather than downloading
the entire file.

``` r

library(zeroserve)

# Serve a file (e.g., the built-in mtcars as a temp file)
temp_p <- tempfile(fileext = ".parquet")
arrow::write_parquet(mtcars, temp_p)
url <- zs_serve_file(temp_p)

# Fetch only the first 100 bytes using a Range header
h <- curl::new_handle()
curl::handle_setheaders(h, Range = "bytes=0-99")
res <- curl::curl_fetch_memory(url, handle = h)

# Check the response
print(res$status_code) # Should be 206 (Partial Content)
```

    [1] 206

``` r

cat("Fetched", length(res$content), "bytes\n")
```

    Fetched 100 bytes

``` r

print(res$headers["content-range"])
```

    [1] 00

``` r

# Clean up
zs_stop_server()
```

    [1] TRUE

## Next Steps

For more information, please refer to the function documentation.
