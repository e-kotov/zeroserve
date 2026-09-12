# Agent Instructions: zeroserve

`zeroserve` is a high-performance, frontend-agnostic transport layer for the R
ecosystem. It serves Arrow IPC buffers and disk-backed files from backends such
as DuckDB, DuckSpatial, Arrow, and sf over a local HTTP server while avoiding
JSON serialization and unnecessary copies.


## Core Mission
Follow [`implementation_plan.md.resolved`](implementation_plan.md.resolved) as
the current implementation plan and [`private/roadmap.md`](private/roadmap.md)
for the longer-term rollout. Keep the package focused on robust transport
without absorbing mapping or styling logic.

## Current Phase
The minimal core transport is implemented. Current work integrates
`duckspatial_df` with DuckSpatial's native GeoArrow stream interface and adds a
real spatial integration test. Production code in `R/` and the current plan are
authoritative; `R_drafts/` contains historical prototypes only.

## Guiding Principles for Agents
1. **Minimalism:** Stick to the transport layer. Don't re-implement mapping logic that belongs in `mapgl` or `geoarrowDeckglLayers`.
2. **Performance:** Avoid unnecessary copies, but do not describe the current
   in-memory Arrow path as end-to-end zero-copy or out-of-core.
3. **TDD:** Add or update focused `testthat` tests before implementation and run
   the verification commands in the current plan.
4. **Interoperability:** Keep generated URLs compatible with browser consumers
   while preserving ZeroServe's frontend-agnostic interface.
