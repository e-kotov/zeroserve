# zeroserve Architecture Review

## Overview
`zeroserve` provides a high-performance transport layer for R data (Arrow, Parquet) to web frontends. It minimizes latency and memory overhead by serving data over a local HTTP server directly from R's memory or temporary disk storage.

## Network Architecture
The package uses a **Single-Server Architecture** to handle both data serving and internal control operations (IPC).

- **Host:** `127.0.0.1` (localhost only)
- **Port:** Dynamically assigned (8000–9000) or user-specified via `options(zeroserve.port)`.
- **Backgrounding:** The server runs in a dedicated background R session via `callr`, ensuring it doesn't block the main R thread's execution or UI responsiveness.

### Unified Request Handler
A single `httpuv` instance dispatches requests based on the URL path:

| Path Prefix | Purpose | Security |
|-------------|---------|----------|
| `/`          | Data Plane: Serves Arrow streams or Parquet files | Public (CORS enabled) |
| `/__zs__/`   | Control Plane: IPC for registration, health, and cleanup | Token-protected |

### Security Model
1. **Localhost Bound:** The server binds strictly to `127.0.0.1`. It is not accessible from other machines on the network.
2. **Token Authentication:** Control endpoints (under `/__zs__/`) require a transient `X-Zeroserve-Token` header. This token is generated randomly at server startup and known only to the parent R process.
3. **Reserved Namespace:** The `/__zs__/` prefix is reserved for internal use. User-registered resource paths are validated to prevent collisions.

## IPC (Inter-Process Communication)
The main R process communicates with the background server using standard HTTP requests (via `curl`).

1. **Registration:** `POST /__zs__/register` sends a JSON payload containing the path and resource metadata (file path or shared memory handle).
2. **Health Check:** `GET /__zs__/ping` verifies that the background event loop is alive and responsive.
3. **Cleanup:** `GET /__zs__/clear` flushes the registry and triggers deletion of temporary files.

## Performance Features
- **Copy-Minimized Transport:** The complete Arrow IPC stream is serialized to
  an R raw vector before `mori` shares that buffer with the background server.
  This avoids JSON and an additional R-process copy, but it is not end-to-end
  zero-copy or out-of-core transport.
- **Range Support:** Robust support for HTTP `Range` requests (RFC 7233) allows clients to fetch specific byte ranges of Parquet files (essential for DuckDB `httpfs`).
- **OOM Protection:** Automatic capping of response chunk sizes prevents memory exhaustion when serving extremely large files over poor connections.
- **CORS Support:** Full support for `OPTIONS` preflight and standard CORS headers ensures seamless integration with modern web browsers.
