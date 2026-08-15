import 'dart:io';

import 'package:drift_crdt/drift_crdt.dart';
import 'package:drift_testcases/tests.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show
        DatabaseException,
        databaseFactory,
        databaseFactoryFfi,
        getDatabasesPath;
import 'package:test/test.dart';

class CrdtExecutor extends TestExecutor {
  final String databasePath;

  CrdtExecutor(this.databasePath);

  // Nested transactions are not supported because the Sqflite backend doesn't
  // support them.
  @override
  bool get supportsNestedTransactions => false;

  @override
  DatabaseConnection createConnection() {
    return DatabaseConnection(
      CrdtQueryExecutor(path: databasePath, singleInstance: false),
    );
  }

  @override
  Future deleteData() async {
    final file = File(databasePath);

    if (await file.exists()) {
      await file.delete();
    }
  }
}

Future<void> main() async {
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    databaseFactory = databaseFactoryFfi;
  }

  // Resolve the test path once so setup, the executor, and teardown always
  // target the same file.
  final databasesPath = await getDatabasesPath();
  final testExecutor = CrdtExecutor(join(databasesPath, 'app.db'));
  setUp(testExecutor.deleteData);

  runAllTests(testExecutor);

  // Test loading a database from file (creator callback)
  test('can load a database with creator callback', () async {
    final dbFile = File(join(databasesPath, 'app_from_creator.db'));
    if (await dbFile.exists()) {
      await dbFile.delete();
    }

    var didCallCreator = false;
    final executor = CrdtQueryExecutor(
      path: dbFile.path,
      singleInstance: true,
      creator: (file) async {
        // Create an empty database file
        await file.writeAsBytes([]);
        didCallCreator = true;
      },
    );
    final database = Database.executor(executor);
    await database.executor.ensureOpen(database);
    addTearDown(() async {
      await database.close();
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
    });

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
      await database
          .customSelect('select 1')
          .getSingle()
          .timeout(
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
    await database.customStatement(
      'CREATE TABLE y (foo INTEGER PRIMARY KEY '
      'REFERENCES x (foo) DEFERRABLE INITIALLY DEFERRED);',
    );

    await expectLater(
      database.transaction(() async {
        await database.customStatement('INSERT INTO y (foo) VALUES (2);');
      }),
      throwsA(isA<DatabaseException>()),
    );

    expect(await database.customSelect('SELECT * FROM y').get(), isEmpty);
  });
}

class EmptyDb extends GeneratedDatabase {
  EmptyDb(super.q);
  @override
  final List<TableInfo> allTables = const [];
  @override
  final schemaVersion = 1;
}
