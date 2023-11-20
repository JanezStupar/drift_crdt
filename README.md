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

## Querying in drift_crdt and you!
When performing queries by default deleted records are not returned.

The reason is that we want the CRDT implementation to be seamless and should not 
break your application by default.

However if you want to query for deleted records you can use the `queryDeleted` helper function.

Example, to get all users including deleted ones:
```dart
  final result = await queryDeleted(
    (db.executor) as CrdtQueryExecutor,
    () async => db.select(db.users).get()
  );
```

## CRDT specific features
Use `CrdtQueryExecutor.getLastModified` to get the last modified timestamp of the database.
See [CrdtQueryExecutor.getLastModified](/lib/drift_crdt.dart) for more information.
```dart
  final changeset = await (db.executor as CrdtQueryExecutor).getCLastModified();
```

Use `CrdtQueryExecutor.getChangeset` to get the changeset of the database.
See [CrdtQueryExecutor.getChangeset](/lib/drift_crdt.dart) for more information.
```dart
  final changeset = await (db.executor as CrdtQueryExecutor).getChangeset();
```

Use 'CrdtQueryExecutor.merge' to merge a changeset into the database.
See [CrdtQueryExecutor.merge](/lib/drift_crdt.dart) for more information.
```dart
  await (db.executor as CrdtQueryExecutor).merge(changeset);
```

## Serialization into JSON
I am using the [json_annotation](https://pub.dev/packages/json_annotation) package to serialize the changesets into and from JSON in my own project.
You can see an example of such in the test suite of this package.

__Note__: The `drift_crdt` package is an alternative to the standard approach suggested in
the drift documentation (which consists of a `NativeDatabase` instead of `CrdtQueryExecutor`).

__Note__: Hasn't been tested on iOS and Android yet.
