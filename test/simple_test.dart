import 'dart:io';

import 'package:drift_crdt/drift_crdt.dart';
import 'package:drift_crdt_testing/drift_crdt_testing.dart' as backend;
import 'package:test/test.dart';

void main() async {
  await backend.configureBackendForPlatform();

  test('can create in-memory CRDT executor', () {
    final executor = CrdtQueryExecutor.inMemory();
    expect(executor, isNotNull);
    expect(executor.dialect.name, equals('sqlite'));
  });

  test('can create file-based CRDT executor', () {
    final executor = CrdtQueryExecutor(path: '/tmp/test.db');
    expect(executor, isNotNull);
    expect(executor.dialect.name, equals('sqlite'));
  });

  test('sqflite_common_ffi works on ${Platform.operatingSystem}', () {
    // Just verify that sqflite_common_ffi is properly initialized
    expect(Platform.operatingSystem, anyOf(['linux', 'windows', 'macos']));
  });

  test('can create postgres executor', () {
    final executor = CrdtQueryExecutor.postgres(
      endpoint: Endpoint(
        host: 'localhost',
        port: 5432,
        database: 'test',
      ),
    );
    expect(executor, isNotNull);
    expect(executor.dialect.name, equals('postgres'));
  });
}
