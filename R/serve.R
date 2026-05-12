#' Serve an object via In-Memory Arrow IPC (mori)
#'
#' @param x A spatial object (e.g. `sf`, `duckspatial_df`), data frame,
#'   `nanoarrow_array_stream`, DuckDB connection, or DuckDB-backed lazy table.
#' @param query A SQL query string or simple table name. Required when `x` is a
#'   DuckDB connection.
#' @param layer_id A unique identifier for this data stream.
#' @param crs Optional Coordinate Reference System.
#'
#' @return A URL string pointing to the localhost background server.
#' @export
#'
#' @examples
#' \dontrun{
#' library(sf)
#' nc <- st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
#' url <- zs_serve_arrow(nc)
#' print(url)
#' zs_stop_server()
#' }
zs_serve_arrow <- function(x, query = NULL, layer_id = "stream", crs = NULL) {
  buf <- if (.zs_is_duckdb_arrow_input(x)) {
    .zs_duckdb_arrow_ipc_buffer(x, query = query)
  } else {
    na_stream <- as_arrow_stream(x, crs = crs)
    on.exit(na_stream$release(), add = TRUE)
    .zs_arrow_stream_to_raw(na_stream)
  }

  .zs_serve_arrow_buffer(buf, layer_id = layer_id)
}

.zs_serve_arrow_buffer <- function(buf, layer_id = "stream") {
  # Share the raw vector via mori
  shared_buf <- mori::share(buf)
  shm_name <- mori::shared_name(shared_buf)

  # Keep a reference to the shared buffer in the main process
  # so it doesn't get garbage collected.
  .zeroserve_env$mori_buffers[[layer_id]] <- shared_buf

  path <- sprintf("/%s.arrow", layer_id)

  url <- register_resource(path, list(
    type = "mori",
    shm_name = shm_name
  ))

  url
}

.zs_arrow_stream_to_raw <- function(stream) {
  # Serialize the Arrow IPC stream into a raw vector in memory.
  con <- rawConnection(raw(0), "w")
  on.exit(close(con), add = TRUE)
  nanoarrow::write_nanoarrow(stream, con)
  rawConnectionValue(con)
}

.zs_is_duckdb_arrow_input <- function(x) {
  if (inherits(x, "duckdb_connection") || inherits(x, "duckspatial_df")) {
    return(TRUE)
  }

  if (!inherits(x, c("tbl_sql", "tbl_lazy"))) {
    return(FALSE)
  }

  if (!requireNamespace("dbplyr", quietly = TRUE)) {
    return(TRUE)
  }

  conn <- tryCatch(dbplyr::remote_con(x), error = function(e) NULL)
  inherits(conn, "duckdb_connection")
}

.zs_duckdb_arrow_ipc_buffer <- function(x, query = NULL) {
  .zs_require_namespace("DBI", "DuckDB Arrow serving")
  .zs_require_namespace("duckdb", "DuckDB Arrow serving")
  .zs_require_namespace("arrow", "DuckDB Arrow serving")

  source <- .zs_duckdb_arrow_source(x, query = query)
  res <- NULL
  stream <- NULL

  tryCatch({
    res <- DBI::dbSendQuery(source$conn, source$sql, arrow = TRUE)
    on.exit(try(DBI::dbClearResult(res), silent = TRUE), add = TRUE)

    reader <- duckdb::duckdb_fetch_record_batch(res)
    stream <- nanoarrow::as_nanoarrow_array_stream(reader)
    on.exit({
      if (!is.null(stream$release)) {
        stream$release()
      }
    }, add = TRUE)

    .zs_arrow_stream_to_raw(stream)
  }, error = function(e) {
    stop(
      "DuckDB Arrow path failed: ", conditionMessage(e),
      ". For large or out-of-core data, use zs_serve_parquet().",
      call. = FALSE
    )
  })
}

.zs_duckdb_arrow_source <- function(x, query = NULL) {
  if (inherits(x, "duckdb_connection")) {
    if (is.null(query)) {
      stop("`query` is required when `x` is a DuckDB connection.", call. = FALSE)
    }

    return(list(
      conn = x,
      sql = .zs_duckdb_query_sql(x, query)
    ))
  }

  .zs_require_namespace("dbplyr", "DuckDB-backed lazy table Arrow serving")

  conn <- dbplyr::remote_con(x)
  if (!inherits(conn, "duckdb_connection")) {
    stop("DuckDB Arrow serving requires a DuckDB-backed input.", call. = FALSE)
  }

  list(
    conn = conn,
    sql = as.character(dbplyr::sql_render(x))
  )
}

.zs_duckdb_query_sql <- function(conn, query) {
  if (!is.character(query) || length(query) != 1 || is.na(query) || query == "") {
    stop("`query` must be a single non-empty SQL string or table name.", call. = FALSE)
  }

  if (.zs_is_simple_table_name(query)) {
    return(sprintf("SELECT * FROM %s", as.character(DBI::dbQuoteIdentifier(conn, query))))
  }

  query
}

.zs_is_simple_table_name <- function(query) {
  grepl("^[A-Za-z_][A-Za-z0-9_]*$", query)
}

.zs_require_namespace <- function(package, context) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop(sprintf("%s requires the '%s' package.", context, package), call. = FALSE)
  }
}

#' Serve an existing file via HTTP with Range request support
#'
#' @param file_path Path to the file on disk.
#' @param layer_id A unique identifier for this data stream.
#'
#' @return A URL string pointing to the localhost background server.
#' @export
#'
#' @examples
#' \dontrun{
#' temp_f <- tempfile(fileext = ".txt")
#' writeLines("hello world", temp_f)
#' url <- zs_serve_file(temp_f)
#' print(url)
#' zs_stop_server()
#' }
zs_serve_file <- function(file_path, layer_id = "stream") {
  if (!file.exists(file_path)) {
    stop(sprintf("File does not exist: %s", file_path))
  }
  
  # Ensure we use an absolute path
  file_path <- normalizePath(file_path)
  
  # Use file extension as part of the path if possible
  ext <- tools::file_ext(file_path)
  path <- if (ext == "") {
    sprintf("/%s", layer_id)
  } else {
    sprintf("/%s.%s", layer_id, ext)
  }
  
  url <- register_resource(path, list(
    type = "file",
    path = file_path
  ))
  
  url
}

#' Serve data via Out-Of-Core Parquet export
#'
#' @param data A DuckDB connection OR a spatial object (sf, data.frame, etc.).
#' @param query A SQL query string or table name (required if 'data' is a connection).
#' @param engine The engine to use for writing Parquet: "duckdb" or "arrow".
#' @param layer_id A unique identifier for this data stream.
#' @param crs Optional Coordinate Reference System.
#'
#' @return A URL string pointing to the localhost background server.
#' @export
#'
#' @examples
#' \dontrun{
#' library(sf)
#' nc <- st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
#' url <- zs_serve_parquet(nc)
#' print(url)
#' zs_stop_server()
#' }
zs_serve_parquet <- function(
    data, 
    query = NULL, 
    engine = c("duckdb", "arrow"), 
    layer_id = "stream", 
    crs = NULL
) {
  engine <- match.arg(engine)
  
  temp_dir <- tempfile(pattern = paste0("zeroserve_", layer_id))
  dir.create(temp_dir, showWarnings = FALSE, recursive = TRUE)
  file_path <- file.path(temp_dir, sprintf("%s.parquet", layer_id))

  if (engine == "duckdb") {
    if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("duckdb", quietly = TRUE)) {
      stop("Engine 'duckdb' requires the 'DBI' and 'duckdb' packages.")
    }
    
    conn <- data
    sql <- if (grepl(" ", query)) {
      query
    } else {
      sprintf("SELECT * FROM %s", query)
    }

    col_info <- DBI::dbGetQuery(conn, sprintf("SELECT * FROM (%s) LIMIT 0", sql))
    
    geom_col <- NULL
    if ("geometry" %in% names(col_info)) {
      geom_col <- "geometry"
    } else if ("geom" %in% names(col_info)) {
      geom_col <- "geom"
    } else {
      for (col in names(col_info)) {
        if (inherits(col_info[[col]], "list") || inherits(col_info[[col]], "blob")) {
          geom_col <- col
          break
        }
      }
    }

    if (!is.null(geom_col) && requireNamespace("sf", quietly = TRUE)) {
      srid <- if (!is.null(crs)) {
        if (inherits(crs, "crs")) {
          if (!is.na(crs$epsg)) crs$epsg else 4326
        } else {
          crs
        }
      } else {
        NULL
      }

      if (!is.null(srid)) {
        srid_str <- if (is.numeric(srid)) sprintf("'EPSG:%s'", srid) else sprintf("'%s'", srid)
        sql <- sprintf("SELECT * EXCLUDE (%s), ST_Transform(ST_SetCRS(%s, %s), 'EPSG:4326') AS geometry FROM (%s)", 
                      geom_col, geom_col, srid_str, sql)
      } else {
        sql <- sprintf("SELECT * EXCLUDE (%s), ST_SetCRS(%s, 'EPSG:4326') AS geometry FROM (%s)", 
                      geom_col, geom_col, sql)
      }
    }

    copy_sql <- sprintf("COPY (%s) TO '%s' (FORMAT PARQUET)", sql, file_path)
    DBI::dbExecute(conn, copy_sql)
    
  } else {
    # Arrow Engine
    if (!requireNamespace("arrow", quietly = TRUE)) {
      stop("Engine 'arrow' requires the 'arrow' package.")
    }
    
    # Use our robust spatial stream converter to ensure GeoArrow metadata
    # and CRS handling are consistent across the package.
    na_stream <- as_arrow_stream(data, crs = crs)
    on.exit(na_stream$release())
    
    # arrow::write_parquet can write directly from a nanoarrow stream
    arrow::write_parquet(na_stream, file_path)
  }

  # Track temp file for cleanup
  .zeroserve_env$temp_files <- c(.zeroserve_env$temp_files, file_path)
  
  zs_serve_file(file_path, layer_id)
}
