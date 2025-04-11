import 'package:source_span/source_span.dart';
import 'package:sqlparser/sqlparser.dart';

class DriftCrdtUtils {
  static void _prepareSelectStatement(SelectStatement statement) {
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

      final expression = Parentheses(BinaryExpression(
        BinaryExpression(reference, equalToken, NumericLiteral(0)),
        orToken,
        IsNullExpression(reference),
      ));
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

  static void _prepareSelectSubquery(SelectStatementAsSource subquery) {
    final innerStatement = subquery.statement;
    if (innerStatement is SelectStatement) {
      _prepareSelectStatement(innerStatement);
    } else if (innerStatement is CompoundSelectStatement) {
      final base = innerStatement.base;
      if (base is SelectStatement) {
        _prepareSelectStatement(base);
      }

      for (final part in innerStatement.additional) {
        final select = part.select;
        if (select is SelectStatement) {
          _prepareSelectStatement(select);
        }
      }
    }
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
}
