test_that("zs_serve_file handles generic files", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")
  
  temp_f <- tempfile(fileext = ".txt")
  writeLines("hello world", temp_f)
  
  url <- zs_serve_file(temp_f, layer_id = "test_file")
  expect_match(url, "^http://127.0.0.1:[0-9]+/test_file\\.txt$")
  
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
  
  expect_match(url, "^http://127.0.0.1:[0-9]+/arrow_non_spatial\\.parquet$")
  
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
  expect_match(url, "^http://127.0.0.1:[0-9]+/arrow_spatial\\.parquet$")
  
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
  
  expect_match(url, "^http://127.0.0.1:[0-9]+/test_df\\.arrow$")
  
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

test_that("zs_serve_arrow handles empty sf object", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")
  skip_if_not_installed("nanoarrow")
  skip_if_not_installed("sf")
  
  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
  nc_empty <- nc[0, ]
  
  url <- zs_serve_arrow(nc_empty, layer_id = "test_empty")
  expect_match(url, "^http://127.0.0.1:[0-9]+/test_empty\\.arrow$")
  
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
  
  url <- zs_serve_parquet(con, "test_table", engine = "duckdb", layer_id = "test_parquet_df")
  expect_match(url, "^http://127.0.0.1:[0-9]+/test_parquet_df\\.parquet$")
  
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
  
  expect_error(zs_serve_parquet(con, "SELECT * FROM non_existent_table", engine = "duckdb"))
})

test_that("zs_stop_server and zs_clear_registry work", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("curl")
  
  df <- data.frame(a = 1)
  url <- zs_serve_arrow(df, layer_id = "test_lifecycle")
  
  # Registry should have one item
  reg <- readRDS(.zeroserve_env$registry_file)
  expect_true("/test_lifecycle.arrow" %in% names(reg))
  
  # Clear registry
  zs_clear_registry()
  reg <- readRDS(.zeroserve_env$registry_file)
  expect_equal(length(reg), 0)
  expect_equal(length(.zeroserve_env$mori_buffers), 0)
  
  # Stop server
  expect_true(zs_stop_server())
  expect_null(.zeroserve_env$server)
  
  # Subsequent download should fail
  expect_error(curl::curl_download(url, tempfile(), quiet = TRUE))
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
  expect_match(url, "^http://127.0.0.1:[0-9]+/test_arrow\\.arrow$")
  
  temp_out <- tempfile(fileext = ".arrow")
  res <- tryCatch({
    curl::curl_download(url, temp_out, quiet = TRUE)
    TRUE
  }, error = function(e) FALSE)
  
  if (!res) {
    if (!is.null(.zeroserve_env$server) && !.zeroserve_env$server$is_alive()) {
      cat("\nServer crashed. Error:", .zeroserve_env$server$get_error_message(), "\n")
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
  
  url <- zs_serve_parquet(con, "test_range", engine = "duckdb", layer_id = "test_range")
  
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
  reg <- readRDS(.zeroserve_env$registry_file)
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
  DBI::dbExecute(con, "ALTER TABLE nc_table ALTER geometry TYPE GEOMETRY USING ST_GeomFromText(geometry);")
  
  url <- zs_serve_parquet(con, "nc_table", engine = "duckdb", layer_id = "test_parquet")
  
  expect_true(is.character(url))
  expect_match(url, "^http://127.0.0.1:[0-9]+/test_parquet\\.parquet$")
  
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
  DBI::dbExecute(con, "CREATE TABLE test_geom AS SELECT ST_GeomFromText('POINT(0 0)') AS geom")
  
  url <- zs_serve_parquet(con, "test_geom", engine = "duckdb", layer_id = "test_geom")
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
  
  DBI::dbExecute(con, "CREATE TABLE test_crs AS SELECT ST_GeomFromText('POINT(0 0)') AS geometry")
  
  # CRS as number (4326)
  url1 <- zs_serve_parquet(con, "test_crs", engine = "duckdb", layer_id = "test_crs_num", crs = 4326)
  expect_match(url1, "test_crs_num\\.parquet$")
  temp1 <- tempfile(fileext = ".parquet")
  curl::curl_download(url1, temp1, quiet = TRUE)
  res1 <- arrow::read_parquet(temp1)
  expect_true("geometry" %in% names(res1))
  
  # CRS as sf::crs object
  url2 <- zs_serve_parquet(con, "test_crs", engine = "duckdb", layer_id = "test_crs_obj", crs = sf::st_crs(4326))
  expect_match(url2, "test_crs_obj\\.parquet$")
  temp2 <- tempfile(fileext = ".parquet")
  curl::curl_download(url2, temp2, quiet = TRUE)
  res2 <- arrow::read_parquet(temp2)
  expect_true("geometry" %in% names(res2))
})

# Final cleanup for covr stability
# We stop the server and clear all buffers to ensure no ALTREP/background
# processes are alive when covr attempts to finalize the trace.
zs_stop_server()
zs_clear_registry()
