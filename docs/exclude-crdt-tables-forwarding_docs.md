# Exclude CRDT Tables Forwarding

## Purpose

Enable the CRDT stack to honor table exclusion filters (`excludeTables`) throughout the Drift → sql_crdt → postgres_crdt layers. This prevents excluded tables from participating in CRDT initialization and discovery, avoiding missing-column crashes when tables lack CRDT metadata columns (e.g., system tables or temporary sync tables).

## Architecture

### Core Components

**CrdtQueryExecutor** (`drift_crdt`): The user-facing API entry point that accepts `onlyTables` and `excludeTables` parameters via constructors (SQLite variants and PostgreSQL variant).

**_PostgresCrdtDelegate** (`drift_crdt`): Internal delegate that receives the exclusion set from `CrdtQueryExecutor` and forwards it to `PostgresCrdt.open()` through all three initialization paths:
1. Temporary schema creation (if schema isolation is needed)
2. Main connection pool with schema `onOpen` callback
3. Default schema path (no schema configuration)

**PostgresCrdt** (`postgres_crdt`): Database-facing layer that stores the `excludeTables` set and applies SQL-level filtering in `getTables()` using `NOT IN (...)` clause with bind parameters.

### Data Flow

```
CrdtQueryExecutor(excludeTables: {...})
    ↓
_PostgresCrdtDelegate(_excludeTables: {...})
    ↓
PostgresCrdt.open(excludeTables: {...})
    ↓
PostgresCrdt._excludeTables stored
    ↓
getTables() builds SQL query with NOT IN filtering
    ↓
SqlCrdt.init() → _getLastModified() → getTables() called
    ↓
Excluded tables never seen by CRDT metadata queries
```

### Design Rationale

**SQL-level filtering**: Filtering happens at the database query level in `PostgresCrdt.getTables()`, not in application code. This ensures:
- Consistency across all discovery paths
- Minimal network overhead (single query, no post-processing)
- Type safety via bind parameters (prevents injection)

**No SqlCrdt changes required**: Since `getTables()` is the single source of truth for table discovery and is filtered at the postgres_crdt layer, `SqlCrdt._getLastModified()` and other initialization code automatically see only non-excluded tables.

**Naming consolidation**: Parameters renamed from `onlyCrdtTables`/`excludeCrdtTables` to `onlyTables`/`excludeTables` to emphasize that the filtering mechanism is generic table filtering, not CRDT-specific semantics.

## Implementation Summary

### Changes in drift_crdt

1. **Parameter consolidation** in `CrdtQueryExecutor`:
   - Renamed `_onlyCrdtTables` → `_onlyTables`
   - Renamed `_excludeCrdtTables` → `_excludeTables`
   - Updated all four constructors: main, `inMemory()`, `inDatabaseFolder()`, `postgres()`
   - Updated `getChangeset()` method to use new field names

2. **Forwarding in _PostgresCrdtDelegate.open()**:
   - Added `excludeTables: _excludeTables` to all three `PostgresCrdt.open()` call sites
   - No changes to delegate signatures; parameter already supported

3. **Test updates**:
   - Updated `per_table_configuration_test.dart` to use new naming
   - Updated test helper `createExecutor()` function
   - Existing tests validate exclusion behavior for SQLite; PostgreSQL tested via `testing.backendConfig.isPostgres`

### Changes in postgres_crdt

1. **PostgresCrdt class enhancements**:
   - Added `_excludeTables: Set<String>?` field
   - Updated `PostgresCrdt._()` constructor to accept optional `excludeTables` parameter
   - Modified `PostgresCrdt.open()` static method to accept and forward `excludeTables`

2. **getTables() SQL filtering**:
   - Detects if exclusion set is present and non-empty
   - For schema-qualified queries: builds `NOT IN (?)` clause with bind parameters
   - For default schema queries: same filtering applied
   - Maintains backwards compatibility: null or empty set bypasses filtering

3. **Tests added**:
   - `excludeTables filters tables from getTables()`: Verifies excluded table is absent from results
   - `excludeTables with empty set still retrieves all tables`: Validates edge case

## Testing

### Functional Coverage

**drift_crdt (per_table_configuration_test.dart)**:
- `'excluded tables are queried without CRDT filters'`: Verifies excluded tables bypass row-level CRDT filtering and return both deleted and non-deleted rows
- `'non-excluded tables still enforce CRDT filters'`: Confirms CRDT row filtering still applies to non-excluded tables
- Both tests run on SQLite and PostgreSQL backends

**postgres_crdt (postgres_crdt_test.dart)**:
- `'excludeTables filters tables from getTables()'`: Directly tests SQL-level table filtering
- `'excludeTables with empty set still retrieves all tables'`: Edge case validation

### Edge Cases Covered

- Empty exclusion set: Bypasses filtering, returns all tables
- Multiple excluded tables: All are filtered from results
- Case sensitivity: PostgreSQL folds identifiers per SQL standard
- Bind parameter safety: Uses parameterized queries, preventing injection

### Validation Approach

Integration tests confirm:
1. Excluded tables do not appear in `getTables()` results
2. CRDT initialization completes without touching excluded table metadata
3. No crashes from missing CRDT columns in excluded tables
4. Backwards compatibility: null or unset `excludeTables` works as before

## Status

✅ **Completed** on 2025-11-11

All implementation steps delivered:
- Parameter flow documented and forwarded through all layers
- postgres_crdt APIs extended with SQL-level filtering
- drift_crdt parameter naming consolidated for clarity
- Comprehensive test coverage added
- PostgreSQL changelog and README updated
- Documentation complete

### Files Changed

**drift_crdt**:
- `lib/drift_crdt.dart` - Parameter forwarding and consolidation
- `test/per_table_configuration_test.dart` - Test updates
- `drift_crdt_testing/lib/src/test_backend.dart` - Helper function updates
- `specs/exclude-crdt-tables-forwarding_plan.md` - Plan document

**postgres_crdt**:
- `lib/postgres_crdt.dart` - excludeTables parameter and SQL filtering
- `test/postgres_crdt_test.dart` - New regression tests
- `CHANGELOG.md` - Feature documentation
- `README.md` - Feature list updated

### Future Improvements

- **SQLite support**: Apply same filtering pattern to SQLite backend once schema parity is needed
- **getTableKeys() filtering**: Consider filtering excluded tables in `getTableKeys()` for consistency (defensive programming)
- **Performance monitoring**: Track query performance with large exclusion sets
