import 'dart:io';

import 'package:drift_crdt/drift_crdt.dart';
import 'package:drift_testcases/tests.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactory, databaseFactoryFfi, getDatabasesPath;

class CrdtExecutor extends TestExecutor {
  // Nested transactions are not supported because the Sqflite backend doesn't
  // support them.
  @override
  bool get supportsNestedTransactions => false;

  @override
  DatabaseConnection createConnection() {
    return DatabaseConnection(
      CrdtQueryExecutor.inDatabaseFolder(
        path: 'app.db',
        singleInstance: false,
      ),
    );
  }

  @override
  Future deleteData() async {
    final folder = await getDatabasesPath();
    final file = File(join(folder, 'app.db'));

    if (await file.exists()) {
      await file.delete();
    }
  }
}

Future<void> main() async {
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    databaseFactory = databaseFactoryFfi;
  }

  var executor = CrdtExecutor();
  executor.deleteData();
  runAllTests(executor);
}

class EmptyDb extends GeneratedDatabase {
  EmptyDb(super.q);
  @override
  final List<TableInfo> allTables = const [];
  @override
  final schemaVersion = 1;
}
