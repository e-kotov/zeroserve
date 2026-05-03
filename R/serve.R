#' Serve an object via In-Memory Arrow IPC (mori)
#'
#' @param x A spatial object (e.g. `sf`, `duckspatial_df`).
#' @param layer_id A unique identifier for this data stream.
#' @param crs Optional Coordinate Reference System.
#'
#' @return A URL string pointing to the localhost background server.
#' @export
zs_serve_arrow <- function(x, layer_id = "stream", crs = NULL) {
  na_stream <- as_arrow_stream(x, crs = crs)
  on.exit(na_stream$release())

  # Serialize the Arrow IPC stream into a raw vector in memory
  con <- rawConnection(raw(0), "w")
  nanoarrow::write_nanoarrow(na_stream, con)
  buf <- rawConnectionValue(con)
  close(con)

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

#' Serve an existing file via HTTP with Range request support
#'
#' @param file_path Path to the file on disk.
#' @param layer_id A unique identifier for this data stream.
#'
#' @return A URL string pointing to the localhost background server.
#' @export
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

  zs_serve_file(file_path, layer_id)
}
