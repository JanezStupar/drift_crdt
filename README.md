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

### Drift migrations

At the moment migrations are not supported. This is because the CRDT implementation hijacks the SQL queries and
modifies them to manage the CRDT functions.

However, the migrations can be made to work.

#### 1. Create the migrations as usual.
#### 2. Create closures for generating the columns
Add CRDT related closures to the top of the `schema_versions.dart` file like this:
```dart
i1.GeneratedColumn<int> _column_is_deleted(String aliasedName) =>
    i1.GeneratedColumn<int>('is_deleted', aliasedName, false,
        type: i1.DriftSqlType.int, defaultValue: i1.Constant(0));
i1.GeneratedColumn<String> _column_hlc(String aliasedName) =>
    i1.GeneratedColumn<String>(
      'hlc',
      aliasedName,
      false,
      type: i1.DriftSqlType.string,
    );
i1.GeneratedColumn<String> _column_node_id(String aliasedName) =>
    i1.GeneratedColumn<String>('node_id', aliasedName, false,
        type: i1.DriftSqlType.string);
i1.GeneratedColumn<String> _column_modified(String aliasedName) =>
    i1.GeneratedColumn<String>('modified', aliasedName, false,
        type: i1.DriftSqlType.string);
```

#### 3. Add the CRDT columns to the schema_versions

Assuming the columns field inside the `VersionedTable` object looks like this:
```dart
  late final Shape0 epochs = Shape0(
    source: i0.VersionedTable(
      entityName: 'epochs',
      withoutRowId: true,
      isStrict: false,
      tableConstraints: [
        'PRIMARY KEY(id)',
      ],
      columns: [
        _column_0,
        _column_1,
        _column_2,
        _column_3,
        _column_4,
        _column_5,
      ],
      attachedDatabase: database,
    ),
    alias: null);
```

Change it like this:
```dart
  late final Shape0 epochs = Shape0(
    source: i0.VersionedTable(
      entityName: 'epochs',
      withoutRowId: true,
      isStrict: false,
      tableConstraints: [
        'PRIMARY KEY(id)',
      ],
      columns: [
        _column_0,
        _column_1,
        _column_2,
        _column_3,
        _column_4,
        _column_5,
        _column_is_deleted,
        _column_hlc,
        _column_node_id,
        _column_modified,
      ],
      attachedDatabase: database,
    ),
    alias: null);
```

Then proceed to add the CRDT column references to every single shape class within the schema_versions file.

I would love to automate this process, but I don't have the tools to do it yet. If this plugin ever gets more popular,
I am sure Simon will add a feature that will enable us to inject these shapes.

Until then, you will have to do it manually.

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
