import 'package:drift_crdt/drift_crdt.dart';
import 'package:drift_crdt_testing/drift_crdt_testing.dart' as testing;
import 'package:drift_testcases/tests.dart';
import 'package:test/test.dart';

Future<void> main() async {
  await testing.configureBackendForPlatform();

  group('per-table CRDT configuration', () {
    test('getChangeset respects onlyTables defaults', () async {
      final harness = await _TestHarness.open(
        sqliteDbName: 'per_table_only.db',
        schemaName: 'per_table_only',
        onlyTables: const {'users'},
      );
      addTearDown(harness.dispose);

      final db = harness.db;
      await testing.resetAndSeedBaselineData(db);

      final changeset = await (db.executor as CrdtQueryExecutor).getChangeset();

      expect(changeset.containsKey('users'), isTrue);
      expect(
        changeset.containsKey('friendships'),
        isFalse,
        reason: 'friendships should be omitted when onlyTables is set',
      );
    });

    test('excluded tables are queried without CRDT filters', () async {
      final harness = await _TestHarness.open(
        sqliteDbName: 'per_table_exclude.db',
        schemaName: 'per_table_exclude',
        excludeTables: const {'handshake_nodes'},
      );
      addTearDown(harness.dispose);

      final db = harness.db;
      await testing.resetAndSeedBaselineData(db);
      await _createNonCrdtSyncTable(db);

      final rows = await db
          .customSelect('SELECT * FROM handshake_nodes ORDER BY id')
          .get();

      final names = rows.map((row) => row.read<String>('name')).toSet();
      expect(names, equals({'alpha', 'beta'}));
      final deletedFlags =
          rows.map((row) => row.read<int>('is_deleted')).toSet();
      expect(deletedFlags, equals({0, 1}));
    });

    test('non-excluded tables still enforce CRDT filters', () async {
      final harness = await _TestHarness.open(
        sqliteDbName: 'per_table_enforced.db',
        schemaName: 'per_table_enforced',
      );
      addTearDown(harness.dispose);

      final db = harness.db;
      await testing.resetAndSeedBaselineData(db);
      await _createNonCrdtSyncTable(db);

      final rows = await db
          .customSelect('SELECT * FROM handshake_nodes ORDER BY id')
          .get();

      expect(rows, hasLength(1),
          reason: 'CRDT filters should hide rows marked as deleted');
      expect(rows.single.read<int>('is_deleted'), equals(0));
      expect(rows.single.read<String>('name'), equals('alpha'));
    });
  });
}

Future<void> _createNonCrdtSyncTable(Database db) async {
  await db.customStatement('DROP TABLE IF EXISTS handshake_nodes');
  await db.customStatement(
    'CREATE TABLE handshake_nodes ('
    'id INTEGER PRIMARY KEY, '
    'name TEXT NOT NULL, '
    'is_deleted INTEGER NOT NULL DEFAULT 0'
    ')',
  );
  await db.customStatement(
    "INSERT INTO handshake_nodes (id, name, is_deleted) VALUES (1, 'alpha', 0)",
  );
  await db.customStatement(
    "INSERT INTO handshake_nodes (id, name, is_deleted) VALUES (2, 'beta', 1)",
  );
}

class _TestHarness {
  final CrdtQueryExecutor executor;
  final Database db;
  final String sqliteDbName;
  final String? postgresSchema;

  _TestHarness._(
      {required this.executor,
      required this.db,
      required this.sqliteDbName,
      required this.postgresSchema});

  static Future<_TestHarness> open({
    required String sqliteDbName,
    required String schemaName,
    Set<String>? onlyTables,
    Set<String>? excludeTables,
  }) async {
    final schema = testing.backendConfig.isPostgres ? schemaName : null;
    await testing.clearBackend(
      sqliteDbName: sqliteDbName,
      postgresSchema: schema,
    );

    final executor = testing.createExecutor(
      sqliteDbName: sqliteDbName,
      postgresSchema: schema,
      singleInstance: false,
      onlyTables: onlyTables,
      excludeTables: excludeTables,
    );

    final connection = DatabaseConnection(executor);
    final db = Database(connection);
    await connection.ensureOpen(db);

    return _TestHarness._(
      executor: executor,
      db: db,
      sqliteDbName: sqliteDbName,
      postgresSchema: schema,
    );
  }

  Future<void> dispose() async {
    await db.close();
    await executor.close();
    await testing.clearBackend(
      sqliteDbName: sqliteDbName,
      postgresSchema: postgresSchema,
    );
  }
}
