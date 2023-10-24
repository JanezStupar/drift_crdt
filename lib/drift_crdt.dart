/// Flutter implementation for the drift database packages.
///
/// The [CrdtQueryExecutor] class can be used as a drift database
/// implementation based on the `sqflite` package.
library drift_crdt;

import 'dart:async';
import 'dart:io';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqlite_crdt/sqlite_crdt.dart';

/// Signature of a function that runs when a database doesn't exist on file.
/// This can be useful to, for instance, load the database from an asset if it
/// doesn't exist.
typedef DatabaseCreator = FutureOr<void> Function(File file);
typedef Query = (String sql, List<Object?> args);

class SqliteTransactionCrdt {
  final TransactionCrdt txn;

  SqliteTransactionCrdt(this.txn);

  Future<void> execute(String sql, [List<Object?>? args]) async {
    await txn.execute(sql, args);
  }

  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) {
    return txn.rawQuery(sql, arguments);
  }

  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) {
    return txn.rawUpdate(sql, arguments);
  }

  Future<int> rawInsert(String sql, [List<Object?>? arguments]) {
    return txn.rawInsert(sql, arguments);
  }
}

class _CrdtQueryDelegate extends QueryDelegate {
  late final SqliteTransactionCrdt _transactionCrdt;

  _CrdtQueryDelegate(this._transactionCrdt);

  @override
  Future<void> runCustom(String statement, List<Object?> args) {
    return _transactionCrdt.execute(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) {
    return _transactionCrdt.rawInsert(statement, args);
  }

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async {
    final result = await _transactionCrdt.rawQuery(statement, args);
    return QueryResult.fromRows(result);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    return _transactionCrdt.rawUpdate(statement, args);
  }
}

class _CrdtTransactionDelegate extends SupportedTransactionDelegate {
  final _CrdtDelegate api;

  _CrdtTransactionDelegate(this.api);

  @override
  FutureOr<void> startTransaction(Future Function(QueryDelegate) run) {
    return api.sqliteCrdt.transaction((txn) async {
      return run(_CrdtQueryDelegate(SqliteTransactionCrdt(txn)));
    });
  }

  Future<void> runBatched(BatchedStatements statements) async {
    final batch = api.sqliteCrdt.batch();

    for (final arg in statements.arguments) {
      batch.execute(statements.statements[arg.statementIndex], arg.arguments);
    }

    await batch.apply(noResult: true);
  }
}

class _CrdtDelegate extends DatabaseDelegate {
  late SqliteCrdt sqliteCrdt;
  bool _isOpen = false;

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
    return _transactionDelegate ??= _CrdtTransactionDelegate(this);
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

    // default value when no migration happened
    sqliteCrdt = await SqliteCrdt.open(
      resolvedPath,
      singleInstance: singleInstance,
      migrate: migrate,
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
      batch.execute(statements.statements[arg.statementIndex], arg.arguments);
    }

    await batch.apply(noResult: true);
  }

  @override
  Future<void> runCustom(String statement, List<Object?> args) {
    return sqliteCrdt.execute(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) {
    return sqliteCrdt.rawInsert(statement, args);
  }

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async {
    final result = await sqliteCrdt.rawQuery(statement, args);
    return QueryResult.fromRows(result);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    return sqliteCrdt.rawUpdate(statement, args);
  }
}

class _CrdtVersionDelegate extends DynamicVersionDelegate {
  final SqliteCrdt _db;

  _CrdtVersionDelegate(this._db);

  @override
  Future<int> get schemaVersion async {
    final result = await _db.rawQuery('PRAGMA user_version;');
    return result.single.values.first as int;
  }

  @override
  Future<void> setSchemaVersion(int version) async {
    await _db.execute('PRAGMA user_version = $version;');
  }
}

/// A query executor that uses sqflite internally.
class CrdtQueryExecutor extends DelegatedDatabase {
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
      : super(
            _CrdtDelegate(false, path,
                singleInstance: singleInstance,
                creator: creator,
                migrate: migrate),
            logStatements: logStatements);

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
      : super(
            _CrdtDelegate(true, path,
                singleInstance: singleInstance,
                creator: creator,
                migrate: migrate),
            logStatements: logStatements);

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
    final crdtDelegate = delegate as _CrdtDelegate;
    return crdtDelegate.isOpen ? crdtDelegate.sqliteCrdt : null;
  }

  @override
  // We're not really required to be sequential since sqflite has an internal
  // lock to bring statements into a sequential order.
  // Setting isSequential here helps with cancellations in stream queries
  // though.
  bool get isSequential => true;

  /// Returns the last modified timestamp of the database.
  Future<Hlc?> getLastModified(
      {String? onlyNodeId, String? exceptNodeId}) async {
    final crdtDelegate = delegate as _CrdtDelegate;
    return crdtDelegate.sqliteCrdt
        .getLastModified(onlyNodeId: onlyNodeId, exceptNodeId: exceptNodeId);
  }

  Future<CrdtChangeset> getChangeset({
    Map<String, Query>? customQueries,
    Iterable<String>? onlyTables,
    String? onlyNodeId,
    String? exceptNodeId,
    Hlc? modifiedOn,
    Hlc? modifiedAfter,
  }) async {
    final crdtDelegate = delegate as _CrdtDelegate;
    return crdtDelegate.sqliteCrdt.getChangeset(
        customQueries: customQueries,
        onlyTables: onlyTables,
        exceptNodeId: exceptNodeId,
        modifiedOn: modifiedOn,
        modifiedAfter: modifiedAfter);
  }

  Future<void> merge(CrdtChangeset changeset) async {
    final crdtDelegate = delegate as _CrdtDelegate;
    return crdtDelegate.sqliteCrdt.merge(changeset);
  }
}
