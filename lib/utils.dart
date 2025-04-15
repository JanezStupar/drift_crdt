import 'package:source_span/source_span.dart';
import 'package:sqlparser/sqlparser.dart';
import 'package:sqlparser/utils/node_to_text.dart';

class DriftCrdtUtils {
  static void _prepareSelectSubquery(SelectStatementAsSource subquery) {
    final innerStatement = subquery.statement;
    if (innerStatement is SelectStatement) {
      prepareSelectStatement(innerStatement, false);
    } else if (innerStatement is CompoundSelectStatement) {
      final base = innerStatement.base;
      if (base is SelectStatement) {
        prepareSelectStatement(base, false);
      }

      for (final part in innerStatement.additional) {
        final select = part.select;
        if (select is SelectStatement) {
          prepareSelectStatement(select, false);
        }
      }
    }
  }

  /// We need to delete CRDT columns from a CreateTable statement because the
  /// `sqlite_crdt` library is going to insert them again.
  /// But we need to have them in our definitions to make other logic work correctly
  static String prepareCreateTableQuery(String query) {
    SqlEngine parser = SqlEngine();
    CreateTableStatement statement =
        (parser.parse(query).rootNode) as CreateTableStatement;
    final columnsToExclude = ['is_deleted', 'hlc', 'node_id', 'modified'];
    statement.columns = statement.columns
        .where((ColumnDefinition element) =>
            !columnsToExclude.contains(element.columnName))
        .toList();
    return statement.toSql();
  }

  /// Prepare the Select [statement] to be in line with the CRDT requirements
  /// if [queryDeleted] is set to `false` then we query only regular records
  /// if it is set to `true` we query all the records in database.
  /// This is useful in migrations, or auditing
  static void prepareSelectStatement(
      SelectStatement statement, bool queryDeleted) {
    var fakeSpan = SourceFile.fromString('fakeSpan').span(0);
    var andToken = Token(TokenType.and, fakeSpan);
    var orToken = Token(TokenType.or, fakeSpan);
    var equalToken = Token(TokenType.equal, fakeSpan);

    var rootTables = <TableReference>[];

    var from = statement.from;
    if (from is JoinClause) {
      final primary = from.primary;
      if (primary is TableReference) {
        rootTables.add(primary);
      } else if (primary is SelectStatementAsSource) {
        _prepareSelectSubquery(primary);
      }

      for (final join in from.joins) {
        final query = join.query;
        if (query is TableReference) {
          rootTables.add(query);
        } else if (query is SelectStatementAsSource) {
          _prepareSelectSubquery(query);
        }
      }
    } else if (from is TableReference) {
      rootTables.add(from);
    } else if (from is SelectStatementAsSource) {
      _prepareSelectSubquery(from);
    }

    for (final table in rootTables) {
      Reference reference;
      if (table.as != null) {
        reference = Reference(
          columnName: 'is_deleted',
          entityName: table.as,
          schemaName: table.schemaName,
        );
      } else {
        reference = Reference(columnName: 'is_deleted');
      }

      // Do we filter out the deleted record or not
      Expression expression;
      if (queryDeleted) {
        expression = Parentheses(BinaryExpression(
          BinaryExpression(reference, equalToken, NumericLiteral(1)),
          orToken,
          BinaryExpression(reference, equalToken, NumericLiteral(0)),
        ));
      } else {
        expression = Parentheses(BinaryExpression(
          BinaryExpression(reference, equalToken, NumericLiteral(0)),
          orToken,
          IsNullExpression(reference),
        ));
      }

      if (statement.where != null) {
        statement.where = BinaryExpression(
          statement.where!,
          andToken,
          expression,
        );
      } else {
        statement.where = expression;
      }
    }
  }

  // Queries that don't need to be intercepted and transformed
  static final _specialQueries = <String>{
    'SELECT 1',
  };

  // There are some queries where it doesn't make sense to add CRDT columns
  static bool isSpecialQuery(ParseResult result) {
    // Pragma queries don't need to be intercepted and transformed
    if (result.sql.toUpperCase().startsWith('PRAGMA')) {
      return true;
    }

    //  IF the query is on the lookup table, we don't need to add CRDT columns
    if (_specialQueries.contains(result.sql.toUpperCase())) {
      return true;
    }
    ;

    final statement = result.rootNode;
    if (statement is SelectStatement) {
      //     If the query is accessing the schema table, we don't need to add CRDT columns
      if (statement.from != null) {
        if (statement.from is TableReference) {
          final table = statement.from as TableReference;
          if ([
            'sqlite_schema',
            'sqlite_master',
            'sqlite_temp_schema',
            'sqlite_temp_master'
          ].contains(table.tableName)) {
            return true;
          }
        }
      }
    }
    return false;
  }
}
