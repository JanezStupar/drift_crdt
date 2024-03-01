library drift_crdt;

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_crdt/drift_crdt.dart' as c;

class CrdtLazyDatabase extends QueryExecutor {
  /// Underlying executor
  late final c.CrdtQueryExecutor _delegate;

  bool _delegateAvailable = false;
  final SqlDialect _dialect;

  Completer<void>? _openDelegate;

  get delegate => _delegate;

  @override
  SqlDialect get dialect {
    // Drift reads dialect before database opened, so we must know in advance
    if (_delegateAvailable && _dialect != _delegate.dialect) {
      throw Exception('CrdtLazyDatabase created with $_dialect, but underlying '
          'database is ${_delegate.dialect}.');
    }
    return _dialect;
  }

  final DatabaseOpener opener;

  CrdtLazyDatabase(this.opener, {SqlDialect dialect = SqlDialect.sqlite})
      : _dialect = dialect;

  Future<void> _awaitOpened() {
    if (_delegateAvailable) {
      return Future.value();
    } else if (_openDelegate != null) {
      return _openDelegate!.future;
    } else {
      final delegate = _openDelegate = Completer();
      Future.sync(opener).then((database) {
        _delegate = database as c.CrdtQueryExecutor;
        _delegateAvailable = true;
        delegate.complete();
      }, onError: delegate.completeError);
      return delegate.future;
    }
  }

  @override
  TransactionExecutor beginTransaction() => _delegate.beginTransaction();

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) {
    return _awaitOpened().then((_) => _delegate.ensureOpen(user));
  }

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _delegate.runBatched(statements);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _delegate.runCustom(statement, args);

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _delegate.runDelete(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _delegate.runInsert(statement, args);

  @override
  Future<List<Map<String, Object?>>> runSelect(
      String statement, List<Object?> args) {
    return _delegate.runSelect(statement, args);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _delegate.runUpdate(statement, args);

  @override
  Future<void> close() {
    if (_delegateAvailable) {
      return _delegate.close();
    } else {
      return Future.value();
    }
  }

  Future<c.Hlc?> getLastModified(
      {String? onlyNodeId, String? exceptNodeId}) async {
    return _delegate.getLastModified(
        onlyNodeId: onlyNodeId, exceptNodeId: exceptNodeId);
  }

  Future<c.CrdtChangeset> getChangeset({
    Map<String, c.Query>? customQueries,
    Iterable<String>? onlyTables,
    String? onlyNodeId,
    String? exceptNodeId,
    c.Hlc? modifiedOn,
    c.Hlc? modifiedAfter,
  }) async {
    return _delegate.getChangeset(
        customQueries: customQueries,
        onlyTables: onlyTables,
        exceptNodeId: exceptNodeId,
        modifiedOn: modifiedOn,
        modifiedAfter: modifiedAfter);
  }

  /// merges the provided changeset with the database
  Future<void> merge(c.CrdtChangeset changeset) async {
    return _delegate.merge(changeset);
  }
}
