import 'dart:convert';

import 'package:drift_crdt/drift_crdt.dart';
import 'package:drift_testcases/tests.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'utils/seed_data.dart' as seeds;
import 'utils/serializable.dart' as s;
import 'utils/test_backend.dart' as backend;

void crdtTests(Database db, CrdtExecutor executor) {
  const baselineUserNames = {'Dash', 'Duke', 'Go Gopher'};
  Hlc _hlcFromChangesetValue(Object? value) {
    if (value is Hlc) return value;
    if (value is String) return Hlc.parse(value);
    throw ArgumentError('Unexpected HLC value: $value');
  }

  setUp(() async {
    await seeds.resetAndSeedBaselineData(db);
  });

  test('get last modified', () async {
    final lastModified =
        await (db.executor as CrdtQueryExecutor).getLastModified();

    expect(lastModified, isNotNull);
    expect(lastModified!.toString(), contains('-'));
  });

  test('get changeset', () async {
    final changeset = await (db.executor as CrdtQueryExecutor).getChangeset();

    expect(changeset, isNotNull);
    expect(changeset.containsKey('users'), isTrue);
    final users = changeset['users']!;
    expect(users.length, equals(baselineUserNames.length));
    final names = users.map((row) => row['name'] as String).toSet();
    expect(names, containsAll(baselineUserNames));
    expect(changeset.containsKey('friendships'), isTrue);
  });

  test('update and get changeset', () async {
    await db.into(db.users).insert(florian);

    final changeset = await (db.executor as CrdtQueryExecutor).getChangeset();

    final names =
        changeset['users']!.map((row) => row['name'] as String).toSet();
    expect(names, containsAll({...baselineUserNames, florian.name.value}));
  });

  test('handle JSON changeset', () async {
    final changeset = await (db.executor as CrdtQueryExecutor).getChangeset();

    final raw = json.encode(changeset);
    final decoded = json.decode(raw) as Map<String, dynamic>;

    final users = (decoded['users'] as List<dynamic>)
        .map((entry) => s.User.fromJson(
            Map<String, Object?>.from(entry as Map<String, Object?>)))
        .toList();

    expect(users, isNotEmpty);
    final seenNames = users.map((u) => u.name).toSet();
    expect(seenNames, containsAll(baselineUserNames));
  });

  test('reject merge changeset', () async {
    final changeset = await (db.executor as CrdtQueryExecutor).getChangeset();
    final target = Map<String, Object?>.from(changeset['users']!.first);
    final targetId = target['id'] as int;

    final staleHlc = _hlcFromChangesetValue(target['hlc']);
    final stale = Map<String, Object?>.from(target)
      ..['name'] = '${target['name']} Updated'
      ..['modified'] = target['modified']
      ..['hlc'] = staleHlc;

    await (db.executor as CrdtQueryExecutor).merge({
      'users': [stale]
    });

    final user = await (db.select(db.users)
          ..where((tbl) => tbl.id.equals(targetId)))
        .getSingle();
    expect(user.name, equals(target['name']));
  });

  test('accept merge changeset', () async {
    final changeset = await (db.executor as CrdtQueryExecutor).getChangeset();
    final target = Map<String, Object?>.from(
      changeset['users']!.firstWhere(
        (row) => row['name'] == 'Go Gopher',
        orElse: () => changeset['users']!.first,
      ),
    );
    final targetId = target['id'] as int;

    const remoteNodeId = 'remote-node-for-merge';
    final originalHlc = _hlcFromChangesetValue(target['hlc']);
    final updatedHlc = originalHlc
        .increment(
            wallTime: originalHlc.dateTime.add(const Duration(seconds: 1)))
        .apply(nodeId: remoteNodeId);

    final updated = Map<String, Object?>.from(target)
      ..['name'] = 'Go Gopher Updated'
      ..['hlc'] = updatedHlc
      ..['modified'] = updatedHlc.toString()
      ..['node_id'] = updatedHlc.nodeId;

    await (db.executor as CrdtQueryExecutor).merge({
      'users': [updated]
    });

    final user = await (db.select(db.users)
          ..where((tbl) => tbl.id.equals(targetId)))
        .getSingle();
    expect(user.name, equals('Go Gopher Updated'));
  });

  test('queryDeleted', () async {
    final notDeleted = await db.select(db.users).get();
    expect(notDeleted.length, equals(baselineUserNames.length));

    await (db.delete(db.users)
          ..where((tbl) => tbl.id.equals(notDeleted.first.id)))
        .go();

    final result = await queryDeleted(
      (db.executor) as CrdtQueryExecutor,
      () async => db.select(db.users).get(),
    );
    final resultNames = result
        .map((user) => user.name)
        .where(baselineUserNames.contains)
        .toSet();
    expect(resultNames.length, equals(baselineUserNames.length));

    final remaining = await db.select(db.users).get();
    expect(remaining.length, equals(baselineUserNames.length - 1));
  });

  test('queryDeleted in transaction', () async {
    final notDeleted = await db.select(db.users).get();
    expect(notDeleted.length, equals(baselineUserNames.length));

    final removedId = notDeleted.first.id;
    await (db.delete(db.users)..where((tbl) => tbl.id.equals(removedId))).go();

    await queryDeleted(
      (db.executor) as CrdtQueryExecutor,
      () async => db.transaction(() async {
        final resultTransaction = await db.select(db.users).get();
        final names = resultTransaction
            .map((user) => user.name)
            .where(baselineUserNames.contains)
            .toSet();
        expect(names.length, equals(baselineUserNames.length));
      }),
    );

    final remaining = await db.select(db.users).get();
    expect(remaining.length, equals(baselineUserNames.length - 1));
  });

  test('INSERT ... RETURNING with CRDT columns', () async {
    // Test that INSERT ... RETURNING works correctly with CRDT-enhanced tables using Drift syntax
    final newUser = UsersCompanion(
      name: const Value('Test User'),
      birthDate: Value(
          DateTime.fromMillisecondsSinceEpoch(946684800 * 1000)), // Jan 1, 2000
    );

    // Use Drift's insertReturning to insert and return the row
    final insertedUser = await db.into(db.users).insertReturning(newUser);

    expect(insertedUser, isNotNull);
    expect(insertedUser.name, equals('Test User'));
    expect(insertedUser.birthDate.millisecondsSinceEpoch,
        equals(946684800 * 1000));
    expect(insertedUser.id, isA<int>()); // ID should be auto-generated

    // Verify the record exists in the database
    final queriedUser = await (db.select(db.users)
          ..where((tbl) => tbl.id.equals(insertedUser.id)))
        .getSingle();
    expect(queriedUser.name, equals('Test User'));
    expect(queriedUser.id, equals(insertedUser.id));
  });
}

class CrdtExecutor extends TestExecutor {
  // Nested transactions are not supported because the Sqflite backend doesn't
  // support them.
  @override
  bool get supportsNestedTransactions => false;

  final String _sqliteDbName = 'crdt_functions.db';

  @override
  DatabaseConnection createConnection() {
    final executor = backend.createExecutor(
      sqliteDbName: _sqliteDbName,
      singleInstance: true,
    );
    return DatabaseConnection(executor);
  }

  @override
  Future deleteData() async {
    await backend.clearBackend(sqliteDbName: _sqliteDbName);
  }
}

Future<void> main() async {
  await backend.configureBackendForPlatform();
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final executor = CrdtExecutor();
  final connection = executor.createConnection();
  final db = Database(connection);
  await executor.deleteData();
  await connection.ensureOpen(db);
  await seeds.resetAndSeedBaselineData(db);

  crdtTests(db, executor);
}
