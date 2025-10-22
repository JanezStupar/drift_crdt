## 2.0.0

**BREAKING CHANGE: Package is now Flutter-agnostic**

This major version removes the Flutter SDK dependency, making `drift_crdt` compatible with pure Dart applications while maintaining full backward compatibility with Flutter apps.

### Breaking Changes
- **Removed Flutter SDK dependency** - The package no longer requires the Flutter SDK
- **Replaced `sqflite` with `sqflite_common_ffi`** - Pure Dart applications should initialize `sqfliteFfiInit()` and set `databaseFactory = databaseFactoryFfi` for desktop platforms
- **Version bumped to 2.0.0** to indicate the breaking change in dependencies

### Migration Guide
- **Flutter apps**: No changes required! The package remains 100% backward compatible
- **Pure Dart apps**: Add FFI initialization for desktop platforms (see MIGRATION_V2.md)

### What's New
- ✅ Works in pure Dart CLI applications
- ✅ Works in server-side Dart applications
- ✅ Works on desktop without Flutter (Linux, Windows, macOS)
- ✅ Still fully compatible with Flutter applications
- ✅ All tests remain functional using `drift_testcases` (which is also Flutter-agnostic)

### Technical Changes
- Updated library imports from `package:sqflite/sqflite.dart` to `package:sqflite_common_ffi/sqflite_ffi.dart`
- Replaced `flutter_test` with `test` package in test suite
- Updated documentation to reflect Dart-agnostic nature
- Added `drift_testcases` as dev dependency for comprehensive testing

See MIGRATION_V2.md for detailed migration instructions and examples.

## 1.1.1
- Ensure default changeset queries order records by primary key (typically `id`) and document the behavior.

## 1.1.0
- Added a `CrdtQueryExecutor.postgres` constructor and Postgres-specific delegates so CRDT workflows now run on `postgres_crdt`.
- Normalized SQL placeholder handling across SQLite and Postgres, including support for `$n` syntax and consistent `RETURNING` clause mapping.
- Extended CRDT transaction plumbing and utilities to share code between backends while preserving automatic `is_deleted` filtering.
- Improved binary (`Uint8List`) parameter binding for Postgres and removed noisy debug logging throughout the stack.

## 1.0.11
- Downgrade Drift to 2.26.0 due to version conflict with kiwi downstream

## 1.0.10
- Replace the `synchroflite` library with `sqlite_crdt` 

## 1.0.9
- Add LazyDatabase implementation compatible with CRDT.

## 1.0.8
- Bump Drift to 2.15.0 and synchroflite to 0.1.3

## 1.0.7
- Improve serializable datatype.
- Bump dependencies.

## 1.0.6
- Add crdt library to dependencies and reexport it.

## 1.0.5
- Add bypass for the queryDeleted function for non CRDT databases.

## 1.0.4
- Added an 'inMemory' constructor to the database. This is useful for testing and development.

## 1.0.3
- Update Readme with migrations instructions.

## 1.0.2
- Upgraded synchroflite to 0.1.1

## 1.0.1
- Added note about Android and iOS support.

## 1.0.0

- Initial release based on drift_sqflite.
