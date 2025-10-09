import 'package:drift_testcases/suite/crud_tests.dart';
import 'package:drift_testcases/suite/custom_objects.dart';
import 'package:drift_testcases/suite/transactions.dart';
import 'package:drift_testcases/tests.dart';
import 'package:flutter_test/flutter_test.dart';

import 'utils/test_backend.dart' as backend;

class CrdtExecutor extends TestExecutor {
  // Nested transactions are not supported because the Sqflite backend doesn't
  // support them.
  @override
  bool get supportsNestedTransactions => false;

  final String _sqliteDbName = 'in_memory.db';

  @override
  DatabaseConnection createConnection() {
    final executor = backend.createExecutor(
      inMemory: backend.backendConfig.isSqlite,
      sqliteDbName: _sqliteDbName,
    );
    return DatabaseConnection(executor);
  }

  @override
  Future deleteData() async {
    await backend.clearBackend(sqliteDbName: _sqliteDbName);
  }
}

// TODO: remove this once we can run tests for migrations
void runSomeTests(TestExecutor executor) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tearDown(() async {
    await executor.deleteData();
  });

  crudTests(executor);
  // migrationTests(executor);
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
  runSomeTests(executor);
}

class EmptyDb extends GeneratedDatabase {
  EmptyDb(super.q);
  @override
  final List<TableInfo> allTables = const [];
  @override
  final schemaVersion = 1;
}
