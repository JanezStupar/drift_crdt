import 'package:drift_testcases/suite/crud_tests.dart';
import 'package:drift_testcases/suite/custom_objects.dart';
import 'package:drift_testcases/suite/migrations.dart';
import 'package:drift_testcases/suite/transactions.dart';
import 'package:drift_testcases/tests.dart';
import 'package:test/test.dart';

import 'utils/test_backend.dart' as backend;

class CrdtExecutor extends TestExecutor {
  // Nested transactions are not supported because the Sqflite backend doesn't
  // support them.
  @override
  bool get supportsNestedTransactions => false;

  final String _sqliteDbName = 'app.db';

  @override
  DatabaseConnection createConnection() {
    final executor = backend.createExecutor(
      sqliteDbName: _sqliteDbName,
      singleInstance: false,
    );
    return DatabaseConnection(executor);
  }

  @override
  Future deleteData() async {
    await backend.clearBackend(sqliteDbName: _sqliteDbName);
  }
}

/// Runs only the suites supported by the current backend (skipping migrations on Postgres).
void runSupportedTests(TestExecutor executor) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tearDown(() async {
    await executor.deleteData();
  });

  crudTests(executor);

  if (!backend.backendConfig.isPostgres) {
    migrationTests(executor);
  }

  customObjectTests(executor);
  transactionTests(executor);

  test('can close database without interacting with it', () async {
    final connection = executor.createConnection();

    await connection.executor.close();
  });
}

Future<void> main() async {
  await backend.configureBackendForPlatform();

  final executor = CrdtExecutor();
  await executor.deleteData();

  runSupportedTests(executor);
}

class EmptyDb extends GeneratedDatabase {
  EmptyDb(super.q);
  @override
  final List<TableInfo> allTables = const [];
  @override
  final schemaVersion = 1;
}
