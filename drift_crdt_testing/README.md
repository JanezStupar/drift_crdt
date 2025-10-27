# drift_crdt_testing

Testing utilities for [drift_crdt](../README.md), providing multi-backend support and reusable test fixtures for packages that use drift_crdt.

## Features

- **Multi-backend testing**: Run tests against both SQLite and PostgreSQL with a single codebase
- **Environment-based configuration**: Select backend via environment variables
- **Reusable test utilities**: Backend abstraction, executor creation, and cleanup helpers
- **Test fixtures**: Pre-built data seeding for common test scenarios
- **JSON serialization**: Base class for CRDT-aware serializable models

## Installation

Add to your `pubspec.yaml`:

```yaml
dev_dependencies:
  drift_crdt_testing:
    path: ../drift_crdt_testing  # or another relative path
```

## Usage

### Basic Setup

```dart
import 'package:drift_crdt_testing/drift_crdt_testing.dart';
import 'package:drift_testcases/tests.dart';

void main() async {
  // Configure platform-specific database setup
  await configureBackendForPlatform();

  // Create a CRDT executor (SQLite or PostgreSQL)
  final executor = createExecutor(
    sqliteDbName: 'test.db',
    singleInstance: true,
  );

  // Set up your database connection
  final connection = DatabaseConnection(executor);
  final db = Database(connection);

  // Run tests...
}
```

### Multi-Backend Testing

Select backend via environment variable:

```bash
# Run tests with SQLite (default)
dart test

# Run tests with PostgreSQL
export DRIFT_CRDT_TEST_BACKEND=postgres
export DRIFT_CRDT_PG_USER=postgres
export DRIFT_CRDT_PG_PASSWORD=password
dart test
```

### Environment Variables

**Backend Selection:**
- `DRIFT_CRDT_TEST_BACKEND` - `sqlite` (default) or `postgres`

**PostgreSQL Configuration:**
- `DRIFT_CRDT_PG_HOST` - PostgreSQL host (default: `localhost`)
- `DRIFT_CRDT_PG_PORT` - PostgreSQL port (default: `5432`)
- `DRIFT_CRDT_PG_DB` - Database name (default: `postgres`)
- `DRIFT_CRDT_PG_USER` - PostgreSQL username
- `DRIFT_CRDT_PG_PASSWORD` - PostgreSQL password
- `DRIFT_CRDT_PG_ENABLE_MIGRATIONS` - Enable migrations (default: `true`)
- `DRIFT_CRDT_PG_SSL_MODE` - SSL mode: `disable`, `require`, `verify_full` (default: `disable`)

### Test Data Seeding

Use `resetAndSeedBaselineData()` to populate test databases with baseline data:

```dart
import 'package:drift_crdt_testing/drift_crdt_testing.dart';

await resetAndSeedBaselineData(db);
// Database now contains:
// - 3 users: Dash, Duke, Go Gopher
// - 1 friendship: Dash & Duke
```

### Creating Custom Test Executors

Extend `TestExecutor` from `drift_testcases`:

```dart
import 'package:drift_crdt_testing/drift_crdt_testing.dart';
import 'package:drift_testcases/tests.dart';

class MyTestExecutor extends TestExecutor {
  @override
  bool get supportsNestedTransactions => false;

  final String _dbName = 'mytest.db';

  @override
  DatabaseConnection createConnection() {
    final executor = createExecutor(
      sqliteDbName: _dbName,
      singleInstance: true,
    );
    return DatabaseConnection(executor);
  }

  @override
  Future<void> deleteData() async {
    await clearBackend(sqliteDbName: _dbName);
  }
}
```

### JSON Serialization

Use `User` as an example for creating CRDT-aware serializable models:

```dart
import 'package:drift_crdt_testing/drift_crdt_testing.dart';

// User extends BaseCrdtSerializable and provides JSON serialization
final userJson = {
  'id': 1,
  'hlc': '2025-10-27T10:00:00Z-node1',
  'node_id': 'node1',
  'modified': '2025-10-27T10:00:00Z',
  'is_deleted': 0,
  'name': 'Dash',
  'birth_date': 1318284000,
};

final user = User.fromJson(userJson);
final json = user.toJson();
```

## API Reference

### Functions

#### `configureBackendForPlatform()`
Sets up platform-specific database configuration. On desktop platforms (Linux, Windows, macOS), initializes `sqflite_common_ffi`.

#### `createExecutor({...})`
Creates a CRDT query executor for the configured backend.

**Parameters:**
- `inMemory` - Create in-memory database (SQLite only)
- `sqliteDbName` - SQLite database file name (default: `'app.db'`)
- `singleInstance` - Reuse single database instance (default: `true`)
- `sqliteCreator` - Custom SQLite database creator

**Returns:** `CrdtQueryExecutor`

#### `clearBackend({required String sqliteDbName})`
Clears all data from the test database.
- SQLite: Deletes database file
- PostgreSQL: Truncates schema and recreates public schema

#### `resetAndSeedBaselineData(Database db)`
Resets and populates database with baseline test data:
- 3 users: Dash, Duke, Go Gopher
- 1 friendship relationship

### Classes

#### `BackendConfig`
Configuration for the test backend.

**Properties:**
- `backend` - `TestBackend.sqlite` or `TestBackend.postgres`
- `endpoint` - PostgreSQL connection endpoint (null for SQLite)
- `enableMigrations` - Whether migrations are enabled
- `sslMode` - SSL mode for PostgreSQL connections
- `isSqlite` - Boolean shorthand
- `isPostgres` - Boolean shorthand

**Static Methods:**
- `fromEnvironment()` - Parse configuration from environment variables

#### `TestBackend` enum
- `sqlite` - SQLite backend
- `postgres` - PostgreSQL backend

#### `User` (Example Model)
Extends `BaseCrdtSerializable` with JSON serialization. Demonstrates creating CRDT-aware models.

### Properties

#### `backendConfig`
Global getter returning the cached backend configuration. Automatically populated from environment variables on first access.

## Example: Testing Against Both Backends

```dart
import 'package:drift_crdt_testing/drift_crdt_testing.dart';
import 'package:drift_testcases/tests.dart';
import 'package:test/test.dart';

void main() async {
  await configureBackendForPlatform();

  group('CRDT Tests - ${backendConfig.backend.name.toUpperCase()}', () {
    late Database db;

    setUp(() async {
      final executor = createExecutor(sqliteDbName: 'test.db');
      final connection = DatabaseConnection(executor);
      db = Database(connection);
    });

    tearDown(() async {
      await clearBackend(sqliteDbName: 'test.db');
    });

    test('seeds baseline data', () async {
      await resetAndSeedBaselineData(db);
      final users = await db.select(db.users).get();
      expect(users.length, equals(3));
    });
  });
}
```

## Development

To regenerate JSON serialization code:

```bash
dart run build_runner build
```

To watch for changes:

```bash
dart run build_runner watch
```

## Testing

Run tests in `drift_crdt` which uses these utilities:

```bash
cd ../
dart test
```

Or with PostgreSQL:

```bash
export DRIFT_CRDT_TEST_BACKEND=postgres
export DRIFT_CRDT_PG_USER=postgres
dart test
```
