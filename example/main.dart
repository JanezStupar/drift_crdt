import 'package:drift/drift.dart';
import 'package:drift_crdt/drift_crdt.dart';

QueryExecutor executorWithCrdt() {
  return CrdtQueryExecutor.inDatabaseFolder(path: 'app.db');
}
