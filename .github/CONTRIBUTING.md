# Contributing to zeroserve

Thank you for your interest in contributing to `zeroserve`!

## Code of Conduct

Please note that the `zeroserve` project is released with a [Contributor Code of Conduct](https://contributor-covenant.org/version/2/1/code_of_conduct.html). By contributing to this project, you agree to abide by its terms.

## How to Contribute

1.  **Report Bugs:** If you find a bug, please open an issue on GitHub with a minimal reproducible example.
2.  **Suggest Features:** We welcome feature requests! Please open an issue to discuss your ideas.
3.  **Submit Pull Requests:**
    -   Fork the repository.
    -   Create a new branch for your changes.
    -   Ensure your code follows the package's style (snake_case, 80-character line limit).
    -   Add tests for any new functionality.
    -   Run `devtools::check()` locally before submitting.

## Development Setup

To set up a development environment, you will need R and several dependencies:

```r
install.packages(c("devtools", "testthat", "roxygen2", "knitr", "quarto"))
devtools::install_deps(dependencies = TRUE)
```

We look forward to your contributions!
