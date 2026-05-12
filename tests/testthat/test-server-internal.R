test_that(".handle_data_request handles full file serving (GET & HEAD)", {
  temp_f <- tempfile(fileext = ".txt")
  writeLines("hello", temp_f)
  
  res_def <- list(type = "file", path = temp_f)
  log_file <- tempfile(fileext = ".log")
  
  # GET
  req_get <- list(REQUEST_METHOD = "GET", PATH_INFO = "/test", HTTP_RANGE = NULL)
  res_get <- zeroserve:::.handle_data_request(req_get, res_def, log_file)
  
  expect_equal(res_get$status, 200L)
  expect_equal(res_get$body$file, temp_f)
  expect_equal(res_get$headers[["Content-Length"]], as.character(file.info(temp_f)$size))
  
  # HEAD
  req_head <- list(REQUEST_METHOD = "HEAD", PATH_INFO = "/test", HTTP_RANGE = NULL)
  res_head <- zeroserve:::.handle_data_request(req_head, res_def, log_file)
  expect_equal(res_head$status, 200L)
  expect_equal(res_head$body, raw(0))
  expect_equal(res_head$headers[["Content-Length"]], res_get$headers[["Content-Length"]])
})

test_that(".handle_data_request handles 404 for missing file on disk", {
  res_def <- list(type = "file", path = "/non/existent/file")
  log_file <- tempfile(fileext = ".log")
  
  req <- list(PATH_INFO = "/test", HTTP_RANGE = NULL)
  res <- zeroserve:::.handle_data_request(req, res_def, log_file)
  
  expect_equal(res$status, 404L)
  expect_equal(res$body, "File Not Found")
  expect_equal(res$headers[["Access-Control-Allow-Origin"]], "*")
})

test_that(".handle_data_request handles robust range requests", {
  temp_f <- tempfile(fileext = ".txt")
  writeBin(charToRaw("0123456789"), temp_f) # 10 bytes
  
  res_def <- list(type = "file", path = temp_f)
  log_file <- tempfile(fileext = ".log")
  
  # Whitespace stripping
  req1 <- list(PATH_INFO = "/test", HTTP_RANGE = " bytes = 0 - 4 ")
  res1 <- zeroserve:::.handle_data_request(req1, res_def, log_file)
  expect_equal(res1$status, 206L)
  expect_equal(rawToChar(res1$body), "01234")
  
  # Suffix-byte (last 3 bytes)
  req2 <- list(PATH_INFO = "/test", HTTP_RANGE = "bytes=-3")
  res2 <- zeroserve:::.handle_data_request(req2, res_def, log_file)
  expect_equal(res2$status, 206L)
  expect_equal(rawToChar(res2$body), "789")
  expect_match(res2$headers[["Content-Range"]], "bytes 7-9/10")
  
  # Open-ended
  req3 <- list(PATH_INFO = "/test", HTTP_RANGE = "bytes=7-")
  res3 <- zeroserve:::.handle_data_request(req3, res_def, log_file)
  expect_equal(rawToChar(res3$body), "789")
})

test_that(".handle_data_request rejects multipart ranges", {
  temp_f <- tempfile(fileext = ".txt")
  writeBin(charToRaw("0123456789"), temp_f)
  res_def <- list(type = "file", path = temp_f)
  
  req <- list(PATH_INFO = "/test", HTTP_RANGE = "bytes=0-2,5-7")
  res <- zeroserve:::.handle_data_request(req, res_def, tempfile())
  
  expect_equal(res$status, 416L)
  expect_match(res$body, "Multipart")
})

test_that(".handle_data_request implements OOM chunk capping", {
  temp_f <- tempfile(fileext = ".txt")
  writeBin(charToRaw("0123456789"), temp_f)
  res_def <- list(type = "file", path = temp_f)
  
  # Request 0-9 (10 bytes) but cap at 5
  req <- list(PATH_INFO = "/test", HTTP_RANGE = "bytes=0-9")
  res <- zeroserve:::.handle_data_request(req, res_def, tempfile(), max_chunk = 5)
  
  expect_equal(res$status, 206L)
  expect_equal(length(res$body), 5)
  expect_equal(rawToChar(res$body), "01234")
  expect_match(res$headers[["Content-Range"]], "bytes 0-4/10")
})

test_that(".handle_data_request handles mori resources", {
  skip_if_not_installed("mori")
  
  buf <- charToRaw("hello mori")
  shared_buf <- mori::share(buf)
  shm_name <- mori::shared_name(shared_buf)
  
  res_def <- list(type = "mori", shm_name = shm_name)
  log_file <- tempfile(fileext = ".log")
  
  req <- list(PATH_INFO = "/mori")
  res <- zeroserve:::.handle_data_request(req, res_def, log_file)
  
  expect_equal(res$status, 200L)
  expect_equal(res$headers[["Content-Type"]], "application/vnd.apache.arrow.stream")
  expect_equal(rawToChar(res$body), "hello mori")
})
