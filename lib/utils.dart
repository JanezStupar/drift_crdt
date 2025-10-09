import 'package:collection/collection.dart';
import 'package:source_span/source_span.dart';
import 'package:sqlparser/sqlparser.dart';
import 'package:sqlparser/utils/node_to_text.dart';

class DriftCrdtUtils {
  /// Transforms automatic (unnumbered) ? placeholders into explicit ?N placeholders.
  /// This ensures all placeholders have explicit indices (e.g., ?1, ?2, ?3).
  /// This is important when adding WHERE clauses that might reorder or add new placeholders.
  static void transformAutomaticExplicit(Statement statement) {
    statement.allDescendants
        .whereType<NumberedVariable>()
        .forEachIndexed((i, ref) {
      ref.explicitIndex ??= i + 1;
    });
  }

  /// Builds SQL suitable for PostgreSQL while preserving originally quoted
  /// identifiers and expanding SQLite-specific tokens like `ISNULL`.
  static String buildPostgresSql(ParseResult parsed, Statement statement) {
    final quotedIdentifiers = <String>{};
    for (final token in parsed.tokens) {
      if (token is IdentifierToken && token.escaped) {
        quotedIdentifiers.add(token.identifier);
      }
    }

    final builder = _PostgresNodeSqlBuilder(quotedIdentifiers);
    builder.visit(statement, null);
    return builder.buffer.toString();
  }

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
      final entityName = table.as ?? table.tableName;
      final schemaName = table.as == null ? table.schemaName : null;
      final reference = Reference(
        columnName: 'is_deleted',
        entityName: entityName,
        schemaName: schemaName,
      );

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

          // SQLite system tables
          if ([
            'sqlite_schema',
            'sqlite_master',
            'sqlite_temp_schema',
            'sqlite_temp_master',
          ].contains(table.tableName)) {
            return true;
          }

          // PostgreSQL system tables
          if ([
            'pg_catalog',
            'information_schema',
            'pg_class',
            'pg_index',
            'pg_attribute',
            'pg_tables',
          ].contains(table.tableName)) {
            return true;
          }

          // Check for schema-qualified system tables (e.g., pg_catalog.pg_tables)
          if (table.schemaName != null &&
              ['pg_catalog', 'information_schema'].contains(table.schemaName)) {
            return true;
          }
        }
      }
    }
    return false;
  }
}

class _PostgresNodeSqlBuilder extends NodeSqlBuilder {
  final Set<String> _quotedIdentifiers;

  _PostgresNodeSqlBuilder(this._quotedIdentifiers);

  @override
  String escapeIdentifier(String identifier) {
    if (_quotedIdentifiers.contains(identifier)) {
      final escaped = identifier.replaceAll('"', '""');
      return '"$escaped"';
    }
    return super.escapeIdentifier(identifier);
  }

  @override
  void identifier(String identifier,
      {bool spaceBefore = true, bool spaceAfter = true}) {
    if (_quotedIdentifiers.contains(identifier)) {
      final escaped = identifier.replaceAll('"', '""');
      symbol('"$escaped"', spaceBefore: spaceBefore, spaceAfter: spaceAfter);
      return;
    }
    super.identifier(identifier,
        spaceBefore: spaceBefore, spaceAfter: spaceAfter);
  }

  @override
  void visitIsNullExpression(IsNullExpression e, void arg) {
    visit(e.operand, arg);
    keyword(TokenType.$is);
    if (e.negated) {
      keyword(TokenType.not);
    }
    keyword(TokenType.$null);
  }

  @override
  void visitParentheses(Parentheses e, void arg) {
    final insertSpace = needsSpace;
    symbol('(', spaceBefore: insertSpace);
    visit(e.expression, arg);
    symbol(')');
    needsSpace = true;
  }
}
