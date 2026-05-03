#' Convert input to a nanoarrow stream
#'
#' Handles duckspatial_df, sf, and standard data.frames, applying
#' GeoArrow metadata only if spatial data is detected.
#'
#' @param x A `duckspatial_df`, `sf`, `arrow::Table`, or `nanoarrow_array_stream`.
#' @param crs Optional CRS to override or assign if missing.
#'
#' @return A `nanoarrow_array_stream`.
#' @noRd
as_arrow_stream <- function(x, crs = NULL) {
  # 1. If it's a duckspatial_df, get the query and connection
  if (inherits(x, "duckspatial_df")) {
    if (!requireNamespace("duckspatial", quietly = TRUE) || !requireNamespace("dbplyr", quietly = TRUE)) {
      stop("Input 'duckspatial_df' requires the 'duckspatial' and 'dbplyr' packages.")
    }
    conn <- dbplyr::remote_con(x)
    sql <- as.character(dbplyr::sql_render(x))
    crs <- crs %||% (if (requireNamespace("sf", quietly = TRUE)) sf::st_crs(x) else NULL)
    
    # DuckDB's internal Arrow fetch (duckdb_fetch_arrow) has a bug (bad_weak_ptr)
    # when spatial extension is loaded. 
    # Fallback: Fetch as data.frame and convert.
    df <- DBI::dbGetQuery(conn, sql)
    return(as_arrow_stream(df, crs = crs))
  }

  # 2. If it's a data.frame/sf, handle geometries and reproject
  if (inherits(x, "data.frame")) {
    # Find geometry column
    geom_col <- NULL
    if (inherits(x, "sf")) {
      geom_col <- attr(x, "sf_column")
    } else {
      # Scan for blob/list columns that might be DuckDB geometries
      for (col in names(x)) {
        if (inherits(x[[col]], "list") || inherits(x[[col]], "blob")) {
          geom_col <- col
          break
        }
      }
    }
    
    # Handle spatial data only if sf is available
    if (!is.null(geom_col) && requireNamespace("sf", quietly = TRUE)) {
      # Ensure geoarrow S3 methods are registered for nanoarrow
      if (requireNamespace("geoarrow", quietly = TRUE)) {
        loadNamespace("geoarrow")
      }

      # Convert list/blob to sfc if needed
      if (!inherits(x[[geom_col]], "sfc")) {
        x[[geom_col]] <- sf::st_as_sfc(x[[geom_col]])
        x <- sf::st_as_sf(x, sf_column_name = geom_col)
      }
      
      # Reproject to 4326
      if (is.na(sf::st_crs(x))) {
        sf::st_crs(x) <- crs %||% 4326
      }
      if (sf::st_crs(x) != sf::st_crs(4326)) {
        x <- sf::st_transform(x, 4326)
      }
      
      # Rename to 'geometry' for consistency with JS renderer
      if (geom_col != "geometry") {
        names(x)[names(x) == geom_col] <- "geometry"
        attr(x, "sf_column") <- "geometry"
      }
    }
    
    # Convert to nanoarrow stream.
    return(nanoarrow::as_nanoarrow_array_stream(x))
  }

  # 3. Handle Arrow/Nanoarrow inputs directly
  if (inherits(x, "nanoarrow_array_stream")) {
    return(x)
  }
  
  # Fallback
  return(nanoarrow::as_nanoarrow_array_stream(x))
}
