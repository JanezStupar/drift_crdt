import 'package:drift/drift.dart';
import 'package:drift_crdt/drift_crdt.dart';
import 'package:drift_crdt_testing/drift_crdt_testing.dart' as testing;
import 'package:test/test.dart';

part 'reserved_keyword_test.g.dart';

// Table with a reserved keyword column name
@DataClassName('Event')
class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  // "end" is a reserved keyword in PostgreSQL
  IntColumn get end => integer().named('end')();
}

// Database class for testing
@DriftDatabase(tables: [Events])
class EventsDatabase extends _$EventsDatabase {
  EventsDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
      );
}

void main() async {
  await testing.configureBackendForPlatform();

  group('Reserved keyword column names', () {
    late CrdtQueryExecutor executor;
    late EventsDatabase db;

    setUp(() async {
      executor = testing.createExecutor(
        sqliteDbName: 'reserved_keyword_test.db',
        singleInstance: false,
      );
      db = EventsDatabase(executor);
      // Ensure tables are created by running migrations
      final migrator = db.createMigrator();
      await migrator.createAll();
    });

    tearDown(() async {
      await db.close();
      await testing.clearBackend(sqliteDbName: 'reserved_keyword_test.db');
    });

    test(
      'PostgreSQL: "end" reserved keyword column can be created and used',
      () async {
        // Insert a row using Drift's type-safe API
        // This will generate SQL with the "end" reserved keyword column
        await db.into(db.events).insert(
              EventsCompanion.insert(
                name: 'Event 1',
                end: 100,
              ),
            );

        // Query using Drift's query builder - tests SELECT with reserved keyword
        final result = await (db.select(db.events)
              ..where((tbl) => tbl.name.equals('Event 1')))
            .get();

        expect(result, isNotEmpty);
        final event = result.first;
        expect(event.name, equals('Event 1'));
        expect(event.end, equals(100));

        // Update using Drift's update API - tests UPDATE with reserved keyword
        await (db.update(db.events)..where((tbl) => tbl.id.equals(event.id)))
            .write(const EventsCompanion(end: Value(200)));

        // Verify the update
        final updatedEvent = await (db.select(db.events)
              ..where((tbl) => tbl.id.equals(event.id)))
            .getSingle();

        expect(updatedEvent.end, equals(200));

        // Delete using Drift's delete API
        await (db.delete(db.events)..where((tbl) => tbl.id.equals(event.id)))
            .go();

        // Verify deletion
        final afterDelete = await db.select(db.events).get();
        expect(afterDelete, isEmpty);
      },
      // This test is specifically for PostgreSQL to verify reserved keyword handling
      skip: !testing.backendConfig.isPostgres
          ? 'PostgreSQL-specific test for reserved keywords'
          : null,
    );

    test(
      'SQLite: "end" column works without special quoting',
      () async {
        // Insert a row using Drift's type-safe API
        await db.into(db.events).insert(
              EventsCompanion.insert(
                name: 'Event 1',
                end: 100,
              ),
            );

        // Query using Drift's query builder
        final result = await (db.select(db.events)
              ..where((tbl) => tbl.name.equals('Event 1')))
            .get();

        expect(result, isNotEmpty);
        expect(result.first.name, equals('Event 1'));
        expect(result.first.end, equals(100));
      },
      skip: !testing.backendConfig.isSqlite
          ? 'SQLite-specific test'
          : null,
    );

    test(
      'CRDT-enabled tables with "end" reserved keyword column work correctly',
      () async {
        // This test ensures that the CRDT layer properly handles reserved keywords
        // in table definitions and queries when using Drift's high-level API

        // Insert using Drift's type-safe API
        final insertedId = await db.into(db.events).insert(
              EventsCompanion.insert(
                name: 'Event 1',
                end: 100,
              ),
            );

        // Query using Drift's select - the CRDT layer will inject filtering
        final result = await (db.select(db.events)
              ..where((tbl) => tbl.id.equals(insertedId)))
            .get();

        expect(result, isNotEmpty);
        final event = result.first;
        expect(event.name, equals('Event 1'));
        expect(event.end, equals(100));

        // Update using Drift's update API
        await (db.update(db.events)..where((tbl) => tbl.id.equals(insertedId)))
            .write(const EventsCompanion(end: Value(200)));

        // Verify the update through another query
        final updated = await (db.select(db.events)
              ..where((tbl) => tbl.id.equals(insertedId)))
            .getSingle();

        expect(updated.end, equals(200));

        // Test watch functionality with reserved keyword column
        final stream = (db.select(db.events)
              ..where((tbl) => tbl.id.equals(insertedId)))
            .watchSingle();

        // Get first emission
        final firstEmission = await stream.first;
        expect(firstEmission.end, equals(200));

        // Update again and verify the stream emits
        await (db.update(db.events)..where((tbl) => tbl.id.equals(insertedId)))
            .write(const EventsCompanion(end: Value(300)));

        // Wait for updated emission
        final updatedEmission = await stream.first;
        expect(updatedEmission.end, equals(300));
      },
    );
  });
}
