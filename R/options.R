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
#'     SSH port forwarding. The served path, including the per-resource
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
#' Every served URL contains an unguessable capability token as its first path
#' segment, for example `http://127.0.0.1:8080/6b1f.../stream.arrow`. The token
#' is minted **per resource**, so a URL that leaks -- baked into a saved widget,
#' a knitted document or a pasted issue comment -- exposes at most that one
#' resource, and never anything registered afterwards.
#'
#' A URL is revoked by [zs_clear_registry()], by [zs_stop_server()], or by
#' serving the same `layer_id` again: the re-serve mints a new token, and the
#' URL returned earlier for that layer stops working.
#'
#' A request with a missing, malformed or mismatched token receives a 404 that
#' is byte-identical to the one for an unknown path and carries no CORS headers,
#' so the endpoint reveals neither which tokens nor which resources exist. The
#' `OPTIONS` preflight is gated the same way.
#'
#' Served responses carry `Referrer-Policy: no-referrer`, but only as defence
#' in depth: that header governs requests originating from a served response,
#' not from the page embedding it, so whether a tokenised URL leaks in a
#' `Referer` header remains the embedding page's decision. The token is a
#' secret in a URL. Always use the URL returned by the `zs_serve_*()` functions
#' rather than constructing one by hand, and do not publish it.
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
