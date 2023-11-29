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
Say the DRIFT generated output for a table is this:
```dart
i1.GeneratedColumn<String> _column_0(String aliasedName) =>
    i1.GeneratedColumn<String>('id', aliasedName, false,
        type: i1.DriftSqlType.string);
i1.GeneratedColumn<DateTime> _column_1(String aliasedName) =>
    i1.GeneratedColumn<DateTime>('start', aliasedName, false,
        type: i1.DriftSqlType.dateTime, defaultValue: currentDateAndTime);
i1.GeneratedColumn<DateTime> _column_2(String aliasedName) =>
    i1.GeneratedColumn<DateTime>('end', aliasedName, true,
        type: i1.DriftSqlType.dateTime);
i1.GeneratedColumn<String> _column_3(String aliasedName) =>
    i1.GeneratedColumn<String>('title', aliasedName, false,
        type: i1.DriftSqlType.string);
i1.GeneratedColumn<String> _column_4(String aliasedName) =>
    i1.GeneratedColumn<String>('body', aliasedName, true,
        type: i1.DriftSqlType.string);
i1.GeneratedColumn<String> _column_5(String aliasedName) =>
    i1.GeneratedColumn<String>('category', aliasedName, true,
        type: i1.DriftSqlType.string);
```

Add CRDT related closures like this:
```dart

i1.GeneratedColumn<String> _column_0(String aliasedName) =>
    i1.GeneratedColumn<String>('id', aliasedName, false,
        type: i1.DriftSqlType.string);
i1.GeneratedColumn<DateTime> _column_1(String aliasedName) =>
    i1.GeneratedColumn<DateTime>('start', aliasedName, false,
        type: i1.DriftSqlType.dateTime, defaultValue: currentDateAndTime);
i1.GeneratedColumn<DateTime> _column_2(String aliasedName) =>
    i1.GeneratedColumn<DateTime>('end', aliasedName, true,
        type: i1.DriftSqlType.dateTime);
i1.GeneratedColumn<String> _column_3(String aliasedName) =>
    i1.GeneratedColumn<String>('title', aliasedName, false,
        type: i1.DriftSqlType.string);
i1.GeneratedColumn<String> _column_4(String aliasedName) =>
    i1.GeneratedColumn<String>('body', aliasedName, true,
        type: i1.DriftSqlType.string);
i1.GeneratedColumn<String> _column_5(String aliasedName) =>
    i1.GeneratedColumn<String>('category', aliasedName, true,
        type: i1.DriftSqlType.string);
i1.GeneratedColumn<int> _column_6(String aliasedName) =>
    i1.GeneratedColumn<int>('is_deleted', aliasedName, false,
        type: i1.DriftSqlType.int, defaultValue: i1.Constant(0));
i1.GeneratedColumn<String> _column_7(String aliasedName) =>
    i1.GeneratedColumn<String>('hlc', aliasedName, false,
      type: i1.DriftSqlType.string,);
i1.GeneratedColumn<String> _column_8(String aliasedName) =>
    i1.GeneratedColumn<String>('node_id', aliasedName, false,
        type: i1.DriftSqlType.string);
i1.GeneratedColumn<String> _column_9(String aliasedName) =>
    i1.GeneratedColumn<String>('modified', aliasedName, false,
        type: i1.DriftSqlType.string);

```

#### 3. Add the CRDT columns to the schema_versions

Assume the following columns field inside the `VersionedTable`
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
        _column_6,
        _column_7,
        _column_8,
        _column_9
      ],
      attachedDatabase: database,
    ),
    alias: null);
```

#### 4. add the GeneratedColumns to the Shape class

Shape class for every table goes from this:
```dart
class Shape0 extends i0.VersionedTable {
  Shape0({required super.source, required super.alias}) : super.aliased();
  i1.GeneratedColumn<String> get id =>
      columnsByName['id']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<DateTime> get start =>
      columnsByName['start']! as i1.GeneratedColumn<DateTime>;
  i1.GeneratedColumn<DateTime> get end =>
      columnsByName['end']! as i1.GeneratedColumn<DateTime>;
  i1.GeneratedColumn<String> get title =>
      columnsByName['title']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<String> get body =>
      columnsByName['body']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<String> get category =>
      columnsByName['category']! as i1.GeneratedColumn<String>;
}

```

To this
```dart
class Shape0 extends i0.VersionedTable {
  Shape0({required super.source, required super.alias}) : super.aliased();
  i1.GeneratedColumn<String> get id =>
      columnsByName['id']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<DateTime> get start =>
      columnsByName['start']! as i1.GeneratedColumn<DateTime>;
  i1.GeneratedColumn<DateTime> get end =>
      columnsByName['end']! as i1.GeneratedColumn<DateTime>;
  i1.GeneratedColumn<String> get title =>
      columnsByName['title']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<String> get body =>
      columnsByName['body']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<String> get category =>
      columnsByName['category']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<int> get isDeleted =>
      columnsByName['is_deleted']! as i1.GeneratedColumn<int>;
  i1.GeneratedColumn<String> get hlc =>
      columnsByName['hlc']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<String> get node_id =>
      columnsByName['node_id']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<String> get modified =>
      columnsByName['modified']! as i1.GeneratedColumn<String>;
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
