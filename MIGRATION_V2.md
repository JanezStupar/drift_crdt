# Migration Guide: v1.x to v2.0.0

## Overview

Version 2.0.0 makes `drift_crdt` **Flutter-agnostic**. The package now works with pure Dart applications while still fully supporting Flutter.

## Breaking Changes

### 1. No Flutter Dependency Required

**Before (v1.x):**
```yaml
dependencies:
  flutter:
    sdk: flutter
  drift_crdt: ^1.0.0
```

**After (v2.0.0):**
```yaml
dependencies:
  drift_crdt: ^2.0.0  # No Flutter SDK required!
```

### 2. Database Initialization

The API remains the same, but the underlying implementation now uses `sqflite_common_ffi` instead of `sqflite`.

**No code changes needed!** Your existing code will continue to work:

```dart
// Still works exactly the same
final executor = CrdtQueryExecutor(path: 'my_database.db');
final executor = CrdtQueryExecutor.inMemory();
final executor = CrdtQueryExecutor.inDatabaseFolder(path: 'app.db');
```

### 3. Platform Initialization (Desktop/CLI only)

For pure Dart applications on desktop (Linux, Windows, macOS), you need to initialize `sqflite_common_ffi`:

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Initialize FFI for desktop platforms
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Now use drift_crdt as usual
  final executor = CrdtQueryExecutor(path: 'my_database.db');
  // ...
}
```

**Note:** Flutter apps don't need this initialization - it's handled automatically.

## What's New

### Pure Dart Support

You can now use `drift_crdt` in:
- ✅ CLI applications
- ✅ Server-side Dart (with Dart VM)
- ✅ Desktop applications (Linux, Windows, macOS)
- ✅ Flutter applications (as before)

### PostgreSQL Backend

The PostgreSQL backend continues to work without any changes:

```dart
final executor = CrdtQueryExecutor.postgres(
  endpoint: Endpoint(
    host: 'localhost',
    port: 5432,
    database: 'mydb',
  ),
);
```

## Testing

### Running Tests

**Before (v1.x):**
```bash
flutter test
```

**After (v2.0.0):**
```bash
dart test
```

### Platform-Specific Tests

```bash
# SQLite backend (default)
export DRIFT_CRDT_TEST_BACKEND=sqlite
dart test

# PostgreSQL backend
export DRIFT_CRDT_TEST_BACKEND=postgres
export DRIFT_CRDT_PG_HOST=localhost
export DRIFT_CRDT_PG_DB=test
export DRIFT_CRDT_PG_USER=postgres
export DRIFT_CRDT_PG_PASSWORD=password
dart test
```

## Dependencies

### Removed
- `flutter` SDK dependency
- `flutter_test`
- `integration_test`

### Added
- None! `sqflite_common_ffi` was already a dependency

### Changed
- Uses `lints` instead of `flutter_lints`
- Uses `test` instead of `flutter_test` for testing

## Important Notes

### Test Suite

All tests remain available and work without Flutter! The test suite uses `drift_testcases` which is also Flutter-agnostic. You can run tests with:

```bash
# All tests
dart test

# Specific test
dart test test/crdt_functions_test.dart
```

## FAQ

### Will my Flutter app still work?

**Yes!** The package is 100% backward compatible for Flutter apps. All existing code will work without changes.

### Do I need to change my code?

**For Flutter apps:** No changes needed.

**For pure Dart apps:** Add the FFI initialization shown above.

### What about asset loading?

If you were using the `creator` callback to load databases from Flutter assets, you'll need to continue using Flutter's `rootBundle` in Flutter apps. For pure Dart apps, load from the file system directly.

### Can I still use this in production?

**Absolutely!** The underlying CRDT functionality is unchanged. This is purely a packaging change to make the library more versatile.

## Support

For issues or questions, please file an issue at:
https://github.com/JanezStupar/drift_crdt/issues
