# PostgreSQL CRDT Delegate Implementation Plan

## Overview

This document outlines the implementation plan for building a `_PostgresCrdtDelegate` class that will provide PostgreSQL CRDT capability to Drift, mirroring the existing SQLite implementation pattern used in `_CrdtDelegate`.

## Current Architecture (SQLite)

The current implementation uses the following class hierarchy:

```
CrdtQueryExecutor (DelegatedDatabase)
  └─> _CrdtDelegate (DatabaseDelegate)
       └─> SqliteCrdt (from sqlite_crdt package)
            └─> _CrdtTransactionDelegate (SupportedTransactionDelegate)
                 └─> _CrdtQueryDelegate (QueryDelegate)
                      └─> SqliteTransactionCrdt (_TransactionCrdt)
```

### Key Components

1. **_CrdtDelegate**: The main database delegate that manages the SQLite CRDT connection
2. **SqliteTransactionCrdt**: Wrapper around CrdtExecutor transactions
3. **_CrdtQueryDelegate**: Handles query delegation with CRDT transformations
4. **_CrdtTransactionDelegate**: Manages transaction lifecycle
5. **_CrdtVersionDelegate**: Handles schema versioning using SQLite PRAGMAs

## Target Architecture (PostgreSQL)

We need to implement parallel classes for PostgreSQL:

```
CrdtQueryExecutor (DelegatedDatabase)
  └─> _PostgresCrdtDelegate (DatabaseDelegate)
       └─> PostgresCrdt (from postgres_crdt package)
            └─> _PostgresCrdtTransactionDelegate (SupportedTransactionDelegate)
                 └─> _CrdtQueryDelegate (QueryDelegate) [REUSABLE]
                      └─> PostgresTransactionCrdt (_TransactionCrdt)
```

## Implementation Plan

### Phase 1: Core Infrastructure

#### 1.1 Import and Type Definitions

**Location**: `lib/drift_crdt.dart` (top of file)

Add imports:
```dart
import 'package:postgres_crdt/postgres_crdt.dart' as postgres_crdt;
import 'package:drift_postgres/drift_postgres.dart';
```

Add type aliases (after existing ones):
```dart
typedef PostgresCrdt = postgres_crdt.PostgresCrdt;
```

#### 1.2 PostgresTransactionCrdt Class

**Purpose**: Implement the `_TransactionCrdt` interface for PostgreSQL transactions

**Location**: `lib/drift_crdt.dart` (after `SqliteTransactionCrdt`)

```dart
class PostgresTransactionCrdt implements _TransactionCrdt {
  final CrdtExecutor txn;

  PostgresTransactionCrdt(this.txn);

  @override
  Future<ExecuteResult> execute(String sql, [List<Object?>? args]) {
    if (sql.contains('CREATE TABLE')) {
      sql = DriftCrdtUtils.prepareCreateTableQuery(sql);
    }
    return txn.execute(sql, args);
  }

  @override
  Future<List<Map<String, Object?>>> query(String sql,
      [List<Object?>? arguments]) {
    return txn.query(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) {
    return txn.query(sql, arguments);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    await txn.execute(sql, arguments);
    // PostgreSQL doesn't have changes() function
    // The postgres_crdt library handles this internally
    return 1; // Return success indicator
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    final result = await txn.execute(sql, arguments);
    // For RETURNING clause support
    if (result is SqlCrdtQueryResult && result.rows.isNotEmpty) {
      final row = result.rows.first;
      if (row.containsKey('id')) {
        return row['id'] as int;
      }
    }
    return 1; // Default success indicator
  }
}
```

**Key Differences from SQLite**:
- No `last_insert_rowid()` - PostgreSQL uses `RETURNING` clauses
- No `changes()` function - handled by postgres_crdt internally
- Need to handle query results differently for insert/update operations

### Phase 2: Delegate Classes

#### 2.1 _PostgresCrdtTransactionDelegate Class

**Purpose**: Manage transaction lifecycle for PostgreSQL

**Location**: `lib/drift_crdt.dart` (after `_CrdtTransactionDelegate`)

```dart
class _PostgresCrdtTransactionDelegate extends SupportedTransactionDelegate {
  final _PostgresCrdtDelegate api;
  bool queryDeleted = false;

  _PostgresCrdtTransactionDelegate(this.api);

  @override
  FutureOr<void> startTransaction(Future Function(QueryDelegate) run) {
    return api.postgresCrdt.transaction((txn) async {
      return run(_CrdtQueryDelegate(PostgresTransactionCrdt(txn), queryDeleted));
    });
  }

  Future<void> runBatched(BatchedStatements statements) async {
    final batch = api.postgresCrdt.batch();

    for (final arg in statements.arguments) {
      var statement = statements.statements[arg.statementIndex];
      if (statement.contains('CREATE TABLE')) {
        statement = DriftCrdtUtils.prepareCreateTableQuery(statement);
      }
      batch.execute(statement, arg.arguments);
    }

    await batch.commit();
  }
}
```

#### 2.2 _PostgresCrdtVersionDelegate Class

**Purpose**: Handle schema versioning for PostgreSQL

**Location**: `lib/drift_crdt.dart` (after `_CrdtVersionDelegate`)

```dart
class _PostgresCrdtVersionDelegate extends DynamicVersionDelegate {
  final PostgresCrdt _db;

  _PostgresCrdtVersionDelegate(this._db);

  @override
  Future<int> get schemaVersion async {
    // PostgreSQL uses a custom table for versioning
    // This matches drift_postgres conventions
    try {
      final result = await _db.query('''
        SELECT version FROM "__schema"
        ORDER BY version DESC
        LIMIT 1
      ''');
      if (result.isEmpty) return 0;
      return result.first['version'] as int;
    } catch (e) {
      // Table doesn't exist yet
      return 0;
    }
  }

  @override
  Future<void> setSchemaVersion(int version) async {
    // Create schema table if it doesn't exist
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS "__schema" (
        version INTEGER NOT NULL PRIMARY KEY,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');

    // Insert or update the version
    await _db.execute('''
      INSERT INTO "__schema" (version, created_at)
      VALUES (?1, NOW())
      ON CONFLICT (version) DO UPDATE
      SET created_at = NOW()
    ''', [version]);
  }
}
```

**Key Differences from SQLite**:
- PostgreSQL doesn't have `PRAGMA user_version`
- Use custom `__schema` table (drift_postgres convention)
- Need to handle table creation and conflict resolution
- Use PostgreSQL-specific syntax (TIMESTAMPTZ, ON CONFLICT, NOW())

#### 2.3 _PostgresCrdtDelegate Class

**Purpose**: Main delegate for PostgreSQL CRDT database

**Location**: `lib/drift_crdt.dart` (after `_CrdtDelegate`)

```dart
class _PostgresCrdtDelegate extends DatabaseDelegate {
  late PostgresCrdt postgresCrdt;
  bool _isOpen = false;
  bool _queryDeleted = false;

  final Endpoint endpoint;
  final ConnectionSettings? settings;
  final bool enableMigrations;

  late _PostgresCrdtTransactionDelegate? _transactionDelegate;

  _PostgresCrdtDelegate({
    required this.endpoint,
    this.settings,
    this.enableMigrations = true,
  });

  @override
  late final DbVersionDelegate versionDelegate =
      _PostgresCrdtVersionDelegate(postgresCrdt);

  @override
  TransactionDelegate get transactionDelegate {
    final delegate = _transactionDelegate ??= _PostgresCrdtTransactionDelegate(this);
    delegate.queryDeleted = _queryDeleted;
    return delegate;
  }

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> open(QueryExecutorUser user) async {
    postgresCrdt = await PostgresCrdt.open(
      endpoint.database,
      host: endpoint.host,
      port: endpoint.port,
      username: endpoint.username,
      password: endpoint.password,
      sslMode: settings?.sslMode,
    );
    _transactionDelegate = _PostgresCrdtTransactionDelegate(this);
    _isOpen = true;
  }

  @override
  Future<void> close() {
    return postgresCrdt.close();
  }

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    final batch = postgresCrdt.batch();

    for (final arg in statements.arguments) {
      var statement = statements.statements[arg.statementIndex];
      if (statement.contains('CREATE TABLE')) {
        statement = DriftCrdtUtils.prepareCreateTableQuery(statement);
      }
      batch.execute(statement, arg.arguments);
    }

    await batch.commit();
  }

  @override
  Future<void> runCustom(String statement, List<Object?> args) async {
    switch (statement) {
      case _crdtDeletedOn:
        _queryDeleted = true;
        break;
      case _crdtDeletedOff:
        _queryDeleted = false;
        break;
      default:
        if (statement.contains('CREATE TABLE')) {
          statement = DriftCrdtUtils.prepareCreateTableQuery(statement);
        }
        await postgresCrdt.execute(statement, args);
    }
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    // PostgreSQL requires RETURNING clause for getting inserted ID
    if (!statement.toUpperCase().contains('RETURNING')) {
      // Add RETURNING id if not present
      statement = statement.trimRight();
      if (statement.endsWith(';')) {
        statement = statement.substring(0, statement.length - 1);
      }
      statement += ' RETURNING id';
    }

    final result = await postgresCrdt.execute(statement, args);
    if (result is SqlCrdtQueryResult && result.rows.isNotEmpty) {
      final row = result.rows.first;
      if (row.containsKey('id')) {
        return row['id'] as int;
      }
    }
    return 1; // Default success indicator
  }

  @override
  Future<QueryResult> runSelect(String sql, List<Object?> args) async {
    sqlparser.SqlEngine parser = sqlparser.SqlEngine();
    final parsed = parser.parse(sql);
    sqlparser.Statement statement = parsed.rootNode as sqlparser.Statement;

    if (_hasReturningClause(statement)) {
      final result = await postgresCrdt.execute(sql, args);
      return _queryResultFromExecute(result);
    }

    if (!DriftCrdtUtils.isSpecialQuery(parsed) &&
        statement is sqlparser.SelectStatement) {
      DriftCrdtUtils.prepareSelectStatement(statement, _queryDeleted);
      sql = (statement).toSql();
    }

    final result = await postgresCrdt.query(sql, args);
    return QueryResult.fromRows(result);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    await postgresCrdt.execute(statement, args);
    // PostgreSQL doesn't have changes() function
    // Return success indicator (postgres_crdt handles actual counts internally)
    return 1;
  }
}
```

**Key Features**:
- Uses `Endpoint` for connection configuration (postgres standard)
- Uses `ConnectionSettings` for SSL and other options
- Handles RETURNING clauses automatically for inserts
- No file path management (server-based)
- Schema versioning uses custom table instead of PRAGMA

### Phase 3: CrdtQueryExecutor Integration

#### 3.1 Add PostgreSQL Constructors

**Location**: `lib/drift_crdt.dart` in `CrdtQueryExecutor` class

Add after existing constructors:

```dart
/// A query executor that uses PostgreSQL with CRDT functionality.
///
/// Connect to a PostgreSQL database with CRDT support using the provided
/// [endpoint]. The [settings] parameter can be used to configure SSL and
/// other connection options.
///
/// Set [enableMigrations] to false if you're managing schema migrations
/// externally. When true (default), drift will manage migrations through
/// the __schema table.
///
/// If [logStatements] is true, statements sent to the database will
/// be printed, which can be handy for debugging.
CrdtQueryExecutor.postgres({
  required Endpoint endpoint,
  ConnectionSettings? settings,
  bool enableMigrations = true,
  bool? logStatements,
})  : _dialect = SqlDialect.postgres,
      super(
        _PostgresCrdtDelegate(
          endpoint: endpoint,
          settings: settings,
          enableMigrations: enableMigrations,
        ),
        logStatements: logStatements,
        isSequential: false, // PostgreSQL supports concurrent operations
      );

/// A query executor that uses an already-opened PostgreSQL connection.
///
/// This constructor is useful when you're managing PostgreSQL connections
/// yourself (for instance through a connection pool).
///
/// The [session] parameter should be an active PostgreSQL connection.
/// Set [enableMigrations] to false if you're managing schema migrations
/// externally.
CrdtQueryExecutor.postgresOpened(
  Connection session, {
  bool enableMigrations = true,
  bool? logStatements,
})  : _dialect = SqlDialect.postgres,
      super(
        _PostgresCrdtDelegateOpened(
          session: session,
          enableMigrations: enableMigrations,
        ),
        logStatements: logStatements,
        isSequential: false,
      );
```

#### 3.2 Add _PostgresCrdtDelegateOpened Class

**Purpose**: Support pre-opened connections (pool management)

**Location**: `lib/drift_crdt.dart` (after `_PostgresCrdtDelegate`)

```dart
class _PostgresCrdtDelegateOpened extends _PostgresCrdtDelegate {
  final Connection session;

  _PostgresCrdtDelegateOpened({
    required this.session,
    required bool enableMigrations,
  }) : super(
          endpoint: Endpoint(
            host: 'opened',
            database: 'opened',
          ), // Dummy endpoint
          enableMigrations: enableMigrations,
        );

  @override
  Future<void> open(QueryExecutorUser user) async {
    // Use the session directly with postgres_crdt
    // Note: This requires postgres_crdt to support session-based initialization
    postgresCrdt = PostgresCrdt.fromSession(session);
    _transactionDelegate = _PostgresCrdtTransactionDelegate(this);
    _isOpen = true;
  }

  @override
  Future<void> close() async {
    // Don't close the session since it's managed externally
    // Only close the CRDT wrapper
    await postgresCrdt.dispose();
  }
}
```

**Note**: This implementation assumes `postgres_crdt` library supports a `fromSession()` or similar method. If not available, this will need to be adapted or the feature deferred.

### Phase 4: Query Transformation Considerations

#### 4.1 SQL Dialect Differences

The existing `DriftCrdtUtils` class primarily targets SQLite syntax. PostgreSQL has some differences:

**Areas Requiring Attention**:

1. **Parameter Placeholders**:
   - SQLite: `?`, `?1`, `?2`
   - PostgreSQL: `$1`, `$2`, `$3`
   - **Decision**: Let drift handle this at a higher level (it already does)

2. **Quote Characters**:
   - SQLite: Double quotes `"` for identifiers
   - PostgreSQL: Double quotes `"` for identifiers (compatible)
   - **Decision**: No changes needed

3. **Data Types**:
   - SQLite: Flexible type system
   - PostgreSQL: Strict type system
   - **Decision**: No changes to utils needed; handled by postgres_crdt

4. **Special Queries**:
   - Need to update `DriftCrdtUtils.isSpecialQuery()` to handle PostgreSQL system tables

**Recommended Changes to `lib/utils.dart`**:

Add PostgreSQL system tables to special query detection:

```dart
static bool isSpecialQuery(ParseResult result) {
  // Pragma queries don't need to be intercepted and transformed
  if (result.sql.toUpperCase().startsWith('PRAGMA')) {
    return true;
  }

  //  IF the query is on the lookup table, we don't need to add CRDT columns
  if (_specialQueries.contains(result.sql.toUpperCase())) {
    return true;
  }

  final statement = result.rootNode;
  if (statement is SelectStatement) {
    if (statement.from != null) {
      if (statement.from is TableReference) {
        final table = statement.from as TableReference;

        // SQLite system tables
        if ([
          'sqlite_schema',
          'sqlite_master',
          'sqlite_temp_schema',
          'sqlite_temp_master',
          // PostgreSQL system tables
          'pg_catalog',
          'information_schema',
          'pg_class',
          'pg_index',
          'pg_attribute',
          'pg_tables',
          '__schema', // drift's migration table
        ].contains(table.tableName)) {
          return true;
        }

        // Check for schema-qualified system tables (e.g., pg_catalog.pg_tables)
        if (table.schemaName != null &&
            ['pg_catalog', 'information_schema'].contains(table.schemaName)) {
          return true;
        }
      }
    }
  }
  return false;
}
```

#### 4.2 CRDT Column Handling

The CRDT columns (`is_deleted`, `hlc`, `node_id`, `modified`) are automatically added by both `sqlite_crdt` and `postgres_crdt` libraries. The existing `DriftCrdtUtils.prepareCreateTableQuery()` strips these columns before passing to the CRDT library.

**Verification Needed**: Ensure `postgres_crdt` adds the same columns with the same names and types as `sqlite_crdt`.

**VERIFIED**: postgres_crdt works just like sqlite_crdt in this regard.

### Phase 5: Testing Strategy

NOTE: Run postgres tests using `./scripts/test_postgres.sh` it sets up credentials through environment variables.

#### 5.1 Test Infrastructure Updates

**File**: `test/utils/test_backend.dart`

The infrastructure is already in place! The existing code shows:
- `BackendConfig` enum with `TestBackend.postgres`
- `createExecutor()` function that calls `CrdtQueryExecutor.postgres()`
- `clearBackend()` function with PostgreSQL table truncation logic

**Verification**: The test infrastructure expects these constructors to exist, so our implementation will complete the loop.

#### 5.2 Test Coverage

All existing tests should work with PostgreSQL once the delegate is implemented:

- `test/crdt_delegate_test.dart` - Basic CRDT operations
- `test/crdt_functions_test.dart` - CRDT-specific functions
- `test/crdt_migration_test.dart` - Migration handling
- `test/crdt_in_memory_test.dart` - Not applicable for PostgreSQL
- `test/watch_deleted_test.dart` - Query filtering

**Run Tests**:
```bash
export DRIFT_CRDT_TEST_BACKEND=postgres
export DRIFT_CRDT_PG_USER=postgres
export DRIFT_CRDT_PG_PASSWORD=postgres
flutter test
```

Or use the convenience script:
```bash
./scripts/test_postgres.sh
```

#### 5.3 Integration Tests

The existing integration test suite should also work:
```bash
export DRIFT_CRDT_TEST_BACKEND=postgres
export DRIFT_CRDT_PG_USER=postgres
flutter test integration_test/
```

### Phase 6: Documentation Updates

#### 6.1 README.md Updates

The README already documents PostgreSQL usage at lines 34-55! This is great.

**Verify/Update**:
- Constructor signatures match implementation
- Environment variables for testing are correct
- Migration notes for PostgreSQL are accurate

#### 6.2 CLAUDE.md Updates

Add notes about PostgreSQL-specific considerations:

```markdown
### PostgreSQL Support

The package supports both SQLite (via sqflite) and PostgreSQL (via postgres_crdt).

**Key Differences**:
- PostgreSQL uses server-based connections instead of file paths
- Schema versioning uses `__schema` table instead of `PRAGMA user_version`
- PostgreSQL requires `RETURNING` clauses for insert operations to get generated IDs
- Connection pooling is handled by the `postgres` package
- SSL/TLS configuration is available via `ConnectionSettings`

**PostgreSQL-Specific Classes**:
- `_PostgresCrdtDelegate` - Main database delegate
- `PostgresTransactionCrdt` - Transaction wrapper
- `_PostgresCrdtTransactionDelegate` - Transaction lifecycle management
- `_PostgresCrdtVersionDelegate` - Schema versioning for PostgreSQL

**Testing with PostgreSQL**:
Set `DRIFT_CRDT_TEST_BACKEND=postgres` environment variable to run tests against PostgreSQL.
```

### Phase 7: Edge Cases and Considerations

#### 7.1 Connection Management

**PostgreSQL Considerations**:
- Connection pooling (multiple connections vs single connection)
- Connection lifetime and reconnection
- SSL/TLS configuration
- Connection timeout handling
- Memory leak mitigation (postgres_crdt has maxConnectionAge parameter)

**Recommendation**: Follow postgres_crdt library's defaults for connection management.

#### 7.2 Transaction Isolation

**SQLite**: Single-writer, serialized access
**PostgreSQL**: Multi-version concurrency control (MVCC)

**Impact**: PostgreSQL can handle concurrent operations better than SQLite. The `isSequential: false` flag in the constructor reflects this.

**Testing**: Need to verify transaction isolation works correctly with CRDT merge operations.

#### 7.3 Type System Differences

**SQLite**: Dynamic typing with type affinity
**PostgreSQL**: Strong static typing

**Potential Issues**:
- Integer vs BigInt handling
- Timestamp formats
- Boolean representation (SQLite uses 0/1, PostgreSQL has native BOOLEAN)

**Mitigation**: The `postgres_crdt` library should handle type conversions. Need to verify through testing.

#### 7.4 Performance Considerations

**PostgreSQL Advantages**:
- Better indexing options
- Query planner and optimization
- Parallel query execution
- Sophisticated vacuum and maintenance

**PostgreSQL Challenges**:
- Network latency (local vs remote server)
- Connection overhead
- Server resource management

**Recommendation**: Add performance benchmarks comparing SQLite and PostgreSQL for typical CRDT operations.

#### 7.5 Migration Handling

**Current Status**: The code has "TODO: Sort out migration" comments for SQLite.

**PostgreSQL Migration Strategy**:
1. Use drift's standard migration system
2. Store version in `__schema` table (already implemented in version delegate)
3. CRDT columns must be added manually to migration schema_versions (same as SQLite)
4. Test migrations thoroughly with both backends

**Documentation**: The README already covers manual CRDT column injection for migrations (lines 80-169).

### Phase 8: Dependencies and Imports

#### 8.1 Required Imports

Add to `lib/drift_crdt.dart`:

```dart
import 'package:postgres/postgres.dart' show Endpoint, Connection, ConnectionSettings;
import 'package:postgres_crdt/postgres_crdt.dart' as postgres_crdt;
```

#### 8.2 Export Statements

Update exports in `lib/drift_crdt.dart`:

```dart
export 'package:postgres_crdt/postgres_crdt.dart'
    show Hlc, CrdtChangeset, parseCrdtChangeset, CrdtTableChangeset;
export 'package:postgres/postgres.dart'
    show Endpoint, ConnectionSettings, SslMode;
```

**Note**: Check for conflicts with existing `sqlite_crdt` exports.

#### 8.3 Pubspec Verification

The `pubspec.yaml` already includes:
- `postgres: ^3.5.7`
- `postgres_crdt: ^4.0.0`
- `drift_postgres: ^1.3.1`

All required dependencies are present!

## Implementation Checklist

### Core Implementation
- [ ] Add PostgreSQL imports and type definitions
- [ ] Implement `PostgresTransactionCrdt` class
- [ ] Implement `_PostgresCrdtTransactionDelegate` class
- [ ] Implement `_PostgresCrdtVersionDelegate` class
- [ ] Implement `_PostgresCrdtDelegate` class
- [ ] Implement `_PostgresCrdtDelegateOpened` class (if postgres_crdt supports it)
- [ ] Add `CrdtQueryExecutor.postgres()` constructor
- [ ] Add `CrdtQueryExecutor.postgresOpened()` constructor (if supported)
- [ ] Update `_sqlCrdt` getter to handle PostgresCrdtDelegate (already done!)

### Query Utilities
- [ ] Update `DriftCrdtUtils.isSpecialQuery()` for PostgreSQL system tables
- [ ] Verify `DriftCrdtUtils.prepareCreateTableQuery()` works with PostgreSQL
- [ ] Verify `DriftCrdtUtils.prepareSelectStatement()` works with PostgreSQL

### Testing
- [ ] Run all unit tests with PostgreSQL backend
- [ ] Run integration tests with PostgreSQL backend
- [ ] Test transaction handling
- [ ] Test batch operations
- [ ] Test migration scenarios
- [ ] Test queryDeleted functionality
- [ ] Test getChangeset/merge operations
- [ ] Test concurrent operations (PostgreSQL specific)
- [ ] Performance benchmarks

### Documentation
- [ ] Verify README PostgreSQL section accuracy
- [ ] Update CLAUDE.md with PostgreSQL notes
- [ ] Add code comments for PostgreSQL-specific behavior
- [ ] Document any limitations or differences from SQLite

### Edge Cases
- [ ] Verify connection lifecycle management
- [ ] Test SSL/TLS connections
- [ ] Test connection pooling scenarios
- [ ] Verify type conversions (int/bigint, timestamps, etc.)
- [ ] Test error handling and recovery
- [ ] Test RETURNING clause handling

## Potential Risks and Mitigations

### Risk 1: postgres_crdt API Differences
**Impact**: High
**Probability**: Medium
**Mitigation**: Review postgres_crdt source code to verify API compatibility with sqlite_crdt. May need to adapt transaction handling or query execution.

### Risk 2: Query Transformation Compatibility
**Impact**: High
**Probability**: Low
**Mitigation**: The sqlparser library is dialect-agnostic for basic SQL. Extensive testing will catch dialect-specific issues.

### Risk 3: Schema Versioning
**Impact**: Medium
**Probability**: Low
**Mitigation**: Use drift_postgres conventions for __schema table. Well-documented pattern.

### Risk 4: Type System Mismatches
**Impact**: Medium
**Probability**: Medium
**Mitigation**: Rely on postgres_crdt and drift_postgres to handle type conversions. Add explicit tests for edge cases.

### Risk 5: Missing fromSession() Method
**Impact**: Low
**Probability**: Medium
**Mitigation**: If postgres_crdt doesn't support session-based initialization, defer the `postgresOpened()` constructor to a future version.

## Success Criteria

1. All existing tests pass with `DRIFT_CRDT_TEST_BACKEND=postgres`
2. Can create, read, update, delete records via Drift with PostgreSQL
3. CRDT operations (getChangeset, merge, getLastModified) work correctly
4. Transaction handling works correctly
5. Schema migrations work (with manual CRDT column injection)
6. `queryDeleted()` helper works correctly
7. Performance is acceptable for typical workloads
8. Documentation is complete and accurate

## Future Enhancements

1. **Automatic CRDT Column Injection for Migrations**: Extend drift's code generation to automatically include CRDT columns in schema_versions
2. **Connection Pool Management**: Built-in connection pooling for better resource management
3. **Real-time Sync**: Leverage PostgreSQL's NOTIFY/LISTEN for real-time changeset propagation
4. **Partial Sync**: Optimize changeset generation for large databases
5. **Conflict Resolution Strategies**: Configurable conflict resolution beyond last-write-wins
6. **Multi-tenancy Support**: Schema-based or database-based multi-tenancy patterns
7. **Backup/Restore**: CRDT-aware backup and restore utilities
8. **Monitoring**: Built-in metrics and observability for CRDT operations

## References

- [drift documentation](https://drift.simonbinder.eu/docs/)
- [drift_postgres documentation](https://drift.simonbinder.eu/platforms/postgres/)
- [sqlite_crdt package](https://pub.dev/packages/sqlite_crdt)
- [postgres_crdt package](https://pub.dev/packages/postgres_crdt)
- [sql_crdt package](https://pub.dev/packages/sql_crdt)
- [postgres package](https://pub.dev/packages/postgres)

## Conclusion

The implementation of `_PostgresCrdtDelegate` follows established patterns from the SQLite implementation, adapting for PostgreSQL-specific requirements. The architecture is clean, the existing test infrastructure supports both backends, and the documentation is already partially in place.

The main work involves:
1. Creating parallel delegate classes for PostgreSQL
2. Handling PostgreSQL-specific query semantics (RETURNING clauses, schema versioning)
3. Ensuring query transformation utilities work with both dialects
4. Comprehensive testing to verify correctness

With careful attention to the differences between SQLite and PostgreSQL, particularly around connection management, transactions, and type systems, this implementation will provide a robust PostgreSQL CRDT backend for Drift.
