#' Options used by zeroserve
#'
#' @description
#' `zeroserve` reads the following global options, which can be set with
#' [options()] or in an `.Rprofile`.
#'
#' @section Options:
#'
#' \describe{
#'   \item{`zeroserve.port`}{Integer port for the background server. When unset,
#'     a free port between 8000 and 9000 is chosen at server start.}
#'   \item{`zeroserve.max_chunk`}{Maximum number of bytes returned for a single
#'     HTTP Range request. Larger ranges are truncated to this size to bound
#'     server memory. Defaults to `104857600` (100 MB).}
#'   \item{`zeroserve.base_url`}{Base URL that a browser should use to reach the
#'     background server. Set it whenever the browser is not on the same machine
#'     as R: Posit Connect, containers with a published port, reverse proxies or
#'     SSH port forwarding. The served path, including the per-session
#'     capability token, is appended to this value, and a trailing `/` is
#'     ignored. When unset, zeroserve returns `http://127.0.0.1:<port>/...`,
#'     translating it through \pkg{rstudioapi} when running inside RStudio
#'     Server or Posit Workbench. Give a scheme, host and optional path prefix
#'     only: a query string or fragment is appended verbatim and will not work.
#'     Serve over `https` when the page embedding the data is itself `https`,
#'     or the browser will block the request as mixed content.}
#' }
#'
#' @section Data-plane token:
#'
#' Every served URL contains an unguessable per-session token as its first path
#' segment, for example `http://127.0.0.1:8080/6b1f.../stream.arrow`. Requests
#' without it receive a 404. Always use the URL returned by the `zs_serve_*()`
#' functions rather than constructing one by hand.
#'
#' @examples
#' # A container that publishes the server port on a known host name:
#' \dontrun{
#' options(
#'   zeroserve.port = 8080,
#'   zeroserve.base_url = "https://analysis.example.org/zeroserve"
#' )
#' }
#'
#' @name zeroserve-options
NULL
