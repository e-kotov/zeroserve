# Serve an existing file via HTTP with Range request support

Serve an existing file via HTTP with Range request support

## Usage

``` r
zs_serve_file(file_path, layer_id = "stream")
```

## Arguments

- file_path:

  Path to the file on disk.

- layer_id:

  A unique identifier for this data stream.

## Value

A URL string pointing to the localhost background server.

## Examples

``` r
if (FALSE) { # \dontrun{
temp_f <- tempfile(fileext = ".txt")
writeLines("hello world", temp_f)
url <- zs_serve_file(temp_f)
print(url)
zs_stop_server()
} # }
```
