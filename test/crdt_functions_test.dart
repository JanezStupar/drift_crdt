import 'dart:convert';
import 'dart:io';

import 'package:drift_crdt/drift_crdt.dart';
import 'package:drift_testcases/tests.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactory, databaseFactoryFfi, getDatabasesPath;
import 'package:sqlite_crdt/sqlite_crdt.dart' show CrdtChangeset, Hlc;
import 'serializable.dart' as s;

void crdtTests(Database db, CrdtExecutor executor) {
  test('get last modified', () async {
    final lastModified =
        await (db.executor as CrdtQueryExecutor).getLastModified();

    expect(lastModified, isNotNull);
    expect(lastModified?.dateTime.millisecondsSinceEpoch, equals(1691413901771));
  });

  test('get changeset', () async {
    CrdtChangeset changeset = await (db.executor as CrdtQueryExecutor).getChangeset();

    expect(changeset, isNotNull);
    expect(changeset.length, equals(2));
    expect(
        json.encode(changeset),
        equals(
            '{"users":[{"id":1,"name":"Dash","birth_date":1318284000,"profile_picture":null,"preferences":null,"is_deleted":0,"hlc":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966","node_id":"42bab6fa-f6c6-4e5b-babf-1a2adb170966","modified":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"},{"id":2,"name":"Duke","birth_date":822351600,"profile_picture":null,"preferences":null,"is_deleted":0,"hlc":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966","node_id":"42bab6fa-f6c6-4e5b-babf-1a2adb170966","modified":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"},{"id":3,"name":"Go Gopher","birth_date":1332885600,"profile_picture":null,"preferences":null,"is_deleted":0,"hlc":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966","node_id":"42bab6fa-f6c6-4e5b-babf-1a2adb170966","modified":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"}],"friendships":[]}'));
  });

  test('update and get changeset', () async {
    await db.into(db.users).insert(florian);

    final changeset = await (db.executor as CrdtQueryExecutor).getChangeset();

    expect(changeset, isNotNull);
    expect(changeset.length, equals(2));
    expect(
        json.encode(changeset),
        equals(
            '{"users":[{"id":1,"name":"Dash","birth_date":1318284000,"profile_picture":null,"preferences":null,"is_deleted":0,"hlc":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966","node_id":"42bab6fa-f6c6-4e5b-babf-1a2adb170966","modified":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"},{"id":2,"name":"Duke","birth_date":822351600,"profile_picture":null,"preferences":null,"is_deleted":0,"hlc":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966","node_id":"42bab6fa-f6c6-4e5b-babf-1a2adb170966","modified":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"},{"id":3,"name":"Go Gopher","birth_date":1332885600,"profile_picture":null,"preferences":null,"is_deleted":0,"hlc":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966","node_id":"42bab6fa-f6c6-4e5b-babf-1a2adb170966","modified":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"},{"id":6,"name":"Florian, the fluffy Ferret from Florida familiar with Flutter","birth_date":1430258400,"profile_picture":null,"preferences":null,"is_deleted":0,"hlc":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966","node_id":"42bab6fa-f6c6-4e5b-babf-1a2adb170966","modified":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"}],"friendships":[]}'));
  });

  test('handle JSON changeset', () async {
    const raw =
        '{"users":[{"id":3,"name":"Go Gopher Updated","birth_date":1332885600,"profile_picture":null,"preferences":null,"is_deleted":0,"hlc":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966","node_id":"42bab6fa-f6c6-4e5b-babf-1a2adb170966","modified":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"},{"id":6,"name":"Florian Updated, the fluffy Ferret from Florida familiar with Flutter","birth_date":1430258400,"profile_picture":null,"preferences":null,"is_deleted":0,"hlc":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966","node_id":"42bab6fa-f6c6-4e5b-babf-1a2adb170966","modified":"2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"}]}';
    final decoded = json.decode(raw);

    Map<String, Iterable<Map<String, Object?>>> data = {};
    decoded.forEach((key, value) {
      List<Map<String, Object?>> tmp = [];
      value?.forEach((e) {
        tmp.add(s.User.fromJson(e).toJson());
      });
      data[key] = tmp;
    });

    expect(data, isNotNull);
    expect(data.length, equals(1));
    expect(data['users'], isNotNull);
    expect(data['users']?.length, equals(2));
    expect(data['users']?.first['name'], equals('Go Gopher Updated'));
  });

  test('reject merge changeset', () async {
    CrdtChangeset data = {
      "users": [
        {
          "id": 3,
          "name": "Go Gopher Updated",
          "birth_date": 1332885600,
          "profile_picture": null,
          "preferences": null,
          "is_deleted": 0,
          "hlc":
              Hlc.parse("2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"),
          "node_id": "42bab6fa-f6c6-4e5b-babf-1a2adb170966",
          "modified":
              "2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"
        },
        {
          "id": 6,
          "name":
              "Florian Updated, the fluffy Ferret from Florida familiar with Flutter",
          "birth_date": 1430258400,
          "profile_picture": null,
          "preferences": null,
          "is_deleted": 0,
          "hlc":
              Hlc.parse("2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"),
          "node_id": "42bab6fa-f6c6-4e5b-babf-1a2adb170966",
          "modified":
              "2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"
        }
      ]
    };

    await (db.executor as CrdtQueryExecutor).merge(data);

    var user =
        await (db.select(db.users)..where((tbl) => tbl.id.equals(3))).get();
    expect(user.length, equals(1));
    expect(user[0].name, equals('Go Gopher'));
  });

  test('accept merge changeset', () async {
    // There are two modified records in the changeset.
    // First one should be accepted because the hlc, nodeid and modified timestamp indicate a change
    // the second one indicates a stale record and the change should not be silently ignored.
    CrdtChangeset changeset = {
      "users": [
        {
          "id": 3,
          "name": "Go Gopher Updated",
          "birth_date": 1332885600,
          "profile_picture": null,
          "preferences": null,
          "is_deleted": 0,
          "hlc":
              Hlc.parse("2023-09-02T06:48:11.103Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170968"),
          "node_id":
              "2023-09-02T06:48:11.103Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170968",
          "modified":
              "2023-09-02T06:48:11.103Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170968",
        },
        {
          "id": 6,
          "name":
              "Florian Updated, the fluffy Ferret from Florida familiar with Flutter",
          "birth_date": 1430258400,
          "profile_picture": null,
          "preferences": null,
          "is_deleted": 0,
          "hlc":
              Hlc.parse("2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"),
          "node_id": "42bab6fa-f6c6-4e5b-babf-1a2adb170966",
          "modified":
              "2023-08-07T13:11:41.771Z-0000-42bab6fa-f6c6-4e5b-babf-1a2adb170966"
        }
      ]
    };

    await (db.executor as CrdtQueryExecutor).merge(changeset);

    // Change gets accepted
    var userGopher =
        await (db.select(db.users)..where((tbl) => tbl.id.equals(3))).get();
    expect(userGopher.length, equals(1));
    expect(userGopher[0].name, equals('Go Gopher Updated'));

    // Change gets rejected silently
    var userFlorian =
        await (db.select(db.users)..where((tbl) => tbl.id.equals(6))).get();
    expect(userFlorian.length, equals(1));
    expect(
        userFlorian[0].name,
        equals(
            'Florian, the fluffy Ferret from Florida familiar with Flutter'));
  });
}

class CrdtExecutor extends TestExecutor {
  // Nested transactions are not supported because the Sqflite backend doesn't
  // support them.
  @override
  bool get supportsNestedTransactions => false;

  @override
  DatabaseConnection createConnection() {
    return DatabaseConnection(CrdtQueryExecutor.inDatabaseFolder(
      path: 'app_from_asset.db',
      singleInstance: true,
      creator: (file) async {
        final content = await rootBundle.load('test_asset.db');
        await file.writeAsBytes(content.buffer.asUint8List());
      },
    ));
  }

  @override
  Future deleteData() async {
    final folder = await getDatabasesPath();
    final file = File(path.join(folder, 'app_from_asset.db'));

    if (await file.exists()) {
      await file.delete();
    }
  }
}

Future<void> main() async {
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    databaseFactory = databaseFactoryFfi;
  }

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final executor = CrdtExecutor();
  final connection = executor.createConnection();
  final db = Database(connection);
  await executor.deleteData();
  await connection.ensureOpen(db);

  crdtTests(db, executor);
}
