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
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'package:sqlparser/sqlparser.dart';
import 'package:sqlparser/utils/node_to_text.dart';

export 'package:sqlite_crdt/sqlite_crdt.dart'
    show Hlc, CrdtChangeset, parseCrdtChangeset, CrdtTableChangeset;

const _crdtDeletedOn = 'CRDT QUERY DELETED ON';
const _crdtDeletedOff = 'CRDT QUERY DELETED OFF';

/// Signature of a function that runs when a database doesn't exist on file.
/// This can be useful to, for instance, load the database from an asset if it
/// doesn't exist.
typedef DatabaseCreator = FutureOr<void> Function(File file);
typedef Query = (String sql, List<Object?> args);

class SqliteTransactionCrdt {
  final CrdtExecutor txn;

  SqliteTransactionCrdt(this.txn);

  Future<void> execute(String sql, [List<Object?>? args]) async {
    await txn.execute(sql, args);
  }

  Future<List<Map<String, Object?>>> query(String sql,
      [List<Object?>? arguments]) {
    return txn.query(sql, arguments);
  }

  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) {
    return txn.query(sql, arguments);
  }

  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    await txn.execute(sql, arguments);
    return txn.query('SELECT changes()').then((List result) => result.length);
  }

  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    await txn.execute(sql, arguments);
    return txn
        .query('SELECT last_insert_rowid()')
        .then((List result) => result.first.values.first);
  }
}

class _CrdtQueryDelegate extends QueryDelegate {
  late final SqliteTransactionCrdt _transactionCrdt;
  final bool _queryDeleted;

  _CrdtQueryDelegate(this._transactionCrdt, this._queryDeleted);

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
    SqlEngine parser = SqlEngine();
    Statement parsed = (parser.parse(statement).rootNode) as Statement;
    if (parsed is SelectStatement) {
      DriftCrdtUtils.prepareSelectStatement(parsed, _queryDeleted);
      statement = parsed.toSql();
    }
    final result = await _transactionCrdt.query(statement, args);
    return QueryResult.fromRows(result);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    return _transactionCrdt.rawUpdate(statement, args);
  }
}

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
      batch.execute(statements.statements[arg.statementIndex], arg.arguments);
    }

    await batch.commit();
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
      batch.execute(statements.statements[arg.statementIndex], arg.arguments);
    }

    await batch.commit();
  }

  @override
  Future<void> runCustom(String statement, List<Object?> args) {
    switch (statement) {
      case _crdtDeletedOn:
        _queryDeleted = true;
        break;
      case _crdtDeletedOff:
        _queryDeleted = false;
        break;
      default:
        return sqliteCrdt.execute(statement, args);
    }
    return Future.value();
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    await sqliteCrdt.execute(statement, args);
    return sqliteCrdt
        .query('SELECT last_insert_rowid()')
        .then((List result) => result.first.values.first);
  }

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async {
    SqlEngine parser = SqlEngine();
    Statement parsed = (parser.parse(statement).rootNode) as Statement;
    if (parsed is SelectStatement) {
      DriftCrdtUtils.prepareSelectStatement(parsed, _queryDeleted);
      statement = parsed.toSql();
    }
    final result = await sqliteCrdt.query(statement, args);
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

  CrdtQueryExecutor.inMemory(
      {bool? logStatements,
      bool singleInstance = true,
      DatabaseCreator? creator,
      bool migrate = false})
      : super(
            _CrdtDelegateInMemory(
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
  ///  [onlyNodeId] only return the last modified timestamp of the given node
  ///  [exceptNodeId] do not return the last modified timestamp of the given node
  Future<Hlc?> getLastModified(
      {String? onlyNodeId, String? exceptNodeId}) async {
    final crdtDelegate = delegate as _CrdtDelegate;
    return crdtDelegate.sqliteCrdt
        .getLastModified(onlyNodeId: onlyNodeId, exceptNodeId: exceptNodeId);
  }

  /// Returns the database changeset according to the given parameters.
  /// [customQueries] can be used to add custom queries to the changeset.
  /// [onlyTables] only return changes for the given tables
  /// [onlyNodeId] only return changes for the given node
  /// [exceptNodeId] do not return changes for the given node
  /// [modifiedOn] only return changes that were modified on the given timestamp
  /// [modifiedAfter] only return changes that were modified after the given timestamp
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

  /// merges the provided changeset with the database
  Future<void> merge(CrdtChangeset changeset) async {
    final crdtDelegate = delegate as _CrdtDelegate;
    return crdtDelegate.sqliteCrdt.merge(changeset);
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
