import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:drift_crdt/drift_crdt.dart';
import 'package:drift_testcases/tests.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS || kIsWeb) {
    databaseFactory = databaseFactoryFfi;
  }

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  runAllTests(CrdtExecutor());

  // Additional integration test for flutter: Test loading a database from asset
  test('can load a database from asset', () async {
    final databasesPath = await getDatabasesPath();
    final dbFile = File(join(databasesPath, 'app_from_asset.db'));
    if (await dbFile.exists()) {
      await dbFile.delete();
    }

    var didCallCreator = false;
    final executor = CrdtQueryExecutor(
      path: dbFile.path,
      singleInstance: true,
      creator: (file) async {
        final content = await rootBundle.load('test_asset.db');
        await file.writeAsBytes(content.buffer.asUint8List());
        didCallCreator = true;
      },
    );
    final database = Database.executor(executor);
    await database.executor.ensureOpen(database);
    addTearDown(database.close);

    expect(didCallCreator, isTrue);
  });

  test('can rollback transactions', () async {
    final executor = CrdtQueryExecutor(path: ':memory:');
    final database = EmptyDb(executor);
    addTearDown(database.close);

    final expectedException = Exception('oops');

    try {
      await database
          .customSelect('select 1')
          .getSingle(); // ensure database is open/created

      await database.transaction(() async {
        await database.customSelect('select 1').watchSingle().first;
        throw expectedException;
      });
    } catch (e) {
      expect(e, expectedException);
    } finally {
      await database.customSelect('select 1').getSingle().timeout(
            const Duration(milliseconds: 500),
            onTimeout: () => fail('deadlock?'),
          );
    }
  });

  test('handles failing commits', () async {
    final executor = CrdtQueryExecutor(path: ':memory:');
    final database = EmptyDb(executor);
    addTearDown(database.close);

    await database.customStatement('PRAGMA foreign_keys = ON;');
    await database.customStatement('CREATE TABLE x (foo INTEGER PRIMARY KEY);');
    await database.customStatement('CREATE TABLE y (foo INTEGER PRIMARY KEY '
        'REFERENCES x (foo) DEFERRABLE INITIALLY DEFERRED);');

    await expectLater(
      database.transaction(() async {
        await database.customStatement('INSERT INTO y VALUES (2);');
      }),
      throwsA(isA<CouldNotRollBackException>()),
    );
  });
}

class EmptyDb extends GeneratedDatabase {
  EmptyDb(QueryExecutor q) : super(q);
  @override
  final List<TableInfo> allTables = const [];
  @override
  final schemaVersion = 1;
}
