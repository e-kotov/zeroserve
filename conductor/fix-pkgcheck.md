# Fix pkgcheck CI Failures

## Objective
Address the critical `pkgcheck` errors by adding a `CONTRIBUTING.md` file, a minimal HTML vignette, and documentation examples for all exported functions. This will ensure the CI pipeline passes successfully.

## Key Files & Context
- `.github/CONTRIBUTING.md` (to be created)
- `vignettes/zeroserve.Rmd` (to be created)
- `R/serve.R`
- `R/server.R`

## Implementation Steps

1. **Create CONTRIBUTING.md:**
   - Create a minimal `.github/CONTRIBUTING.md` file containing basic contribution guidelines to satisfy `pkgcheck`.
   
2. **Create a Minimal Vignette (Quarto format):**
   - Create a `vignettes/zeroserve.qmd` file (instead of `.Rmd`).
   - Include standard vignette metadata in the YAML frontmatter.
   - Update the `DESCRIPTION` file if necessary to support a Quarto builder (e.g., `VignetteBuilder: quarto` or `knitr` depending on current best practices for qmd).
   - Write a simple introductory paragraph and a basic code example (wrapped in `eval=FALSE` to avoid spinning up servers during checks).

3. **Add `@examples` to Exported Functions:**
   - In `R/serve.R` and `R/server.R`, add `@examples` tags to `zs_serve_arrow`, `zs_serve_file`, `zs_serve_parquet`, `zs_stop_server`, and `zs_clear_registry`.
   - Wrap the example code blocks in `\dontrun{}` since they involve starting a local web server, which could hang or cause issues during CRAN checks.

## Verification & Testing
- Run `devtools::document()` to regenerate the `.Rd` files with the new examples.
- Run `devtools::check()` locally to verify no new errors or warnings are introduced.