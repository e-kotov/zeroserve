test_that("as_arrow_stream handles standard data.frame", {
  df <- data.frame(a = 1:5, b = letters[1:5])
  stream <- as_arrow_stream(df)
  expect_s3_class(stream, "nanoarrow_array_stream")
  
  res <- as.data.frame(stream)
  expect_equal(res, df)
})

test_that("as_arrow_stream handles sf objects and renames to geometry", {
  skip_if_not_installed("sf")
  
  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
  # Change geometry column name to test renaming
  names(nc)[names(nc) == "geometry"] <- "the_geom"
  sf::st_geometry(nc) <- "the_geom"
  
  stream <- as_arrow_stream(nc)
  schema <- stream$get_schema()
  
  expect_true("geometry" %in% names(schema$children))
  expect_false("the_geom" %in% names(schema$children))
  
  # Check for geoarrow extension metadata
  if (requireNamespace("geoarrow", quietly = TRUE)) {
    metadata <- schema$children$geometry$metadata
    expect_true("ARROW:extension:name" %in% names(metadata))
    expect_match(metadata[["ARROW:extension:name"]], "^geoarrow\\.")
  }
})

test_that("as_arrow_stream handles CRS reprojection", {
  skip_if_not_installed("sf")
  
  # Create object in 3857
  pt <- sf::st_sfc(sf::st_point(c(0, 0)), crs = 3857)
  df <- sf::st_sf(a = 1, geometry = pt)
  
  stream <- as_arrow_stream(df)
  schema <- stream$get_schema()
  expect_true("geometry" %in% names(schema$children))
  
  # Fetch data to verify coordinates are in 4326 (roughly 0,0 for this point)
  res <- as.data.frame(stream)
  
  # If geoarrow is loaded, this might be a geoarrow_vctr. 
  # Convert to sfc for coordinate check.
  res_sfc <- sf::st_as_sfc(res$geometry)
  coords <- sf::st_coordinates(res_sfc)
  # 0,0 in 3857 is 0,0 in 4326
  expect_equal(as.numeric(coords), c(0, 0))
  expect_true(sf::st_crs(res_sfc) == sf::st_crs(4326))
})

test_that("as_arrow_stream handles manual list/blob column detection", {
  skip_if_not_installed("sf")
  
  # Mock a duckdb-like result where geometry is a list of raws (WKB)
  wkb <- sf::st_as_binary(sf::st_sfc(sf::st_point(c(0, 0)), crs = 4326))
  df <- data.frame(a = 1, geom = I(list(wkb[[1]])))
  
  stream <- as_arrow_stream(df)
  schema <- stream$get_schema()
  
  # Should detect 'geom' as geometry and rename it
  expect_true("geometry" %in% names(schema$children))
  
  # Verify it's actually spatial now
  res <- as.data.frame(stream)
  expect_true(inherits(res$geometry, "sfc") || inherits(res$geometry, "geoarrow_vctr"))
})

test_that("as_arrow_stream handles nanoarrow_array_stream input", {
  df <- data.frame(a = 1:5)
  stream_in <- nanoarrow::as_nanoarrow_array_stream(df)
  
  stream_out <- as_arrow_stream(stream_in)
  expect_identical(stream_in, stream_out)
})
