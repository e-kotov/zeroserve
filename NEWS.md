# zeroserve 0.1.0

* **Breaking URL change.** The data plane is now authenticated. Every served URL
  carries an unguessable capability token as its first path segment
  (`http://127.0.0.1:<port>/<token>/stream.arrow`), and requests without a valid
  token get a 404 that is indistinguishable from an unknown path. Previously any
  web page open in the user's browser could read the served data cross-origin by
  scanning ports 8000-9000 for the guessable default path. Code that hardcoded
  `http://127.0.0.1:<port>/stream.arrow` must use the URL returned by the
  `zs_serve_*()` functions instead. Both the data tokens and the existing
  control plane token now come from `/dev/urandom` (or `openssl`) rather than
  from R's seeded RNG.

* The capability token is minted **per resource** rather than once per session,
  so a URL that leaks into a saved widget, a knitted document or a pasted issue
  comment exposes at most that one resource, and nothing registered after it.
  A token is revoked by `zs_clear_registry()`, by `zs_stop_server()`, or by
  serving the same `layer_id` again: the re-serve mints a new token, so the URL
  returned earlier for that layer stops working. `.send_ipc("/list")` no longer
  echoes the tokens.

* The `OPTIONS` preflight is now gated on the capability token. It previously
  answered 204 with `Access-Control-Allow-Origin: *` for any path, which left an
  instance fingerprintable cross-origin by the very port scan the token exists
  to defeat. A preflight of a registered, correctly tokenised URL still gets
  204; anything else -- including `OPTIONS` on a control-plane path or on `/` --
  now gets the uniform 404.

* `openssl` moved from `Suggests` to `Imports`, and the weak non-CSPRNG fallback
  behind `.zs_random_token()` is gone. On a platform with neither
  `/dev/urandom` nor a usable `openssl::rand_bytes()`, zeroserve now errors
  instead of serving data behind a token worth a few tens of bits.

* Every data-plane rejection is now byte-identical: status 404, no headers, body
  `Not Found`. The former `File Not Found` response for a resource whose backing
  file has been deleted, and the 404 for an unrecognised resource type, no
  longer differ in body or carry a wildcard CORS header; a missing backing file
  is recorded in the server log (`zs_server_logs()`) instead, once per backing
  file rather than once per request. Successful data responses carry
  `Referrer-Policy: no-referrer` as defence in depth. Note what that header
  can and cannot do: it governs requests originating from a served response,
  not from the page embedding it, so whether a tokenised URL leaks in a
  `Referer` is still decided by the embedding page's own policy. Treat the URL
  as the secret it is and do not publish it.

* `zs_clear_registry()` now returns `FALSE` with a warning when the background
  server is running but could not be reached to clear it, instead of reporting
  success while every served URL stayed live. It is the documented way to
  revoke a URL, so it must not silently no-op.

* The control plane no longer answers an unauthenticated request with a
  distinct `403 Forbidden`. A fixed, guessable path that responded differently
  from every other path identified a zeroserve instance on the first probe,
  which undid for a plain `GET` what gating the `OPTIONS` preflight bought. A
  request to `/__zs__/...` with a missing or wrong `X-Zeroserve-Token` now gets
  the same uniform 404 as an unknown path, which is also what an unknown
  control endpoint already returned to an authenticated caller. Every response
  the server gives an unauthenticated client is now byte-identical, whatever
  the path or method.

* Served URLs are now correct for remote R sessions. On RStudio Server and Posit
  Workbench the URL is translated through the proxy with
  `rstudioapi::translateLocalUrl()`, and the new `zeroserve.base_url` option
  overrides the address for Connect, containers, reverse proxies and SSH port
  forwarding. Previously the returned `127.0.0.1` address pointed at the
  viewer's laptop rather than the R host. See `?"zeroserve-options"`.

* `zs_serve_arrow()` now serves `duckspatial_df` queries through DuckSpatial's
  native GeoArrow stream interface using disk-free, copy-minimized in-memory
  transport.
