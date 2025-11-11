# Spec: Exclude CRDT Tables Forwarding

## Purpose
Ensure Drift's CRDT integration correctly honors `excludeCrdtTables` so that CRDT setup and sync skip explicitly excluded tables, preventing crashes when excluded tables lack the CRDT `modified` column.

## Requirements
- Functional:
  - `CrdtQueryExecutor.postgres` and `_PostgresCrdtDelegate` must forward `excludeCrdtTables` to every `PostgresCrdt.open` call so exclusions reach the `postgres_crdt` layer during initialization, migrations, and migrations-with-schema steps (three callsites today).
  - `PostgresCrdt.getTables()` (and `SqlCrdt.init()` callers) must accept an `excludeTables` parameter and filter results at the SQL level (`NOT IN (...)`) before CRDT metadata queries run.
  - `sql_crdt` needs to pass the exclusion set whenever it enumerates tables (initial load, migrations, schema refresh) to avoid touching excluded tables in `_getLastModified`.
  - Existing Drift API surface must remain unchanged except for honoring the already-documented `excludeCrdtTables` option.
- Non-functional:
  - No added network round-trips; filtering should happen inside the existing discovery query.
  - Maintain backwards compatibility for consumers not providing exclusions (default behavior unchanged and tested).

## Context
- Current bug: `_PostgresCrdtDelegate.open()` drops `_excludeTables` when calling `PostgresCrdt.open(...)`, so excluded tables still appear in CRDT discovery and cause missing `modified` column errors (e.g., `sync_handshake_*` tables).
- Ideal flow: Drift → `PostgresCrdt` → `SqlCrdt` already has plumbing for exclusion sets, but the parameter is never forwarded, and `getTables()` does not filter on the database side.
- Extending `postgres_crdt` / `sql_crdt` keeps the responsibility close to table discovery and scales to SQLite once parity is needed.

## Constraints
- Keep Dart API signatures source-compatible; only add optional parameters where they do not break implementers.
- `sql_crdt` and `postgres_crdt` changes must maintain schema-qualified queries (schema defaults remain supported).
- Filtering logic must be SQL-injection safe (use bind parameters) and case-insensitive to match PostgreSQL identifier folding rules.

## Acceptance Criteria
- Passing `excludeCrdtTables` when constructing `Database.postgres(... useCrdt: true ...)` results in `PostgresCrdt.open()` receiving the same set in every initialization code path.
- Instrumented run (unit test or integration log) shows `SqlCrdt.getTables()` excluding `sync_handshake_nodes` and `sync_handshake_request_log`, and CRDT initialization completes without querying their `modified` columns.
- Regression tests (or new targeted tests) cover both inclusion and exclusion paths, ensuring excluded tables never appear in CRDT table lists while default behavior remains untouched.
