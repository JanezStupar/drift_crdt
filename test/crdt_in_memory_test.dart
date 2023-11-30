import 'dart:io';

import 'package:drift_crdt/drift_crdt.dart';
import 'package:drift_testcases/suite/crud_tests.dart';
import 'package:drift_testcases/suite/custom_objects.dart';
import 'package:drift_testcases/suite/transactions.dart';
import 'package:drift_testcases/tests.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactory, databaseFactoryFfi;

class CrdtExecutor extends TestExecutor {
  // Nested transactions are not supported because the Sqflite backend doesn't
  // support them.
  @override
  bool get supportsNestedTransactions => false;

  @override
  DatabaseConnection createConnection() {
    return DatabaseConnection(
      CrdtQueryExecutor.inMemory(),
    );
  }

  @override
  Future deleteData() async {}
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
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    databaseFactory = databaseFactoryFfi;
  }

  var executor = CrdtExecutor();
  runSomeTests(executor);
}

class EmptyDb extends GeneratedDatabase {
  EmptyDb(QueryExecutor q) : super(q);
  @override
  final List<TableInfo> allTables = const [];
  @override
  final schemaVersion = 1;
}
