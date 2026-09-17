# Served URLs carry an unguessable per-resource capability token as the first
# path segment: http://127.0.0.1:<port>/<32 hex chars>/<layer>.<ext>
expect_zs_url <- function(url, path_regex) {
  expect_match(
    url,
    paste0("^http://127\\.0\\.0\\.1:[0-9]+/[0-9a-f]{32}/", path_regex, "$")
  )
}

zs_token <- function(url) sub("^.*/([0-9a-f]{32})/[^/]*$", "\\1", url)

# Every data-plane rejection must look like this on the wire, whatever the
# reason: no token, a malformed one, one belonging to another resource, an
# unknown path, or a resource whose backing file is gone.
expect_uniform_404 <- function(res) {
  expect_equal(res$status_code, 404L)
  expect_equal(rawToChar(res$content), "Not Found")
  expect_false(any(grepl(
    "Access-Control-",
    curl::parse_headers(res$headers),
    ignore.case = TRUE
  )))
}

expect_arrow_download <- function(url) {
  temp_out <- tempfile(fileext = ".arrow")
  curl::curl_download(url, temp_out, quiet = TRUE)
  expect_true(file.size(temp_out) > 0)
  nanoarrow::read_nanoarrow(temp_out)
}

test_that("zs_serve_file handles generic files", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")

  temp_f <- tempfile(fileext = ".txt")
  writeLines("hello world", temp_f)

  url <- zs_serve_file(temp_f, layer_id = "test_file")
  expect_zs_url(url, "test_file\\.txt")

  temp_out <- tempfile()
  # Using curl directly to avoid weird R download.file localhost SSL issues
  curl::curl_download(url, temp_out, quiet = TRUE)
  expect_equal(readLines(temp_out), "hello world")
})

test_that("zs_serve_parquet handles arrow engine (non-spatial)", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("curl")

  df <- data.frame(a = 1:5, b = letters[1:5])
  url <- zs_serve_parquet(df, engine = "arrow", layer_id = "arrow_non_spatial")

  expect_zs_url(url, "arrow_non_spatial\\.parquet")

  temp_out <- tempfile(fileext = ".parquet")
  curl::curl_download(url, temp_out, quiet = TRUE)
  expect_true(file.size(temp_out) > 0)

  res_df <- arrow::read_parquet(temp_out)
  expect_equal(nrow(res_df), 5)
  expect_equal(res_df$b, letters[1:5])
})

test_that("zs_serve_parquet handles arrow engine (spatial)", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("sf")
  skip_if_not_installed("curl")

  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
  nc <- nc[1:5, ]

  url <- zs_serve_parquet(nc, engine = "arrow", layer_id = "arrow_spatial")
  expect_zs_url(url, "arrow_spatial\\.parquet")

  temp_out <- tempfile(fileext = ".parquet")
  curl::curl_download(url, temp_out, quiet = TRUE)

  # Verify with arrow instead of sf::st_read as sf might not have parquet driver
  res_table <- arrow::read_parquet(temp_out)
  expect_equal(nrow(res_table), 5)
  expect_true("geometry" %in% names(res_table))
})

test_that("zs_serve_arrow handles standard data.frame (non-spatial)", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")
  skip_if_not_installed("nanoarrow")

  df <- data.frame(a = 1:5, b = letters[1:5])
  url <- zs_serve_arrow(df, layer_id = "test_df")

  expect_zs_url(url, "test_df\\.arrow")

  temp_out <- tempfile(fileext = ".arrow")
  curl::curl_download(url, temp_out, quiet = TRUE)
  expect_true(file.size(temp_out) > 0)

  # Deep Validation: Open as stream and check schema
  stream <- nanoarrow::read_nanoarrow(temp_out)
  schema <- stream$get_schema()

  # Non-spatial data should NOT have GeoArrow extension metadata
  geom_field <- schema$children$geometry # Should be NULL
  expect_null(geom_field)

  # Check standard columns exist
  expect_true("a" %in% names(schema$children))
  expect_true("b" %in% names(schema$children))
})

test_that("zs_serve_arrow handles DuckDB connection with table name", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")
  skip_if_not_installed("nanoarrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  skip_if_not_installed("arrow")

  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  df <- data.frame(a = 1:5, b = letters[1:5])
  DBI::dbWriteTable(con, "test_table", df)

  url <- zs_serve_arrow(
    con,
    query = "test_table",
    layer_id = "test_duckdb_table"
  )
  expect_zs_url(url, "test_duckdb_table\\.arrow")

  stream <- expect_arrow_download(url)
  res <- as.data.frame(stream)
  expect_equal(res$a, 1:5)
  expect_equal(res$b, letters[1:5])
})

test_that("zs_serve_arrow handles DuckDB connection with SQL query", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")
  skip_if_not_installed("nanoarrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  skip_if_not_installed("arrow")

  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  df <- data.frame(a = 1:5, b = letters[1:5])
  DBI::dbWriteTable(con, "test_table", df)

  url <- zs_serve_arrow(
    con,
    query = "SELECT a, b FROM test_table WHERE a >= 3 ORDER BY a",
    layer_id = "test_duckdb_sql"
  )
  expect_zs_url(url, "test_duckdb_sql\\.arrow")

  stream <- expect_arrow_download(url)
  res <- as.data.frame(stream)
  expect_equal(res$a, 3:5)
  expect_equal(res$b, letters[3:5])
})

test_that("zs_serve_arrow handles DuckDB-backed dbplyr tables", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")
  skip_if_not_installed("nanoarrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  skip_if_not_installed("arrow")
  skip_if_not_installed("dbplyr")
  skip_if_not_installed("dplyr")

  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  df <- data.frame(a = 1:5, b = letters[1:5])
  DBI::dbWriteTable(con, "test_table", df)
  tbl <- dplyr::tbl(con, "test_table")

  url <- zs_serve_arrow(tbl, layer_id = "test_duckdb_tbl")
  expect_zs_url(url, "test_duckdb_tbl\\.arrow")

  stream <- expect_arrow_download(url)
  res <- as.data.frame(stream)
  expect_equal(res$a, 1:5)
  expect_equal(res$b, letters[1:5])
})

test_that("zs_serve_arrow requests native DuckSpatial streams", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")
  skip_if_not_installed("nanoarrow")

  calls <- new.env(parent = emptyenv())
  calls$native <- NULL
  calls$chunk_size <- NULL
  as_nanoarrow_array_stream.fake_duckspatial_df <- function(
    x,
    ...,
    native = FALSE,
    chunk_size = 1e6
  ) {
    calls$native <- native
    calls$chunk_size <- chunk_size
    nanoarrow::as_nanoarrow_array_stream(data.frame(a = x$a, b = x$b))
  }
  registerS3method(
    "as_nanoarrow_array_stream",
    "fake_duckspatial_df",
    as_nanoarrow_array_stream.fake_duckspatial_df,
    envir = asNamespace("nanoarrow")
  )

  x <- structure(
    data.frame(a = 1:5, b = letters[1:5]),
    class = c("fake_duckspatial_df", "duckspatial_df", "data.frame")
  )
  url <- zs_serve_arrow(
    x,
    layer_id = "test_duckspatial_dispatch",
    chunk_size = 2
  )
  expect_zs_url(url, "test_duckspatial_dispatch\\.arrow")
  expect_identical(calls$native, TRUE)
  expect_identical(calls$chunk_size, 2)

  stream <- expect_arrow_download(url)
  res <- as.data.frame(stream)
  expect_equal(res$a, 1:5)
  expect_equal(res$b, letters[1:5])
})

test_that("zs_serve_arrow preserves native DuckSpatial GeoArrow data", {
  skip_if_not_installed("duckspatial")
  skip_if_not_installed("curl")
  skip_if_not_installed("nanoarrow")

  countries <- duckspatial::ddbs_open_dataset(
    system.file("spatial/countries.geojson", package = "duckspatial")
  )
  geom_col <- attr(countries, "sf_column")
  native_stream <- nanoarrow::as_nanoarrow_array_stream(
    countries,
    native = TRUE
  )
  native_geom_schema <- native_stream$get_schema()$children[[geom_col]]
  expected_crs_metadata <- native_geom_schema$metadata[[
    "ARROW:extension:metadata"
  ]]
  native_stream$release()
  temp_files <- .zeroserve_env$temp_files

  url <- zs_serve_arrow(countries, layer_id = "duckspatial_countries")
  response <- curl::curl_fetch_memory(url)

  expect_equal(response$status_code, 200L)
  expect_equal(.zeroserve_env$temp_files, temp_files)
  expect_identical(
    mori::is_shared(.zeroserve_env$mori_buffers$duckspatial_countries),
    TRUE
  )

  con <- rawConnection(response$content)
  on.exit(close(con), add = TRUE)
  stream <- nanoarrow::read_nanoarrow(con)
  on.exit(stream$release(), add = TRUE)
  schema <- stream$get_schema()
  geom_schema <- schema$children[[geom_col]]

  expect_equal(
    geom_schema$metadata[["ARROW:extension:name"]],
    "geoarrow.polygon"
  )
  expect_named(
    geom_schema$metadata,
    c("ARROW:extension:name", "ARROW:extension:metadata")
  )
  expect_equal(
    geom_schema$metadata[["ARROW:extension:metadata"]],
    expected_crs_metadata
  )
  expect_named(
    schema$children,
    c(
      "OGC_FID",
      "CNTR_ID",
      "NAME_ENGL",
      "ISO3_CODE",
      "CNTR_NAME",
      "FID",
      "date",
      "geom"
    )
  )
  result <- as.data.frame(stream)
  expect_equal(result$NAME_ENGL[[1]], "Argentina")
})

test_that("zs_serve_arrow requires query for DuckDB connections", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")

  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  expect_error(
    zs_serve_arrow(con),
    "`query` is required when `x` is a DuckDB connection.",
    fixed = TRUE
  )
})

test_that("zs_serve_arrow handles empty sf object", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")
  skip_if_not_installed("nanoarrow")
  skip_if_not_installed("sf")

  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
  nc_empty <- nc[0, ]

  url <- zs_serve_arrow(nc_empty, layer_id = "test_empty")
  expect_zs_url(url, "test_empty\\.arrow")

  temp_out <- tempfile(fileext = ".arrow")
  curl::curl_download(url, temp_out, quiet = TRUE)
  expect_true(file.size(temp_out) > 0)

  # Verify schema matches original even if empty
  stream <- nanoarrow::read_nanoarrow(temp_out)
  schema <- stream$get_schema()
  expect_true("geometry" %in% names(schema$children))

  res <- as.data.frame(stream)
  expect_equal(nrow(res), 0)
  expect_true("geometry" %in% names(res))
})

test_that("zs_serve_parquet handles non-spatial DuckDB table", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("curl")
  skip_if_not_installed("arrow")

  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  df <- data.frame(a = 1:5, b = letters[1:5])
  DBI::dbWriteTable(con, "test_table", df)

  url <- zs_serve_parquet(
    con,
    "test_table",
    engine = "duckdb",
    layer_id = "test_parquet_df"
  )
  expect_zs_url(url, "test_parquet_df\\.parquet")

  temp_out <- tempfile(fileext = ".parquet")
  curl::curl_download(url, temp_out, quiet = TRUE)

  # Verify content
  res <- arrow::read_parquet(temp_out)
  expect_equal(nrow(res), 5)
  expect_equal(res$a, 1:5)
})

test_that("zs_serve_parquet throws error on invalid SQL", {
  skip_if_not_installed("duckdb")

  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  expect_error(zs_serve_parquet(
    con,
    "SELECT * FROM non_existent_table",
    engine = "duckdb"
  ))
})

test_that("zs_stop_server and zs_clear_registry work", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")

  # Ensure clean start
  zs_stop_server()

  df <- data.frame(a = 1)
  url <- zs_serve_arrow(df, layer_id = "test_lifecycle")

  # Registry should have one item
  reg <- zeroserve:::.send_ipc("/list")
  expect_true("/test_lifecycle.arrow" %in% names(reg))

  # Ping check
  expect_true(zs_server_status(ping = TRUE))

  # Clear registry
  zs_clear_registry()
  reg <- zeroserve:::.send_ipc("/list")
  expect_equal(length(reg), 0)
  expect_equal(length(.zeroserve_env$mori_buffers), 0)

  # Stop server
  expect_true(zs_stop_server())
  expect_null(.zeroserve_env$server)
  expect_false(zs_server_status(ping = TRUE))

  # Subsequent download should fail
  expect_error(curl::curl_download(url, tempfile(), quiet = TRUE))
})

test_that("server handles CORS OPTIONS and HEAD requests", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")

  temp_f <- tempfile(fileext = ".txt")
  writeLines("hello", temp_f)
  url <- zs_serve_file(temp_f, layer_id = "test_cors_head")

  # OPTIONS
  h <- curl::new_handle()
  curl::handle_setopt(h, customrequest = "OPTIONS")
  res_opt <- curl::curl_fetch_memory(url, handle = h)
  expect_equal(res_opt$status_code, 204)
  headers_opt <- curl::parse_headers(res_opt$headers)
  expect_true(any(grepl(
    "Access-Control-Allow-Methods",
    headers_opt,
    ignore.case = TRUE
  )))

  # HEAD
  h2 <- curl::new_handle()
  curl::handle_setopt(h2, nobody = TRUE)
  res_head <- curl::curl_fetch_memory(url, handle = h2)
  expect_equal(res_head$status_code, 200)
  expect_equal(length(res_head$content), 0)
  headers_head <- curl::parse_headers(res_head$headers)
  expect_true(any(grepl("Content-Length", headers_head, ignore.case = TRUE)))
})

test_that("register_resource prevents collision with reserved path", {
  expect_error(
    register_resource("/__zs__/hack", list(type = "none")),
    "reserved"
  )
})

test_that("zs_serve_arrow returns a valid streaming URL (spatial)", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")
  skip_if_not_installed("nanoarrow")
  skip_if_not_installed("sf")

  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
  nc <- nc[1:5, ]

  url <- zs_serve_arrow(nc, layer_id = "test_arrow")

  expect_true(is.character(url))
  expect_zs_url(url, "test_arrow\\.arrow")

  temp_out <- tempfile(fileext = ".arrow")
  res <- tryCatch(
    {
      curl::curl_download(url, temp_out, quiet = TRUE)
      TRUE
    },
    error = function(e) FALSE
  )

  if (!res) {
    if (!is.null(.zeroserve_env$server) && !.zeroserve_env$server$is_alive()) {
      cat(
        "\nServer crashed. Error:",
        .zeroserve_env$server$get_error_message(),
        "\n"
      )
    }
    cat("\nServer log:", readLines(.zeroserve_env$log_file), "\n")
  }

  expect_true(res, info = paste("Failed to download from URL:", url))
  expect_true(file.size(temp_out) > 0)

  # Deep Validation: Inspect spatial metadata
  stream <- nanoarrow::read_nanoarrow(temp_out)
  schema <- stream$get_schema()

  # Field should be renamed to 'geometry'
  geom_field <- schema$children$geometry
  expect_false(is.null(geom_field))

  # If geoarrow was used, metadata should exist
  if (requireNamespace("geoarrow", quietly = TRUE)) {
    metadata <- geom_field$metadata
    expect_true("ARROW:extension:name" %in% names(metadata))
    expect_match(metadata[["ARROW:extension:name"]], "^geoarrow\\.")
  }
})

test_that("zs_serve_parquet supports HTTP Range requests", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("curl")

  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  df <- data.frame(a = 1:100, b = rnorm(100))
  DBI::dbWriteTable(con, "test_range", df)

  url <- zs_serve_parquet(
    con,
    "test_range",
    engine = "duckdb",
    layer_id = "test_range"
  )

  # Fetch first 10 bytes
  h <- curl::new_handle()
  curl::handle_setheaders(h, "Range" = "bytes=0-9")
  res <- curl::curl_fetch_memory(url, handle = h)

  expect_equal(res$status_code, 206)
  expect_equal(length(res$content), 10)

  # Check for Content-Range header
  headers_text <- rawToChar(res$headers)
  expect_match(headers_text, "Content-Range: bytes 0-9/")

  # Fetch with open-ended range
  curl::handle_setheaders(h, "Range" = "bytes=50-")
  res2 <- curl::curl_fetch_memory(url, handle = h)
  expect_equal(res2$status_code, 206)

  # Get actual file size from registry
  reg <- zeroserve:::.send_ipc("/list")
  file_path <- reg[["/test_range.parquet"]]$path
  file_size <- file.info(file_path)$size

  expect_equal(length(res2$content), file_size - 50)
})

test_that("zs_serve_parquet returns a valid streaming URL (spatial)", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("curl")
  skip_if_not_installed("sf")
  skip_if_not_installed("arrow")

  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
  nc <- nc[1:5, ]

  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  DBI::dbExecute(con, "INSTALL spatial; LOAD spatial;")

  nc_wkt <- sf::st_as_sf(nc)
  nc_wkt$geometry <- sf::st_as_text(nc_wkt$geometry)

  DBI::dbWriteTable(con, "nc_table", as.data.frame(nc_wkt))
  DBI::dbExecute(
    con,
    "ALTER TABLE nc_table ALTER geometry TYPE GEOMETRY USING ST_GeomFromText(geometry);"
  )

  url <- zs_serve_parquet(
    con,
    "nc_table",
    engine = "duckdb",
    layer_id = "test_parquet"
  )

  expect_true(is.character(url))
  expect_zs_url(url, "test_parquet\\.parquet")

  temp_out <- tempfile(fileext = ".parquet")
  curl::curl_download(url, temp_out, quiet = TRUE)
  expect_true(file.size(temp_out) > 0)

  # Verify spatial content
  res <- arrow::read_parquet(temp_out)
  expect_true("geometry" %in% names(res))
  expect_equal(nrow(res), 5)

  # Check if we can convert back to sf.
  # DuckDB might not write GeoParquet metadata, so CRS might be NA.
  # But coordinates should be in 4326 range (approx -84 to -75 for NC)
  res_sfc <- sf::st_as_sfc(res$geometry)
  bbox <- sf::st_bbox(res_sfc)
  expect_true(bbox$xmin < 0 && bbox$xmin > -100)
  expect_true(bbox$ymin > 0 && bbox$ymin < 50)
})

test_that("zs_serve_file throws error if file does not exist", {
  expect_error(zs_serve_file("non_existent_file.txt"))
})

test_that("zs_serve_parquet handles geom column (not geometry) with duckdb engine", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("sf")

  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, "INSTALL spatial; LOAD spatial;")

  # Create table with 'geom' instead of 'geometry'
  DBI::dbExecute(
    con,
    "CREATE TABLE test_geom AS SELECT ST_GeomFromText('POINT(0 0)') AS geom"
  )

  url <- zs_serve_parquet(
    con,
    "test_geom",
    engine = "duckdb",
    layer_id = "test_geom"
  )
  expect_match(url, "test_geom\\.parquet$")

  temp_out <- tempfile(fileext = ".parquet")
  curl::curl_download(url, temp_out, quiet = TRUE)
  expect_true(file.size(temp_out) > 0)
})

test_that("zs_serve_parquet handles CRS as number and crs object", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("sf")
  skip_if_not_installed("arrow")

  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, "INSTALL spatial; LOAD spatial;")

  DBI::dbExecute(
    con,
    "CREATE TABLE test_crs AS SELECT ST_GeomFromText('POINT(0 0)') AS geometry"
  )

  # CRS as number (4326)
  url1 <- zs_serve_parquet(
    con,
    "test_crs",
    engine = "duckdb",
    layer_id = "test_crs_num",
    crs = 4326
  )
  expect_match(url1, "test_crs_num\\.parquet$")
  temp1 <- tempfile(fileext = ".parquet")
  curl::curl_download(url1, temp1, quiet = TRUE)
  res1 <- arrow::read_parquet(temp1)
  expect_true("geometry" %in% names(res1))

  # CRS as sf::crs object
  url2 <- zs_serve_parquet(
    con,
    "test_crs",
    engine = "duckdb",
    layer_id = "test_crs_obj",
    crs = sf::st_crs(4326)
  )
  expect_match(url2, "test_crs_obj\\.parquet$")
  temp2 <- tempfile(fileext = ".parquet")
  curl::curl_download(url2, temp2, quiet = TRUE)
  res2 <- arrow::read_parquet(temp2)
  expect_true("geometry" %in% names(res2))
})

test_that("zs_server_status and zs_server_logs work", {
  skip_if_not_installed("httpuv")

  # Before starting
  zs_stop_server()
  expect_false(zs_server_status())

  # Start server implicitly
  df <- data.frame(a = 1)
  zs_serve_arrow(df, layer_id = "test_status")

  expect_true(zs_server_status())

  logs <- zs_server_logs()
  expect_true(is.character(logs))
  expect_true(length(logs) > 0)
  expect_match(paste(logs, collapse = "\n"), "Background Process Started")
})

test_that("open-ended range requests work", {
  skip_if_not_installed("curl")

  temp_f <- tempfile(fileext = ".txt")
  writeLines("0123456789", temp_f)

  url <- zs_serve_file(temp_f, layer_id = "test_open_range")

  h <- curl::new_handle()
  curl::handle_setheaders(h, "Range" = "bytes=5-")
  res <- curl::curl_fetch_memory(url, handle = h)

  expect_equal(res$status_code, 206)
  expect_equal(rawToChar(res$content), "56789\n") # writeLines adds a newline
})

# Final cleanup for covr stability
# We stop the server and clear all buffers to ensure no ALTREP/background
# processes are alive when covr attempts to finalize the trace.
zs_stop_server()
zs_clear_registry()

test_that("data plane requires the per-resource capability token", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")

  temp_f <- tempfile(fileext = ".txt")
  writeBin(charToRaw("hello token"), temp_f)

  url <- zs_serve_file(temp_f, layer_id = "test_token_auth")
  expect_zs_url(url, "test_token_auth\\.txt")

  token <- zs_token(url)
  expect_match(token, "^[0-9a-f]{32}$")

  # The tokenised URL still serves the payload byte for byte.
  temp_out <- tempfile()
  curl::curl_download(url, temp_out, quiet = TRUE)
  expect_equal(
    readBin(temp_out, "raw", n = file.size(temp_f)),
    readBin(temp_f, "raw", n = file.size(temp_f))
  )

  # A single flipped hex character is rejected.
  flipped <- if (substr(token, 1L, 1L) == "0") "1" else "0"
  bad_url <- sub(token, paste0(flipped, substring(token, 2L)), url, fixed = TRUE)
  res_bad <- curl::curl_fetch_memory(bad_url)
  expect_equal(res_bad$status_code, 404L)

  # The bare registry path without the token segment is rejected.
  bare_url <- sprintf(
    "http://127.0.0.1:%s/test_token_auth.txt",
    .zeroserve_env$port
  )
  res_bare <- curl::curl_fetch_memory(bare_url)
  expect_equal(res_bare$status_code, 404L)

  # Both failures are indistinguishable from an unknown path, so the endpoint
  # is not an oracle for token or resource existence.
  res_unknown <- curl::curl_fetch_memory(sprintf(
    "http://127.0.0.1:%s/%s/no_such_layer.txt",
    .zeroserve_env$port,
    token
  ))
  expect_equal(res_unknown$status_code, 404L)
  expect_equal(rawToChar(res_bad$content), rawToChar(res_unknown$content))
  expect_equal(rawToChar(res_bare$content), rawToChar(res_unknown$content))

  # Boundary cases around the prefix strip: the token alone, with and without
  # a trailing slash.
  for (suffix in c(paste0("/", token), paste0("/", token, "/"))) {
    res_edge <- curl::curl_fetch_memory(sprintf(
      "http://127.0.0.1:%s%s",
      .zeroserve_env$port,
      suffix
    ))
    expect_equal(res_edge$status_code, 404L)
  }

  # The token-less rejection must not be readable cross-origin either.
  expect_false(any(grepl(
    "Access-Control-Allow-Origin",
    curl::parse_headers(res_bare$headers),
    ignore.case = TRUE
  )))

  # A first segment that is not exactly 32 lowercase hex characters must miss
  # before the registry is ever consulted.
  malformed <- c(
    toupper(token), # uppercase hex
    substr(token, 1L, 31L), # too short
    paste0(token, "a"), # too long
    "" # "//test_token_auth.txt"
  )
  for (seg in malformed) {
    res_mal <- curl::curl_fetch_memory(sprintf(
      "http://127.0.0.1:%s/%s/test_token_auth.txt",
      .zeroserve_env$port,
      seg
    ))
    expect_uniform_404(res_mal)
  }

  # All of them, plus the wrong-token and bare-path cases above, are the same
  # response byte for byte.
  expect_uniform_404(res_bad)
  expect_uniform_404(res_bare)
  expect_uniform_404(res_unknown)
})

test_that("Range requests work through the tokenised URL", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")

  temp_f <- tempfile(fileext = ".bin")
  writeBin(charToRaw("0123456789"), temp_f)

  url <- zs_serve_file(temp_f, layer_id = "test_token_range")

  h <- curl::new_handle()
  curl::handle_setheaders(h, Range = "bytes=2-5")
  res <- curl::curl_fetch_memory(url, handle = h)

  expect_equal(res$status_code, 206L)
  expect_equal(rawToChar(res$content), "2345")
  headers <- curl::parse_headers_list(res$headers)
  expect_equal(headers[["content-range"]], "bytes 2-5/10")
})

test_that("each resource gets its own capability token", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")

  temp_a <- tempfile(fileext = ".txt")
  temp_b <- tempfile(fileext = ".txt")
  writeBin(charToRaw("payload A"), temp_a)
  writeBin(charToRaw("payload BB"), temp_b)

  url_a <- zs_serve_file(temp_a, layer_id = "tok_a")
  url_b <- zs_serve_file(temp_b, layer_id = "tok_b")

  token_a <- zs_token(url_a)
  token_b <- zs_token(url_b)
  expect_match(token_a, "^[0-9a-f]{32}$")
  expect_match(token_b, "^[0-9a-f]{32}$")
  expect_false(identical(token_a, token_b))

  # Registering B must not have disturbed A.
  expect_equal(rawToChar(curl::curl_fetch_memory(url_a)$content), "payload A")
  expect_equal(rawToChar(curl::curl_fetch_memory(url_b)$content), "payload BB")

  # A leaked URL is a capability for one resource only: A's token cannot read
  # B's path, or the other way round.
  expect_uniform_404(curl::curl_fetch_memory(sprintf(
    "http://127.0.0.1:%s/%s/tok_b.txt",
    .zeroserve_env$port,
    token_a
  )))
  expect_uniform_404(curl::curl_fetch_memory(sprintf(
    "http://127.0.0.1:%s/%s/tok_a.txt",
    .zeroserve_env$port,
    token_b
  )))
})

test_that("re-serving a layer_id revokes the previous URL", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")

  temp_1 <- tempfile(fileext = ".txt")
  temp_2 <- tempfile(fileext = ".txt")
  writeBin(charToRaw("first"), temp_1)
  writeBin(charToRaw("second"), temp_2)

  url_1 <- zs_serve_file(temp_1, layer_id = "rotate")
  expect_equal(rawToChar(curl::curl_fetch_memory(url_1)$content), "first")

  url_2 <- zs_serve_file(temp_2, layer_id = "rotate")
  expect_false(identical(url_1, url_2))
  expect_false(identical(zs_token(url_1), zs_token(url_2)))

  expect_equal(rawToChar(curl::curl_fetch_memory(url_2)$content), "second")
  expect_uniform_404(curl::curl_fetch_memory(url_1))
})

test_that("OPTIONS preflight is gated on the capability token", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")

  temp_f <- tempfile(fileext = ".txt")
  writeBin(charToRaw("preflight"), temp_f)
  url <- zs_serve_file(temp_f, layer_id = "test_preflight_gate")
  token <- zs_token(url)

  options_fetch <- function(target) {
    h <- curl::new_handle()
    curl::handle_setopt(h, customrequest = "OPTIONS")
    curl::curl_fetch_memory(target, handle = h)
  }

  # The preflight a real client sends: the tokenised URL it was handed.
  res_ok <- options_fetch(url)
  expect_equal(res_ok$status_code, 204L)
  expect_true(any(grepl(
    "Access-Control-Allow-Methods",
    curl::parse_headers(res_ok$headers),
    ignore.case = TRUE
  )))

  # A token-less, unknown or mistokenised preflight must not confirm that a
  # zeroserve instance is listening on this port.
  probes <- c(
    sprintf("http://127.0.0.1:%s/test_preflight_gate.txt", .zeroserve_env$port),
    sprintf("http://127.0.0.1:%s/", .zeroserve_env$port),
    sprintf(
      "http://127.0.0.1:%s/%s/no_such_layer.txt",
      .zeroserve_env$port,
      token
    ),
    sprintf(
      "http://127.0.0.1:%s/%s/test_preflight_gate.txt",
      .zeroserve_env$port,
      strrep("0", 32L)
    )
  )
  for (probe in probes) {
    expect_uniform_404(options_fetch(probe))
  }
})

test_that("served data carries Referrer-Policy: no-referrer", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")

  temp_f <- tempfile(fileext = ".bin")
  writeBin(charToRaw("0123456789"), temp_f)
  url <- zs_serve_file(temp_f, layer_id = "test_referrer_policy")

  res_200 <- curl::curl_fetch_memory(url)
  expect_equal(res_200$status_code, 200L)
  expect_equal(
    curl::parse_headers_list(res_200$headers)[["referrer-policy"]],
    "no-referrer"
  )

  h <- curl::new_handle()
  curl::handle_setheaders(h, Range = "bytes=0-3")
  res_206 <- curl::curl_fetch_memory(url, handle = h)
  expect_equal(res_206$status_code, 206L)
  expect_equal(
    curl::parse_headers_list(res_206$headers)[["referrer-policy"]],
    "no-referrer"
  )
})

test_that("a missing backing file gets the uniform 404 and a log line", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")

  temp_f <- tempfile(fileext = ".txt")
  writeBin(charToRaw("about to vanish"), temp_f)
  url <- zs_serve_file(temp_f, layer_id = "test_vanished_file")
  expect_equal(curl::curl_fetch_memory(url)$status_code, 200L)

  unlink(temp_f)
  res_gone <- curl::curl_fetch_memory(url)

  # Byte-identical to a wrong-token rejection, so the response is not an oracle
  # for whether the resource was ever registered.
  expect_uniform_404(res_gone)
  res_bad_token <- curl::curl_fetch_memory(sub(
    zs_token(url),
    strrep("f", 32L),
    url,
    fixed = TRUE
  ))
  expect_equal(res_gone$status_code, res_bad_token$status_code)
  expect_equal(rawToChar(res_gone$content), rawToChar(res_bad_token$content))

  # The case stays debuggable through the log, which must not leak the token.
  logs <- paste(zs_server_logs(50), collapse = "\n")
  expect_match(logs, "Backing file gone", fixed = TRUE)
  expect_false(grepl(zs_token(url), logs, fixed = TRUE))
})
