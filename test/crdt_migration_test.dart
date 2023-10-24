import 'dart:io';

import 'package:drift_crdt/drift_crdt.dart';
import 'package:drift_testcases/tests.dart' as tc;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactory, databaseFactoryFfi;

void crdtMigrationTests() {
  test('on nonmigrated database an error occurs', () async {
    final connection = tc.DatabaseConnection(CrdtQueryExecutor.inDatabaseFolder(
      path: 'app_from_asset_migration.db',
      singleInstance: true,
      creator: (file) async {
        final content = await rootBundle.load('test_asset_migration.db');
        await file.writeAsBytes(content.buffer.asUint8List());
      },
      migrate: false,
    ));

    try {
      final db = tc.Database(connection);
      await connection.ensureOpen(db);
    } on DatabaseException catch (e) {
      expect(e.toString().contains('no such column: modified'), isTrue);
    }
    connection.close();
  });

  test('if migration parameter is passed migration gets performed', () async {
    // the connection SHOULD generate a warning about opening multiple connections
    // that is fine for this test. We are testing whether the migration is performed
    final connection = tc.DatabaseConnection(CrdtQueryExecutor.inDatabaseFolder(
      path: 'app_from_asset_migration.db',
      singleInstance: true,
      creator: (file) async {
        final content = await rootBundle.load('test_asset_migration.db');
        await file.writeAsBytes(content.buffer.asUint8List());
      },
      migrate: true,
    ));

    final db = tc.Database(connection);
    await connection.ensureOpen(db);
    final result = await db.select(db.users).get();

    expect(result, isNotNull);
    expect(result.length, equals(3));
  });
}

Future<void> main() async {
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    databaseFactory = databaseFactoryFfi;
  }

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  crdtMigrationTests();
}
