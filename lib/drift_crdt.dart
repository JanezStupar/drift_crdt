/// Flutter implementation for the drift database packages.
///
/// The [CrdtQueryExecutor] class can be used as a drift database
/// implementation based on the `sqflite` package.
library drift_crdt;

import 'dart:async';
import 'dart:io';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart';
import 'package:drift_crdt/utils.dart';
import 'package:path/path.dart';
import 'package:postgres/postgres.dart' show Endpoint, ConnectionSettings;
import 'package:postgres_crdt/postgres_crdt.dart' as postgres_crdt;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sql_crdt/sql_crdt.dart' as sql_crdt;
import 'package:sqlite_crdt/sqlite_crdt.dart' as sqlite_crdt;
import 'package:sqlparser/sqlparser.dart' as sqlparser;
import 'package:sqlparser/utils/node_to_text.dart';

export 'package:postgres/postgres.dart'
    show Endpoint, ConnectionSettings, SslMode;
export 'package:sqlite_crdt/sqlite_crdt.dart'
    show Hlc, CrdtChangeset, parseCrdtChangeset, CrdtTableChangeset;

const _crdtDeletedOn = 'CRDT QUERY DELETED ON';
const _crdtDeletedOff = 'CRDT QUERY DELETED OFF';

/// Signature of a function that runs when a database doesn't exist on file.
/// This can be useful to, for instance, load the database from an asset if it
/// doesn't exist.
typedef DatabaseCreator = FutureOr<void> Function(File file);
typedef Query = (String sql, List<Object?> args);

typedef ExecuteResult = sql_crdt.ExecuteResult;
typedef VoidResult = sql_crdt.VoidResult;
typedef SqlCrdtQueryResult = sql_crdt.QueryResult;
typedef SqlCrdt = sql_crdt.SqlCrdt;
typedef CrdtExecutor = sql_crdt.CrdtExecutor;
typedef DatabaseApi = sql_crdt.DatabaseApi;
typedef ReadWriteApi = sql_crdt.ReadWriteApi;
typedef WriteApi = sql_crdt.WriteApi;
typedef ReadApi = sql_crdt.ReadApi;
typedef SqliteCrdt = sqlite_crdt.SqliteCrdt;
typedef PostgresCrdt = postgres_crdt.PostgresCrdt;
typedef Hlc = sql_crdt.Hlc;
typedef CrdtChangeset = sql_crdt.CrdtChangeset;
typedef CrdtTableChangeset = sql_crdt.CrdtTableChangeset;

/// Converts a CRDT execute response into a Drift-style [QueryResult] so callers
/// can transparently consume rows emitted by `RETURNING` clauses.
QueryResult _queryResultFromExecute(ExecuteResult result) {
  if (result case SqlCrdtQueryResult(:final rows)) {
    final castRows = [
      for (final row in rows) Map<String, dynamic>.from(row),
    ];
    return QueryResult.fromRows(castRows);
  }

  return QueryResult(const [], const []);
}

/// Detects whether a parsed statement includes a `RETURNING` clause so that we
/// can request row results instead of void results from the CRDT executor.
bool _hasReturningClause(sqlparser.Statement statement) {
  return switch (statement) {
    sqlparser.InsertStatement(:final returning) => returning != null,
    sqlparser.UpdateStatement(:final returning) => returning != null,
    sqlparser.DeleteStatement(:final returning) => returning != null,
    _ => false,
  };
}

/// Shared interface used by both SQLite and Postgres transactions to surface
/// the handful of operations Drift expects (execute/query/update/insert).
abstract class _TransactionCrdt {
  Future<ExecuteResult> execute(String sql, [List<Object?>? args]);

  Future<List<Map<String, Object?>>> query(String sql,
      [List<Object?>? arguments]);

  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]);

  Future<int> rawUpdate(String sql, [List<Object?>? arguments]);

  Future<int> rawInsert(String sql, [List<Object?>? arguments]);
}

/// Wraps a sqflite-backed CRDT transaction so Drift's transaction delegate can
/// call through without knowing about the underlying CRDT API.
class SqliteTransactionCrdt implements _TransactionCrdt {
  final CrdtExecutor txn;

  SqliteTransactionCrdt(this.txn);

  @override
  Future<ExecuteResult> execute(String sql, [List<Object?>? args]) {
    if (sql.contains('CREATE TABLE')) {
      sql = DriftCrdtUtils.prepareCreateTableQuery(sql);
    }
    return txn.execute(sql, args);
  }

  @override
  Future<List<Map<String, Object?>>> query(String sql,
      [List<Object?>? arguments]) {
    return txn.query(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) {
    return txn.query(sql, arguments);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    await txn.execute(sql, arguments);
    return txn.query('SELECT changes()').then((List result) => result.length);
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    await txn.execute(sql, arguments);
    return txn
        .query('SELECT last_insert_rowid()')
        .then((List result) => result.first.values.first);
  }
}

/// Mirrors [SqliteTransactionCrdt] for Postgres, translating CRDT responses
/// into the minimal information Drift needs (e.g. fake row counts).
class PostgresTransactionCrdt implements _TransactionCrdt {
  final CrdtExecutor txn;

  PostgresTransactionCrdt(this.txn);

  @override
  Future<ExecuteResult> execute(String sql, [List<Object?>? args]) {
    if (sql.contains('CREATE TABLE')) {
      sql = DriftCrdtUtils.prepareCreateTableQuery(sql);
    }
    return txn.execute(sql, args);
  }

  @override
  Future<List<Map<String, Object?>>> query(String sql,
      [List<Object?>? arguments]) {
    return txn.query(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) {
    return txn.query(sql, arguments);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    await txn.execute(sql, arguments);
    // PostgreSQL doesn't have changes() function
    // The postgres_crdt library handles this internally
    return 1; // Return success indicator
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    final result = await txn.execute(sql, arguments);
    // For RETURNING clause support
    if (result is SqlCrdtQueryResult && result.rows.isNotEmpty) {
      final row = result.rows.first;
      if (row.containsKey('id')) {
        return row['id'] as int;
      }
    }
    return 1; // Default success indicator
  }
}

/// Query delegate that routes Drift query callbacks through the active CRDT
/// transaction, applying SQL parser transforms when necessary.
class _CrdtQueryDelegate extends QueryDelegate {
  late final _TransactionCrdt _transactionCrdt;
  final bool _queryDeleted;

  _CrdtQueryDelegate(this._transactionCrdt, this._queryDeleted);

  @override
  Future<void> runCustom(String statement, List<Object?> args) async {
    if (statement.contains('CREATE TABLE')) {
      statement = DriftCrdtUtils.prepareCreateTableQuery(statement);
    }
    await _transactionCrdt.execute(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) {
    return _transactionCrdt.rawInsert(statement, args);
  }

  @override
  Future<QueryResult> runSelect(String sql, List<Object?> args) async {
    final hasPostgresPlaceholders = RegExp(r'\$\d+').hasMatch(sql);

    final sqlForParsing = hasPostgresPlaceholders
        ? sql.replaceAllMapped(
            RegExp(r'\$(\d+)'),
            (match) => '?${match.group(1)}',
          )
        : sql;

    final parser = sqlparser.SqlEngine();
    final parsed = parser.parse(sqlForParsing);
    final statement = parsed.rootNode as sqlparser.Statement;

    if (statement is sqlparser.InvalidStatement) {
      final result = await _transactionCrdt.query(sql, args);
      return QueryResult.fromRows(result);
    }

    if (_hasReturningClause(statement)) {
      final result = await _transactionCrdt.execute(sql, args);
      return _queryResultFromExecute(result);
    }

    if (!DriftCrdtUtils.isSpecialQuery(parsed) &&
        statement is sqlparser.SelectStatement) {
      DriftCrdtUtils.prepareSelectStatement(statement, _queryDeleted);

      DriftCrdtUtils.transformAutomaticExplicit(statement);

      var transformedSql = DriftCrdtUtils.buildPostgresSql(parsed, statement);

      if (hasPostgresPlaceholders) {
        transformedSql = transformedSql.replaceAllMapped(
          RegExp(r'\?(\d+)'),
          (match) => '\$${match.group(1)}',
        );
      }

      sql = transformedSql;
    }

    final result = await _transactionCrdt.query(sql, args);
    return QueryResult.fromRows(result);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    return _transactionCrdt.rawUpdate(statement, args);
  }
}

/// Transaction delegate for SQLite-backed CRDT databases.
class _CrdtTransactionDelegate extends SupportedTransactionDelegate {
  final _CrdtDelegate api;
  bool queryDeleted = false;

  _CrdtTransactionDelegate(this.api);

  @override
  FutureOr<void> startTransaction(Future Function(QueryDelegate) run) {
    return api.sqliteCrdt.transaction((txn) async {
      return run(_CrdtQueryDelegate(SqliteTransactionCrdt(txn), queryDeleted));
    });
  }

  Future<void> runBatched(BatchedStatements statements) async {
    final batch = api.sqliteCrdt.batch();

    for (final arg in statements.arguments) {
      var statement = statements.statements[arg.statementIndex];
      if (statement.contains('CREATE TABLE')) {
        statement = DriftCrdtUtils.prepareCreateTableQuery(statement);
      }
      batch.execute(statement, arg.arguments);
    }

    await batch.commit();
  }
}

/// Transaction delegate for Postgres-backed CRDT databases.
class _PostgresCrdtTransactionDelegate extends SupportedTransactionDelegate {
  final _PostgresCrdtDelegate api;
  bool queryDeleted = false;

  _PostgresCrdtTransactionDelegate(this.api);

  @override
  FutureOr<void> startTransaction(Future Function(QueryDelegate) run) {
    return api.postgresCrdt.transaction((txn) async {
      return run(
          _CrdtQueryDelegate(PostgresTransactionCrdt(txn), queryDeleted));
    });
  }

  Future<void> runBatched(BatchedStatements statements) async {
    // PostgreSQL CRDT doesn't support batch() - execute statements sequentially in a transaction
    await api.postgresCrdt.transaction((txn) async {
      for (final arg in statements.arguments) {
        var statement = statements.statements[arg.statementIndex];
        if (statement.contains('CREATE TABLE')) {
          statement = DriftCrdtUtils.prepareCreateTableQuery(statement);
        }
        await txn.execute(statement, arg.arguments);
      }
    });
  }
}

// TODO: Sort out migration
class _CrdtDelegateInMemory extends _CrdtDelegate {
  _CrdtDelegateInMemory({singleInstance = true, migrate = false, creator})
      : super(false, '',
            singleInstance: singleInstance, migrate: migrate, creator: creator);

  @override
  Future<void> open(QueryExecutorUser user) async {
    sqliteCrdt = await SqliteCrdt.openInMemory(
      singleInstance: singleInstance,
    );
    _transactionDelegate = _CrdtTransactionDelegate(this);
    _isOpen = true;
  }
}

class _CrdtDelegate extends DatabaseDelegate {
  late SqliteCrdt sqliteCrdt;
  bool _isOpen = false;
  bool _queryDeleted = false;

  final bool inDbFolder;
  final String path;
  final bool migrate;

  bool singleInstance;
  final DatabaseCreator? creator;

  late _CrdtTransactionDelegate? _transactionDelegate;

  _CrdtDelegate(this.inDbFolder, this.path,
      {this.singleInstance = true, this.creator, this.migrate = false});

  @override
  late final DbVersionDelegate versionDelegate =
      _CrdtVersionDelegate(sqliteCrdt);

  @override
  TransactionDelegate get transactionDelegate {
    final delegate = _transactionDelegate ??= _CrdtTransactionDelegate(this);
    delegate.queryDeleted = _queryDeleted;
    return delegate;
  }

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> open(QueryExecutorUser user) async {
    String resolvedPath;
    if (inDbFolder) {
      resolvedPath = join(await sqflite.getDatabasesPath(), path);
    } else {
      resolvedPath = path;
    }

    final file = File(resolvedPath);
    if (creator != null && !await file.exists()) {
      if (!Directory(dirname(resolvedPath)).existsSync()) {
        await Directory(dirname(resolvedPath)).create(recursive: true);
      }
      await creator!(file);
    }

    // TODO: Sort out migration
    // default value when no migration happened
    sqliteCrdt = await SqliteCrdt.open(
      resolvedPath,
      singleInstance: singleInstance,
      // migrate: migrate,
    );
    _transactionDelegate = _CrdtTransactionDelegate(this);
    _isOpen = true;
  }

  Future<void> openInMemory(QueryExecutorUser user) async {
    // default value when no migration happened
    sqliteCrdt = await SqliteCrdt.openInMemory(
      singleInstance: singleInstance,
      // migrate: migrate,
    );
    _transactionDelegate = _CrdtTransactionDelegate(this);
    _isOpen = true;
  }

  @override
  Future<void> close() {
    return sqliteCrdt.close();
  }

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    final batch = sqliteCrdt.batch();

    for (final arg in statements.arguments) {
      var statement = statements.statements[arg.statementIndex];
      if (statement.contains('CREATE TABLE')) {
        statement = DriftCrdtUtils.prepareCreateTableQuery(statement);
      }
      batch.execute(statement, arg.arguments);
    }

    await batch.commit();
  }

  @override
  Future<void> runCustom(String statement, List<Object?> args) async {
    switch (statement) {
      case _crdtDeletedOn:
        _queryDeleted = true;
        break;
      case _crdtDeletedOff:
        _queryDeleted = false;
        break;
      default:
        if (statement.contains('CREATE TABLE')) {
          statement = DriftCrdtUtils.prepareCreateTableQuery(statement);
        }
        await sqliteCrdt.execute(statement, args);
    }
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    await sqliteCrdt.execute(statement, args);
    return sqliteCrdt
        .query('SELECT last_insert_rowid()')
        .then((List result) => result.first.values.first);
  }

  @override
  Future<QueryResult> runSelect(String sql, List<Object?> args) async {
    sqlparser.SqlEngine parser = sqlparser.SqlEngine();
    final parsed = parser.parse(sql);
    sqlparser.Statement statement = parsed.rootNode as sqlparser.Statement;

    if (_hasReturningClause(statement)) {
      final result = await sqliteCrdt.execute(sql, args);
      return _queryResultFromExecute(result);
    }

    if (!DriftCrdtUtils.isSpecialQuery(parsed) &&
        statement is sqlparser.SelectStatement) {
      DriftCrdtUtils.prepareSelectStatement(statement, _queryDeleted);
      sql = (statement).toSql();
    }
    final result = await sqliteCrdt.query(sql, args);
    return QueryResult.fromRows(result);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    await sqliteCrdt.execute(statement, args);
    return sqliteCrdt
        .query('SELECT changes()')
        .then((List result) => result.length);
  }
}

/// Database delegate that proxies Drift calls into `postgres_crdt`.
class _PostgresCrdtDelegate extends DatabaseDelegate {
  late PostgresCrdt postgresCrdt;
  bool _isOpen = false;
  bool _queryDeleted = false;

  final Endpoint endpoint;
  final ConnectionSettings? settings;
  final bool enableMigrations;

  late _PostgresCrdtTransactionDelegate? _transactionDelegate;

  _PostgresCrdtDelegate({
    required this.endpoint,
    this.settings,
    this.enableMigrations = true,
  });

  @override
  late final DbVersionDelegate versionDelegate =
      _PostgresCrdtVersionDelegate(postgresCrdt);

  @override
  TransactionDelegate get transactionDelegate {
    final delegate =
        _transactionDelegate ??= _PostgresCrdtTransactionDelegate(this);
    delegate.queryDeleted = _queryDeleted;
    return delegate;
  }

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> open(QueryExecutorUser user) async {
    postgresCrdt = await PostgresCrdt.open(
      endpoint.database,
      host: endpoint.host,
      port: endpoint.port,
      username: endpoint.username,
      password: endpoint.password,
      sslMode: settings?.sslMode,
    );
    _transactionDelegate = _PostgresCrdtTransactionDelegate(this);
    _isOpen = true;
  }

  @override
  Future<void> close() {
    return postgresCrdt.close();
  }

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    // PostgreSQL CRDT doesn't support batch() - execute statements sequentially in a transaction
    await postgresCrdt.transaction((txn) async {
      for (final arg in statements.arguments) {
        var statement = statements.statements[arg.statementIndex];
        if (statement.contains('CREATE TABLE')) {
          statement = DriftCrdtUtils.prepareCreateTableQuery(statement);
        }
        await txn.execute(statement, arg.arguments);
      }
    });
  }

  @override
  Future<void> runCustom(String statement, List<Object?> args) async {
    switch (statement) {
      case _crdtDeletedOn:
        _queryDeleted = true;
        break;
      case _crdtDeletedOff:
        _queryDeleted = false;
        break;
      default:
        if (statement.contains('CREATE TABLE')) {
          statement = DriftCrdtUtils.prepareCreateTableQuery(statement);
        }
        await postgresCrdt.execute(statement, args);
    }
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    // Execute the INSERT statement through CRDT
    // Drift's query generator already adds RETURNING clauses when needed
    final result = await postgresCrdt.execute(statement, args);

    // If we have results (from RETURNING clause), return the first column
    if (result is SqlCrdtQueryResult && result.rows.isNotEmpty) {
      final row = result.rows.first;
      final firstValue = row.values.firstOrNull;
      if (firstValue is int) {
        return firstValue;
      }
    }

    // Return 0 to indicate success but no ID (for tables without auto-increment)
    return 0;
  }

  @override
  Future<QueryResult> runSelect(String sql, List<Object?> args) async {
    final hasPostgresPlaceholders = RegExp(r'\$\d+').hasMatch(sql);
    final sqlForParsing = hasPostgresPlaceholders
        ? sql.replaceAllMapped(
            RegExp(r'\$(\d+)'),
            (match) => '?${match.group(1)}',
          )
        : sql;

    final parser = sqlparser.SqlEngine();
    final parsed = parser.parse(sqlForParsing);
    final statement = parsed.rootNode as sqlparser.Statement;

    if (statement is sqlparser.InvalidStatement) {
      final result = await postgresCrdt.query(sql, args);
      return QueryResult.fromRows(result);
    }

    if (_hasReturningClause(statement)) {
      final result = await postgresCrdt.execute(sql, args);
      return _queryResultFromExecute(result);
    }

    if (!DriftCrdtUtils.isSpecialQuery(parsed) &&
        statement is sqlparser.SelectStatement) {
      DriftCrdtUtils.prepareSelectStatement(statement, _queryDeleted);

      DriftCrdtUtils.transformAutomaticExplicit(statement);

      var transformedSql = DriftCrdtUtils.buildPostgresSql(parsed, statement);

      if (hasPostgresPlaceholders) {
        transformedSql = transformedSql.replaceAllMapped(
          RegExp(r'\?(\d+)'),
          (match) => '\$${match.group(1)}',
        );
      }

      sql = transformedSql;
    }

    final result = await postgresCrdt.query(sql, args);
    return QueryResult.fromRows(result);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    await postgresCrdt.execute(statement, args);
    // PostgreSQL doesn't have changes() function
    // Return success indicator (postgres_crdt handles actual counts internally)
    return 1;
  }
}

class _CrdtVersionDelegate extends DynamicVersionDelegate {
  final SqliteCrdt _db;

  _CrdtVersionDelegate(this._db);

  @override
  Future<int> get schemaVersion async {
    final result = await _db.query('PRAGMA user_version;');
    return result.single.values.first as int;
  }

  @override
  Future<void> setSchemaVersion(int version) async {
    await _db.execute('PRAGMA user_version = $version;');
  }
}

class _PostgresCrdtVersionDelegate extends DynamicVersionDelegate {
  final PostgresCrdt _db;

  _PostgresCrdtVersionDelegate(this._db);

  @override
  Future<int> get schemaVersion async {
    // PostgreSQL migrations are not supported by drift.
    // Schema versioning should be handled externally using migration tools
    // like dbmate, flyway, or liquibase.
    // Always return 0 to indicate that drift should not manage migrations.
    return 0;
  }

  @override
  Future<void> setSchemaVersion(int version) async {
    // PostgreSQL migrations are not supported by drift.
    // Schema versioning should be handled externally.
    // This is a no-op to prevent drift from trying to manage schema versions.
  }
}

extension on BigInt {
  static final _minValue = BigInt.parse('-9223372036854775808');
  static final _maxValue = BigInt.parse('9223372036854775807');

  int rangeCheckedToInt() {
    if (this < _minValue || this > _maxValue) {
      throw ArgumentError.value(
        this,
        'this',
        'Should be in signed 64bit range ($_minValue..=$_maxValue)',
      );
    }

    return toInt();
  }
}

/// A query executor that uses sqflite internally.
class CrdtQueryExecutor extends DelegatedDatabase {
  final SqlDialect _dialect;

  /// A query executor that will store the database in the file declared by
  /// [path]. If [logStatements] is true, statements sent to the database will
  /// be [print]ed, which can be handy for debugging. The [singleInstance]
  /// parameter sets the corresponding parameter on [s.openDatabase].
  /// The [creator] will be called when the database file doesn't exist. It can
  /// be used to, for instance, populate default data from an asset. Note that
  /// migrations might behave differently when populating the database this way.
  /// For instance, a database created by an [creator] will not receive the
  /// [MigrationStrategy.onCreate] callback because it hasn't been created by
  /// drift.
  CrdtQueryExecutor(
      {required String path,
      bool? logStatements,
      bool singleInstance = true,
      DatabaseCreator? creator,
      bool migrate = false})
      : _dialect = SqlDialect.sqlite,
        super(
            _CrdtDelegate(false, path,
                singleInstance: singleInstance,
                creator: creator,
                migrate: migrate),
            logStatements: logStatements,
            isSequential: true);

  CrdtQueryExecutor.inMemory(
      {bool? logStatements,
      bool singleInstance = true,
      DatabaseCreator? creator,
      bool migrate = false})
      : _dialect = SqlDialect.sqlite,
        super(
            _CrdtDelegateInMemory(
                singleInstance: singleInstance,
                creator: creator,
                migrate: migrate),
            logStatements: logStatements,
            isSequential: true);

  /// A query executor that will store the database in the file declared by
  /// [path], which will be resolved relative to [s.getDatabasesPath()].
  /// If [logStatements] is true, statements sent to the database will
  /// be [print]ed, which can be handy for debugging. The [singleInstance]
  /// parameter sets the corresponding parameter on [s.openDatabase].
  /// The [creator] will be called when the database file doesn't exist. It can
  /// be used to, for instance, populate default data from an asset. Note that
  /// migrations might behave differently when populating the database this way.
  /// For instance, a database created by an [creator] will not receive the
  /// [MigrationStrategy.onCreate] callback because it hasn't been created by
  /// drift.
  CrdtQueryExecutor.inDatabaseFolder(
      {required String path,
      bool? logStatements,
      bool singleInstance = true,
      DatabaseCreator? creator,
      bool migrate = false})
      : _dialect = SqlDialect.sqlite,
        super(
            _CrdtDelegate(true, path,
                singleInstance: singleInstance,
                creator: creator,
                migrate: migrate),
            logStatements: logStatements,
            isSequential: true);

  /// A query executor that uses PostgreSQL with CRDT functionality.
  ///
  /// Connect to a PostgreSQL database with CRDT support using the provided
  /// [endpoint]. The [settings] parameter can be used to configure SSL and
  /// other connection options.
  ///
  /// Set [enableMigrations] to false if you're managing schema migrations
  /// externally. When true (default), drift will manage migrations through
  /// the __schema table.
  ///
  /// If [logStatements] is true, statements sent to the database will
  /// be printed, which can be handy for debugging.
  CrdtQueryExecutor.postgres({
    required Endpoint endpoint,
    ConnectionSettings? settings,
    bool enableMigrations = true,
    bool? logStatements,
  })  : _dialect = SqlDialect.postgres,
        super(
          _PostgresCrdtDelegate(
            endpoint: endpoint,
            settings: settings,
            enableMigrations: enableMigrations,
          ),
          logStatements: logStatements,
          isSequential: false, // PostgreSQL supports concurrent operations
        );

  @override
  SqlDialect get dialect => _dialect;

  /// The underlying sqflite [s.Database] object used by drift to send queries.
  ///
  /// Using the sqflite database can cause unexpected behavior in drift. For
  /// instance, stream queries won't update for updates sent to the [s.Database]
  /// directly. Further, drift assumes full control over the database for its
  /// internal connection management.
  /// For this reason, projects shouldn't use this getter unless they absolutely
  /// need to. The database is exposed to make migrating from sqflite to drift
  /// easier.
  ///
  /// Note that this returns null until the drift database has been opened.
  /// A drift database is opened lazily when the first query runs.
  SqliteCrdt? get sqfliteDb {
    final currentDelegate = delegate;
    if (currentDelegate is _CrdtDelegate && currentDelegate.isOpen) {
      return currentDelegate.sqliteCrdt;
    }
    return null;
  }

  /// Resolves the concrete CRDT implementation used by the current delegate.
  SqlCrdt get _sqlCrdt {
    final currentDelegate = delegate;
    if (currentDelegate is _CrdtDelegate) {
      return currentDelegate.sqliteCrdt;
    } else if (currentDelegate is _PostgresCrdtDelegate) {
      return currentDelegate.postgresCrdt;
    }

    throw StateError(
        'Unsupported delegate ${currentDelegate.runtimeType} for CrdtQueryExecutor.');
  }

  /// Returns the last modified timestamp of the database.
  ///  [onlyNodeId] only return the last modified timestamp of the given node
  ///  [exceptNodeId] do not return the last modified timestamp of the given node
  Future<Hlc?> getLastModified(
      {String? onlyNodeId, String? exceptNodeId}) async {
    final crdt = _sqlCrdt;
    return crdt.getLastModified(
        onlyNodeId: onlyNodeId, exceptNodeId: exceptNodeId);
  }

  /// Returns the database changeset according to the given parameters.
  /// [customQueries] can be used to add custom queries to the changeset.
  /// [onlyTables] only return changes for the given tables
  /// [onlyNodeId] only return changes for the given node
  /// [exceptNodeId] do not return changes for the given node
  /// [modifiedOn] only return changes that were modified on the given timestamp
  /// [modifiedAfter] only return changes that were modified after the given timestamp
  /// When [customQueries] is omitted, each generated query orders rows by the
  /// table's primary key to ensure deterministic changesets.
  Future<CrdtChangeset> getChangeset({
    Map<String, Query>? customQueries,
    Iterable<String>? onlyTables,
    String? onlyNodeId,
    String? exceptNodeId,
    Hlc? modifiedOn,
    Hlc? modifiedAfter,
  }) async {
    final crdt = _sqlCrdt;
    var effectiveQueries = customQueries;

    if (effectiveQueries == null) {
      final tables = onlyTables != null
          ? onlyTables.toList()
          : (await crdt.getTables()).toList();

      final queries = <String, Query>{};
      for (final table in tables) {
        final orderBy = await _orderByPrimaryKeys(crdt, table);
        queries[table] = (
          'SELECT * FROM $table$orderBy',
          const <Object?>[]
        );
      }
      effectiveQueries = queries;
    }

    return crdt.getChangeset(
        customQueries: effectiveQueries,
        onlyTables: onlyTables,
        onlyNodeId: onlyNodeId,
        exceptNodeId: exceptNodeId,
        modifiedOn: modifiedOn,
        modifiedAfter: modifiedAfter);
  }

  /// merges the provided changeset with the database
  Future<void> merge(CrdtChangeset changeset) async {
    final crdt = _sqlCrdt;
    return crdt.merge(changeset);
  }

  /// Builds an ORDER BY clause for the table's primary key columns.
  /// Returns an empty string when the table exposes no primary key metadata.
  Future<String> _orderByPrimaryKeys(SqlCrdt crdt, String table) async {
    final keys = (await crdt.getTableKeys(table)).toList();
    if (keys.isEmpty) {
      return '';
    }
    final orderColumns = keys.join(', ');
    return ' ORDER BY $orderColumns';
  }
}

typedef DelegateCallback<R> = Future<R> Function();

/// Allows access to the deleted records using the Drift API
/// [db] the database executor to query
/// callback the callback to execute, works with transactions too.
Future<R> queryDeleted<T, R>(T db, DelegateCallback<R> callback) async {
  if (db is QueryExecutor) {
    if (db is CrdtQueryExecutor) {
      await db.runCustom(_crdtDeletedOn);
      final result = await callback();
      await db.runCustom(_crdtDeletedOff);
      return result;
    } else {
      // queryDeleted is a noop for non CrdtQueryExecutor
      return await callback();
    }
  } else {
    throw "Database executor is null";
  }
}
