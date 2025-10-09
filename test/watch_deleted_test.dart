import 'package:drift_testcases/tests.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'utils/seed_data.dart' as seeds;
import 'utils/test_backend.dart' as backend;

class _CrdtExecutor extends TestExecutor {
  @override
  bool get supportsNestedTransactions => false;

  final String _sqliteDbName = 'watch_deleted.db';

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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  await backend.configureBackendForPlatform();

  group('watch() on deleted rows', () {
    late _CrdtExecutor executor;
    late Database db;

    setUpAll(() async {
      executor = _CrdtExecutor();
      final connection = executor.createConnection();
      db = Database(connection);
      await executor.deleteData();
      await connection.ensureOpen(db);
      await seeds.resetAndSeedBaselineData(db);
    });

    tearDownAll(() async {
      await executor.deleteData();
    });

    test('deleted rows do not reappear in watch() results', () async {
      // Capture initial emission
      final stream = db.select(db.users).watch();

      // First emission should have initial users from the asset db (3 preloaded);
      // previous tests may add more; so we just track IDs we act on.
      final firstEmission = await stream.first;
      expect(firstEmission, isNotEmpty);

      // Insert a marker row we will then delete, to avoid coupling to fixture count
      await db.into(db.users).insert(
            UsersCompanion.insert(
              name: 'ToDelete',
              birthDate: DateTime.fromMillisecondsSinceEpoch(0),
              profilePicture: const Value.absent(),
              preferences: const Value.absent(),
            ),
          );

      // Determine the id of the inserted row
      final candidates = await (db.select(db.users)
            ..where((u) => u.name.equals('ToDelete')))
          .get();
      final insertedId =
          candidates.map((u) => u.id).reduce((a, b) => a > b ? a : b);

      // Next emission should include the inserted row
      final withInserted = await stream.firstWhere((rows) =>
          rows.any((u) => u.id == insertedId && u.name == 'ToDelete'));
      expect(withInserted.any((u) => u.id == insertedId), isTrue);

      // Now delete that row
      await (db.delete(db.users)..where((t) => t.id.equals(insertedId))).go();

      // Subsequent emission must NOT contain the deleted row
      final afterDelete = await stream
          .firstWhere((rows) => !rows.any((u) => u.id == insertedId));
      expect(afterDelete.any((u) => u.id == insertedId), isFalse);

      // Ensure it never reappears after more activity (e.g., updating another row)
      // Perform an unrelated update to trigger another emission
      if (afterDelete.isNotEmpty) {
        final someId = afterDelete.first.id;
        await (db.update(db.users)..where((t) => t.id.equals(someId))).write(
          const UsersCompanion(name: Value('TempNameForWatch')),
        );
        final afterUnrelatedUpdate = await stream.first;
        expect(afterUnrelatedUpdate.any((u) => u.id == insertedId), isFalse);
      }
    });

    test('watchSingleOrNull on a filtered query returns null after delete',
        () async {
      // Insert a fresh row
      await db.into(db.users).insert(
            UsersCompanion.insert(
              name: 'ToDeleteSingle',
              birthDate: DateTime.fromMillisecondsSinceEpoch(0),
              profilePicture: const Value.absent(),
              preferences: const Value.absent(),
            ),
          );

      final inserted = await (db.select(db.users)
            ..where((u) => u.name.equals('ToDeleteSingle')))
          .get();
      final userId = inserted.map((u) => u.id).reduce((a, b) => a > b ? a : b);

      final query = (db.select(db.users)..where((t) => t.id.equals(userId)));
      final singleStream = query.watchSingleOrNull();

      final first = await singleStream.first;
      expect(first, isNotNull);
      expect(first!.id, userId);

      // Delete the row
      await (db.delete(db.users)..where((t) => t.id.equals(userId))).go();

      // Now, watchSingleOrNull must emit null and never the deleted row again
      final after = await singleStream.firstWhere((row) => row == null);
      expect(after, isNull);

      // Trigger another emission and ensure it stays null
      await db.customStatement('SELECT 1');
      final afterAgain = await singleStream.first;
      expect(afterAgain, isNull);
    });
  });
}
