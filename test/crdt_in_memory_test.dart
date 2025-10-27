import 'package:drift_crdt_testing/drift_crdt_testing.dart' as testing;
import 'package:drift_testcases/suite/crud_tests.dart';
import 'package:drift_testcases/suite/custom_objects.dart';
import 'package:drift_testcases/suite/transactions.dart';
import 'package:drift_testcases/tests.dart';
import 'package:test/test.dart';

class CrdtExecutor extends TestExecutor {
  // Nested transactions are not supported because the Sqflite backend doesn't
  // support them.
  @override
  bool get supportsNestedTransactions => false;

  final String _sqliteDbName = 'in_memory.db';

  @override
  DatabaseConnection createConnection() {
    final executor = testing.createExecutor(
      inMemory: testing.backendConfig.isSqlite,
      sqliteDbName: _sqliteDbName,
    );
    return DatabaseConnection(executor);
  }

  @override
  Future deleteData() async {
    await testing.clearBackend(sqliteDbName: _sqliteDbName);
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
  await testing.configureBackendForPlatform();

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
