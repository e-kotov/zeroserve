test_that(".handle_request handles 404 for missing path", {
  registry_file <- tempfile(fileext = ".rds")
  saveRDS(list(), registry_file)
  log_file <- tempfile(fileext = ".log")
  
  req <- list(PATH_INFO = "/non_existent")
  res <- .handle_request(req, registry_file, log_file)
  
  expect_equal(res$status, 404L)
  expect_equal(res$body, "Not Found")
})

test_that(".handle_request handles full file serving", {
  temp_f <- tempfile(fileext = ".txt")
  writeLines("hello", temp_f)
  
  registry_file <- tempfile(fileext = ".rds")
  saveRDS(list("/test" = list(type = "file", path = temp_f)), registry_file)
  log_file <- tempfile(fileext = ".log")
  
  req <- list(PATH_INFO = "/test", HTTP_RANGE = NULL)
  res <- .handle_request(req, registry_file, log_file)
  
  expect_equal(res$status, 200L)
  expect_equal(res$body$file, temp_f)
})

test_that(".handle_request handles 404 for missing file on disk", {
  registry_file <- tempfile(fileext = ".rds")
  saveRDS(list("/test" = list(type = "file", path = "/non/existent/file")), registry_file)
  log_file <- tempfile(fileext = ".log")
  
  req <- list(PATH_INFO = "/test", HTTP_RANGE = NULL)
  res <- .handle_request(req, registry_file, log_file)
  
  expect_equal(res$status, 404L)
  expect_equal(res$body, "File Not Found")
})

test_that(".handle_request handles valid range requests", {
  temp_f <- tempfile(fileext = ".txt")
  writeLines("0123456789", temp_f)
  
  registry_file <- tempfile(fileext = ".rds")
  saveRDS(list("/test" = list(type = "file", path = temp_f)), registry_file)
  log_file <- tempfile(fileext = ".log")
  
  # Request bytes 0-4 ("01234" + newline?) 
  # Wait, writeLines adds a newline. "0123456789\n" is 11 bytes.
  
  req <- list(PATH_INFO = "/test", HTTP_RANGE = "bytes=0-4")
  res <- .handle_request(req, registry_file, log_file)
  
  expect_equal(res$status, 206L)
  expect_equal(length(res$body), 5)
  expect_equal(rawToChar(res$body), "01234")
  expect_match(res$headers[["Content-Range"]], "bytes 0-4/11")
})

test_that(".handle_request handles invalid range requests (416)", {
  temp_f <- tempfile(fileext = ".txt")
  writeLines("0123456789", temp_f)
  
  registry_file <- tempfile(fileext = ".rds")
  saveRDS(list("/test" = list(type = "file", path = temp_f)), registry_file)
  log_file <- tempfile(fileext = ".log")
  
  # Malformed range
  req1 <- list(PATH_INFO = "/test", HTTP_RANGE = "invalid")
  res1 <- .handle_request(req1, registry_file, log_file)
  expect_equal(res1$status, 416L)
  
  # Out of bounds
  req2 <- list(PATH_INFO = "/test", HTTP_RANGE = "bytes=20-30")
  res2 <- .handle_request(req2, registry_file, log_file)
  expect_equal(res2$status, 416L)
  
  # Start > End
  req3 <- list(PATH_INFO = "/test", HTTP_RANGE = "bytes=5-2")
  res3 <- .handle_request(req3, registry_file, log_file)
  expect_equal(res3$status, 416L)
})

test_that(".handle_request handles mori resources", {
  skip_if_not_installed("mori")
  
  buf <- charToRaw("hello mori")
  shared_buf <- mori::share(buf)
  shm_name <- mori::shared_name(shared_buf)
  
  registry_file <- tempfile(fileext = ".rds")
  saveRDS(list("/mori" = list(type = "mori", shm_name = shm_name)), registry_file)
  log_file <- tempfile(fileext = ".log")
  
  req <- list(PATH_INFO = "/mori")
  res <- .handle_request(req, registry_file, log_file)
  
  expect_equal(res$status, 200L)
  expect_equal(res$headers[["Content-Type"]], "application/vnd.apache.arrow.stream")
  # res$body should be the mapped buffer (raw vector)
  expect_equal(rawToChar(res$body), "hello mori")
})
