# R Package Development Style Guide

Modern R package development using the devtools ecosystem and tidyverse conventions.

## Core Workflow

### Package Creation and Setup

```r
usethis::create_package("pkgname")  # New package
usethis::use_testthat()             # Test infrastructure
usethis::use_package("dplyr")       # Add dependency
usethis::use_pipe()                 # Export |> or %>%
usethis::use_mit_license()          # License
usethis::use_readme_rmd()           # README
usethis::use_news_md()              # Changelog
usethis::use_github_action_check_standard()  # CI
```

### Development Cycle

```r
devtools::load_all()    # Load package for testing (Ctrl+Shift+L)
devtools::document()    # Generate documentation (Ctrl+Shift+D)
devtools::test()        # Run tests (Ctrl+Shift+T)
devtools::check()       # Full R CMD check (Ctrl+Shift+E)
```

Run `check()` frequently—it catches issues early. Address all WARNINGs and NOTEs before release.

## Package Code Rules

### Never Use in Package Code
- `library()` or `require()` — use `@importFrom pkg fun` or `pkg::fun()`
- `setwd()` — paths must be relative or user-provided
- `options()` modifications without `on.exit()` restoration
- `attach()` or `<<-` global assignment

### Namespace Management

```r
# In R/pkgname-package.R
#' @importFrom dplyr filter mutate
#' @importFrom rlang .data := enquo
NULL

# Or use explicit namespacing in code
dplyr::filter(data, .data$col > 0)
```

Prefer `@importFrom` for frequently-used functions. Use `::` for occasional use or clarity.

## Documentation with roxygen2

Every exported function needs documentation:

```r
#' Compute weighted mean
#'
#' @param x Numeric vector of values.
#' @param w Numeric vector of weights, same length as `x`.
#' @param na.rm Logical; remove NA values? Default `FALSE`.
#'
#' @return Single numeric value.
#' @export
#'
#' @examples
#' weighted_mean(1:3, c(0.5, 0.3, 0.2))
weighted_mean <- function(x, w, na.rm = FALSE) {
  sum(x * w, na.rm = na.rm) / sum(w, na.rm = na.rm)
}
```

## Testing with testthat 3e

### Test File Structure

```r
# tests/testthat/test-function-name.R
test_that("function handles typical input", {
  result <- my_function(c(1, 2, 3))
  expect_equal(result, expected_value)
})
```

## Tidyverse Style Essentials

### Syntax

- Use `<-` for assignment, never `=`
- Use `|>` (native pipe), not `%>%` (magrittr)
- Use `TRUE`/`FALSE`, never `T`/`F`
- snake_case for functions and variables
- Line length: 80 characters max

## DESCRIPTION File

- **Imports**: Packages your code uses
- **Suggests**: Packages for tests/vignettes/examples
- **Depends**: Avoid unless truly required (attaches to user's search path)
