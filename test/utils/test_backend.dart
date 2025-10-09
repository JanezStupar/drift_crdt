import 'dart:io';

import 'package:drift_crdt/drift_crdt.dart';
import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactory, databaseFactoryFfi, getDatabasesPath;

enum TestBackend { sqlite, postgres }

class BackendConfig {
  final TestBackend backend;
  final Endpoint? endpoint;
  final bool enableMigrations;
  final SslMode sslMode;

  const BackendConfig({
    required this.backend,
    this.endpoint,
    this.enableMigrations = true,
    this.sslMode = SslMode.disable,
  });

  bool get isSqlite => backend == TestBackend.sqlite;

  bool get isPostgres => backend == TestBackend.postgres;

  static BackendConfig fromEnvironment() {
    final env = Platform.environment;
    final backendName =
        env['DRIFT_CRDT_TEST_BACKEND']?.toLowerCase().trim() ?? 'sqlite';

    switch (backendName) {
      case 'postgres':
        final host = env[_pg('HOST')] ?? 'localhost';
        final database = env[_pg('DB')] ?? 'postgres';
        final username = env[_pg('USER')];
        final password = env[_pg('PASSWORD')];
        final port = int.tryParse(env[_pg('PORT')] ?? '') ?? 5432;
        final enableMigrations =
            (env[_pg('ENABLE_MIGRATIONS')] ?? 'true').toLowerCase() != 'false';
        final sslMode = _parseSslMode(env[_pg('SSL_MODE')]);

        return BackendConfig(
          backend: TestBackend.postgres,
          endpoint: Endpoint(
            host: host,
            port: port,
            database: database,
            username: username,
            password: password,
          ),
          enableMigrations: enableMigrations,
          sslMode: sslMode,
        );
      case 'sqlite':
      default:
        return const BackendConfig(
          backend: TestBackend.sqlite,
          enableMigrations: true,
        );
    }
  }

  static String _pg(String suffix) => 'DRIFT_CRDT_PG_$suffix';
}

SslMode _parseSslMode(String? raw) {
  final normalized = raw?.toLowerCase();
  switch (normalized) {
    case null:
    case '':
    case 'disable':
      return SslMode.disable;
    case 'require':
      return SslMode.require;
    case 'verifyfull':
    case 'verify_full':
    case 'verify-full':
      return SslMode.verifyFull;
    default:
      return SslMode.disable;
  }
}

BackendConfig? _cachedConfig;

BackendConfig get backendConfig =>
    _cachedConfig ??= BackendConfig.fromEnvironment();

Future<void> configureBackendForPlatform() async {
  if (backendConfig.isSqlite &&
      (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    databaseFactory = databaseFactoryFfi;
    final dbDir =
        Directory(p.join('.dart_tool', 'sqflite_common_ffi', 'databases'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
  }
}

CrdtQueryExecutor createExecutor({
  bool inMemory = false,
  String sqliteDbName = 'app.db',
  bool singleInstance = true,
  DatabaseCreator? sqliteCreator,
}) {
  final config = backendConfig;
  if (config.isSqlite) {
    if (inMemory) {
      return CrdtQueryExecutor.inMemory(
        singleInstance: singleInstance,
        creator: sqliteCreator,
      );
    }
    return CrdtQueryExecutor.inDatabaseFolder(
      path: sqliteDbName,
      singleInstance: singleInstance,
      creator: sqliteCreator,
    );
  }

  final endpoint = config.endpoint!;
  return CrdtQueryExecutor.postgres(
    endpoint: endpoint,
    settings: ConnectionSettings(sslMode: config.sslMode),
    enableMigrations: config.enableMigrations,
    logStatements: false,
  );
}

Future<void> clearBackend({required String sqliteDbName}) async {
  final config = backendConfig;
  if (config.isSqlite) {
    final folder = await getDatabasesPath();
    final dir = Directory(folder);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(folder, sqliteDbName));
    if (await file.exists()) {
      await file.delete();
    }
    return;
  }

  final endpoint = config.endpoint!;
  final connection = await Connection.open(
    endpoint,
    settings: ConnectionSettings(sslMode: config.sslMode),
  );
  try {
    await connection.execute(Sql('DROP SCHEMA IF EXISTS public CASCADE'));
    await connection.execute(Sql('CREATE SCHEMA public'));
    // Ensure the search_path still points to the recreated schema.
    await connection.execute(Sql('SET search_path TO public'));
  } finally {
    await connection.close();
  }
}

String _escapeIdentifier(String identifier) => identifier.replaceAll('"', '""');
