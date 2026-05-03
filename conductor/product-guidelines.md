# Product Guidelines

## 1. API Style
**Tidyverse Principles:** The package API should adhere to tidyverse conventions. This includes using `snake_case` for function and argument names, maintaining a consistent argument order (e.g., data first), and designing functions to be pipe-friendly (`%>%` or `|>`).

## 2. Documentation
**Comprehensive (roxygen2):** We will provide extensive documentation using `roxygen2`. All exported functions must include clear descriptions, parameter details, return values, and abundant, reproducible examples. Vignettes should be used to explain complex workflows.

## 3. Error Handling
**Base R Messaging:** Keep dependencies minimal by using standard Base R functions (`stop()`, `warning()`, and `message()`) for user communication. The messaging should be concise and informative without the need for comprehensive semantic formatting like `cli`.

## 4. Design Philosophy
**Magic API with Advanced Overrides:** The overarching design philosophy is to provide a highly abstracted, "magic" API that requires zero configuration for common use cases (e.g., a "zero-click" wrapper). However, it must also provide sensible mechanisms and options for advanced users to override defaults and access lower-level transport configurations when necessary.