## drift_crdt

`drift_crdt` contains a CRDT drift database implementation based on the `sqflite`
package. This package is a plugin for Drift by Simon Binder and is based on
Simon Binder's `drift_sqflite` package.

For more information on `drift`, see its [documentation](https://drift.simonbinder.eu/docs/).

### Usage

The `CrdtQueryExecutor` class can be passed to the constructor of your drift database
class to make it use `sqflite`.

```dart
@DriftDatabase(tables: [Todos, Categories])
class MyDatabase extends _$MyDatabase {
  // we tell the database where to store the data with this constructor
  MyDatabase() : super(_openConnection());

  // you should bump this number whenever you change or add a table definition.
  // Migrations are covered later in the documentation.
  @override
  int get schemaVersion => 1;
}

QueryExecutor _openConnection() {
  return CrdtQueryExecutor.inDatabaseFolder(path: 'db.sqlite');
}
```

__Note__: The `drift_crdt` package is an alternative to the standard approach suggested in
the drift documentation (which consists of a `NativeDatabase` instead of `CrdtQueryExecutor`).
