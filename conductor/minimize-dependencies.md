# Plan: Minimize Dependencies

## Objective
Make `zeroserve` a truly minimal, high-performance IPC layer by removing unnecessary dependencies and moving heavy spatial/database packages (`sf`, `duckdb`, `duckspatial`, etc.) to `Suggests`. The core package should only rely on `nanoarrow`, `mori`, `httpuv`, `callr`, and `rlang`.

## Key Files & Context
- `DESCRIPTION`: Update `Imports` and `Suggests`.
- `R/utils-arrow.R`: Add `requireNamespace` checks before calling `sf` or `geoarrow` functions.
- `R/serve.R`: Add `requireNamespace` checks before calling `duckdb` or `DBI` functions.

## Implementation Steps
1. **Update `DESCRIPTION`**:
   - Move `sf`, `duckdb`, `duckspatial`, `geoarrow`, `dbplyr`, `DBI` to `Suggests`.
   - Completely remove `mapgl`, `geoarrowWidget`, `geoarrowDeckglLayers`, `htmlwidgets`, `htmltools` (they are not used by the core package).
2. **Refactor `R/utils-arrow.R` (`as_spatial_stream`)**:
   - Wrap the spatial/geometry handling logic in `if (requireNamespace("sf", quietly = TRUE))`.
   - Wrap the geoarrow loading in `if (requireNamespace("geoarrow", quietly = TRUE))`.
   - If the input is a plain `data.frame` and no geometry column is detected, simply return `nanoarrow::as_nanoarrow_array_stream(x)` without requiring `sf` or `geoarrow`.
3. **Refactor `R/serve.R` (`zs_serve_parquet`)**:
   - Add a check at the top: `if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("duckdb", quietly = TRUE)) stop("... requires DBI and duckdb ...")`.

## Verification & Testing
1. Run `devtools::document()`.
2. Run `devtools::check()` to ensure the package builds cleanly with the minimized dependency tree and that tests still pass (the tests already skip if `sf` or `duckdb` are missing).