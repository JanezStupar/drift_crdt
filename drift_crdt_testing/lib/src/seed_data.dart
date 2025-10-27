import 'package:drift_testcases/tests.dart';

import 'test_backend.dart';

DateTime _unixSeconds(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

Future<void> resetAndSeedBaselineData(Database db) async {
  await db.transaction(() async {
    if (backendConfig.isPostgres) {
      await db.customStatement(
        'TRUNCATE TABLE "friendships" RESTART IDENTITY CASCADE',
      );
      await db.customStatement(
        'TRUNCATE TABLE "users" RESTART IDENTITY CASCADE',
      );
    } else {
      await db.delete(db.friendships).go();
      await db.delete(db.users).go();
    }

    final users = [
      UsersCompanion.insert(
        id: const Value(1),
        name: 'Dash',
        birthDate: _unixSeconds(1318284000),
      ),
      UsersCompanion.insert(
        id: const Value(2),
        name: 'Duke',
        birthDate: _unixSeconds(822351600),
      ),
      UsersCompanion.insert(
        id: const Value(3),
        name: 'Go Gopher',
        birthDate: _unixSeconds(1332885600),
      ),
    ];

    for (final user in users) {
      if (backendConfig.isPostgres) {
        await db.into(db.users).insertOnConflictUpdate(user);
      } else {
        await db.into(db.users).insert(user, mode: InsertMode.insertOrReplace);
      }
    }

    if (backendConfig.isPostgres) {
      await db.customStatement(
        '''
        SELECT setval(
          pg_get_serial_sequence('"users"', 'id'),
          (SELECT COALESCE(MAX("id"), 0) FROM "users"),
          true
        )
        ''',
      );
    }

    final friendship = FriendshipsCompanion.insert(
      firstUser: 1,
      secondUser: 2,
      reallyGoodFriends: const Value(true),
    );

    if (backendConfig.isSqlite) {
      await db
          .into(db.friendships)
          .insert(friendship, mode: InsertMode.insertOrReplace);
    } else {
      await db.into(db.friendships).insertOnConflictUpdate(friendship);
    }
  });

  // PostgreSQL sequences are reset via TRUNCATE ... RESTART IDENTITY.
}
