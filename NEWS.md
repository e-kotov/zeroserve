# zeroserve 0.1.0

* **Breaking URL change.** The data plane is now authenticated. Every served URL
  carries an unguessable per-session capability token as its first path segment
  (`http://127.0.0.1:<port>/<token>/stream.arrow`), and requests without a valid
  token get a 404 that is indistinguishable from an unknown path. Previously any
  web page open in the user's browser could read the served data cross-origin by
  scanning ports 8000-9000 for the guessable default path. Code that hardcoded
  `http://127.0.0.1:<port>/stream.arrow` must use the URL returned by the
  `zs_serve_*()` functions instead. Both the data token and the existing control
  plane token now come from `/dev/urandom` (or `openssl`) rather than from R's
  seeded RNG.

* Served URLs are now correct for remote R sessions. On RStudio Server and Posit
  Workbench the URL is translated through the proxy with
  `rstudioapi::translateLocalUrl()`, and the new `zeroserve.base_url` option
  overrides the address for Connect, containers, reverse proxies and SSH port
  forwarding. Previously the returned `127.0.0.1` address pointed at the
  viewer's laptop rather than the R host. See `?"zeroserve-options"`.

* `zs_serve_arrow()` now serves `duckspatial_df` queries through DuckSpatial's
  native GeoArrow stream interface using disk-free, copy-minimized in-memory
  transport.
