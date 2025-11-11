# Plan: Exclude CRDT Tables Forwarding

## Overview
Honor `excludeCrdtTables` throughout the Drift → sql_crdt → postgres_crdt stack so excluded tables never participate in CRDT initialization, preventing missing-column crashes. Status: ✅ completed.

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
1. ✅ Document current parameter flow and confirm `_excludeTables` is populated from `CrdtQueryExecutor.postgres` — done.
   - Confirmed `_excludeTables` is stored in `_PostgresCrdtDelegate` constructor but not forwarded to `PostgresCrdt.open()`.
   - All three call paths identified and documented.

2. ✅ Update `_PostgresCrdtDelegate.open` (all three call paths) to pass `_excludeTables` to `PostgresCrdt.open` and adjust constructor signatures/tests as needed — done.
   - Added `excludeTables: _excludeTables` parameter to all three `PostgresCrdt.open()` calls in `_PostgresCrdtDelegate.open()`.
   - Temporary schema creation call (line 579).
   - Main pool with schema onOpen callback (line 593).
   - Default schema path (line 609).

3. ✅ Extend `postgres_crdt` APIs (e.g., `PostgresCrdt.open` → `PostgresCrdt.getTables`) with an optional `excludeTables` parameter that injects a `NOT IN` clause using bind parameters; keep backward compatible defaults — done.
   - Added `_excludeTables: Set<String>?` field to `PostgresCrdt` class.
   - Modified `PostgresCrdt.open()` signature to accept optional `excludeTables` parameter.
   - Updated `getTables()` method to filter excluded tables using SQL `NOT IN` clause with bind parameters.
   - Both schema-qualified and default schema paths support exclusion filtering.

4. ✅ Validate that postgres-side filtering alone keeps `SqlCrdt` from seeing excluded tables; only if gaps remain, plan a minimal `sql_crdt` update to thread the parameter — done.
   - Postgres-side filtering in `getTables()` is sufficient; excluded tables never reach `_getLastModified()` queries.
   - `SqlCrdt.init()` calls `_getLastModified()` which calls `getTables()`, ensuring excluded tables are filtered before metadata queries.
   - No `sql_crdt` changes needed.

5. ✅ Add/update regression tests (in drift_crdt + postgres_crdt, and only in sql_crdt if it changes) verifying excluded tables never appear in CRDT table listings and that defaults still work — done.
   - Added postgres_crdt tests: `excludeTables filters tables from getTables()` and `excludeTables with empty set still retrieves all tables`.
   - Existing drift_crdt per_table_configuration_test.dart tests already cover SQLite behavior; PostgreSQL backend is tested via `testing.backendConfig.isPostgres`.

6. ✅ Consolidate naming convention: renamed `onlyCrdtTables`/`excludeCrdtTables` to `onlyTables`/`excludeTables` across all layers — done.
   - Updated all `CrdtQueryExecutor` constructors (main, inMemory, inDatabaseFolder, postgres) to use `onlyTables` and `excludeTables`.
   - Updated all field references in `getChangeset()` method.
   - Updated test files and test helper (`createExecutor()` function).
   - Rationale: Naming consolidation removes CRDT-specific semantics from parameter names since the actual use (filtering tables from CRDT operations) is implementation detail, not a semantic distinction at the API level.

## Test Plan
- **Functional tests:** Add integration/unit coverage confirming excluded tables are absent from `SqlCrdt.getTables` results and that CRDT init completes without touching their `modified` columns.
- **Edge cases:** Empty exclusion sets, mixed-schema tables, identifiers with quotes/case sensitivity, and repeated init cycles.
- **Validation:** Manual or automated init of Drift with `excludeCrdtTables` containing `sync_handshake_nodes` to ensure no crashes and logging shows filtered table list.

## Notes
- Coordinate changes across drift_crdt, sql_crdt, and postgres_crdt repos; consider version bumps and dependency constraints once implementation lands.
