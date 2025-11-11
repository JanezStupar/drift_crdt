# Plan: Exclude CRDT Tables Forwarding

## Overview
Honor `excludeCrdtTables` throughout the Drift → sql_crdt → postgres_crdt stack so excluded tables never participate in CRDT initialization, preventing missing-column crashes. Status: pending.

## Scope / Packages
- Primary changes: `drift_crdt` (current repo) and `postgres_crdt` (Postgres-only path). Keep all logic scoped to postgres-facing layers.
- Avoid touching `sql_crdt` unless postgres-side filtering proves impossible; any `sql_crdt` work would be a fallback.

## Architecture & Design
- Core components:
  - `CrdtQueryExecutor.postgres` / `_PostgresCrdtDelegate` — ensure exclusion sets are forwarded to every `PostgresCrdt.open` call.
  - `postgres_crdt.PostgresCrdt.getTables` — accept `excludeTables` and filter at the SQL level with bind parameters (keeping the logic entirely on the postgres side).
  - `sql_crdt.SqlCrdt` changes are optional fallback only if postgres-level filtering cannot guarantee exclusions.
- Data flow:
  - Drift collects exclusions → `_PostgresCrdtDelegate` stores `_excludeTables` → passes to `PostgresCrdt.open` → `SqlCrdt.init` receives `excludeTables` → `getTables` query excludes them before `_getLastModified` runs.

## Implementation Steps
1. Document current parameter flow and confirm `_excludeTables` is populated from `CrdtQueryExecutor.postgres` — pending.
2. Update `_PostgresCrdtDelegate.open` (all three call paths) to pass `_excludeTables` to `PostgresCrdt.open` and adjust constructor signatures/tests as needed — pending.
3. Extend `postgres_crdt` APIs (e.g., `PostgresCrdt.open` → `PostgresCrdt.getTables`) with an optional `excludeTables` parameter that injects a `NOT IN` clause using bind parameters; keep backward compatible defaults — pending.
4. Validate that postgres-side filtering alone keeps `SqlCrdt` from seeing excluded tables; only if gaps remain, plan a minimal `sql_crdt` update to thread the parameter — pending.
5. Add/update regression tests (in drift_crdt + postgres_crdt, and only in sql_crdt if it changes) verifying excluded tables never appear in CRDT table listings and that defaults still work — pending.

## Test Plan
- **Functional tests:** Add integration/unit coverage confirming excluded tables are absent from `SqlCrdt.getTables` results and that CRDT init completes without touching their `modified` columns.
- **Edge cases:** Empty exclusion sets, mixed-schema tables, identifiers with quotes/case sensitivity, and repeated init cycles.
- **Validation:** Manual or automated init of Drift with `excludeCrdtTables` containing `sync_handshake_nodes` to ensure no crashes and logging shows filtered table list.

## Notes
- Coordinate changes across drift_crdt, sql_crdt, and postgres_crdt repos; consider version bumps and dependency constraints once implementation lands.
