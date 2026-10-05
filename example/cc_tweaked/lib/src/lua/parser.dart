// A recursive descent parser for Lua 5.1 plus the 5.2 syntax CC: Tweaked
// supports. It resolves names while it parses (local, upvalue or global), so
// the compiler knows which locals closures capture.
import 'ast.dart';
import 'lexer.dart';

final class _Scope {
  final List<VarInfo> vars = [];
}

final class _FuncState {
  final _FuncState? parent;
  final FunctionNode node;
  final List<_Scope> scopes = [];
  int loopDepth = 0;

  _FuncState(this.parent, this.node);

  VarInfo? findLocal(String name) {
    for (var s = scopes.length - 1; s >= 0; s--) {
      final vars = scopes[s].vars;
      for (var v = vars.length - 1; v >= 0; v--) {
        if (vars[v].name == name) return vars[v];
      }
    }
    return null;
  }
}

/// Parses a chunk into the main [FunctionNode].
FunctionNode parseLua(String source, String chunkName) =>
    _Parser(source, chunkName).parseChunk();

/// Binary operator priorities, `(left, right)`, as in the reference parser.
(int, int) _priority(Tok op) => switch (op) {
  Tok.kOr => (1, 1),
  Tok.kAnd => (2, 2),
  Tok.lt || Tok.gt || Tok.le || Tok.ge || Tok.ne || Tok.eq => (3, 3),
  Tok.concat => (5, 4),
  Tok.plus || Tok.minus => (6, 6),
  Tok.star || Tok.slash || Tok.percent => (7, 7),
  Tok.caret => (10, 9),
  _ => (-1, -1),
};

const int _unaryPriority = 8;

final class _Parser {
  final Lexer _lexer;
  late Token _tok;
  Token? _peeked;
  late _FuncState _fs;
  bool _sawEnvDeclaration = false;

  _Parser(String source, String chunkName) : _lexer = Lexer(source, chunkName) {
    _advance();
  }

  FunctionNode parseChunk() {
    final main = FunctionNode('main chunk', 0)..isVararg = true;
    _fs = _FuncState(null, main);
    _openScope();
    main.body = _block();
    if (_tok.type != Tok.eof) _error("'<eof>' expected");
    _closeScope();
    return main;
  }

  // -- Token helpers --------------------------------------------------------

  void _advance() {
    _tok = _peeked ?? _lexer.next();
    _peeked = null;
  }

  Token _peek() => _peeked ??= _lexer.next();

  Never _error(String message) =>
      _lexer.error(message, near: _tok.text, atLine: _tok.line);

  void _expect(Tok type, String what) {
    if (_tok.type != type) _error("'$what' expected");
    _advance();
  }

  bool _accept(Tok type) {
    if (_tok.type != type) return false;
    _advance();
    return true;
  }

  void _expectMatch(Tok type, String what, String who, int line) {
    if (_tok.type == type) {
      _advance();
      return;
    }
    if (line == _tok.line) _error("'$what' expected");
    _error("'$what' expected (to close '$who' at line $line)");
  }

  String _name() {
    if (_tok.type != Tok.name) _error('<name> expected');
    final text = _tok.text;
    _advance();
    return text;
  }

  // -- Scopes and names -----------------------------------------------------

  void _openScope() => _fs.scopes.add(_Scope());

  void _closeScope() => _fs.scopes.removeLast();

  VarInfo _declare(String name) {
    final variable = VarInfo(name);
    _fs.scopes.last.vars.add(variable);
    if (name == '_ENV') _sawEnvDeclaration = true;
    return variable;
  }

  int _findUpvalue(_FuncState fs, String name) {
    final upvalues = fs.node.upvalues;
    for (var i = 0; i < upvalues.length; i++) {
      if (upvalues[i].name == name) return i;
    }
    final parent = fs.parent;
    if (parent == null) return -1;
    final local = parent.findLocal(name);
    if (local != null) {
      local.captured = true;
      upvalues.add(UpvalRef(name, local, -1));
      return upvalues.length - 1;
    }
    final index = _findUpvalue(parent, name);
    if (index < 0) return -1;
    upvalues.add(UpvalRef(name, null, index));
    return upvalues.length - 1;
  }

  /// A local or upvalue named [name], or null.
  Expr? _resolveVariable(String name, int line) {
    final local = _fs.findLocal(name);
    if (local != null) return LocalExpr(line, local);
    final upvalue = _findUpvalue(_fs, name);
    if (upvalue >= 0) return UpvalExpr(line, upvalue, name);
    return null;
  }

  Expr _resolve(String name, int line) {
    final variable = _resolveVariable(name, line);
    if (variable != null) return variable;
    if (name == '_ENV') return EnvExpr(line);
    if (_sawEnvDeclaration) {
      final env = _resolveVariable('_ENV', line);
      if (env != null) return IndexExpr(line, env, StringExpr(line, name));
    }
    return GlobalExpr(line, name);
  }

  // -- Statements -----------------------------------------------------------

  bool _blockFollow() => switch (_tok.type) {
    Tok.eof || Tok.kElse || Tok.kElseif || Tok.kEnd || Tok.kUntil => true,
    _ => false,
  };

  Block _block() {
    final block = Block();
    while (!_blockFollow()) {
      if (_tok.type == Tok.kReturn) {
        block.statements.add(_returnStatement());
        break;
      }
      final statement = _statement();
      if (statement != null) block.statements.add(statement);
    }
    return block;
  }

  Block _scopedBlock() {
    _openScope();
    final block = _block();
    _closeScope();
    return block;
  }

  Stmt? _statement() {
    final line = _tok.line;
    switch (_tok.type) {
      case Tok.semicolon:
        _advance();
        return null;
      case Tok.kIf:
        return _ifStatement(line);
      case Tok.kWhile:
        _advance();
        final condition = _expr();
        _expect(Tok.kDo, 'do');
        _fs.loopDepth++;
        final body = _scopedBlock();
        _fs.loopDepth--;
        _expectMatch(Tok.kEnd, 'end', 'while', line);
        return WhileStmt(line, condition, body);
      case Tok.kDo:
        _advance();
        final body = _scopedBlock();
        _expectMatch(Tok.kEnd, 'end', 'do', line);
        return DoStmt(line, body);
      case Tok.kFor:
        return _forStatement(line);
      case Tok.kRepeat:
        _advance();
        _fs.loopDepth++;
        _openScope();
        final body = _block();
        _expectMatch(Tok.kUntil, 'until', 'repeat', line);
        final condition = _expr();
        _closeScope();
        _fs.loopDepth--;
        return RepeatStmt(line, body, condition);
      case Tok.kFunction:
        return _functionStatement(line);
      case Tok.kLocal:
        _advance();
        return _accept(Tok.kFunction)
            ? _localFunction(line)
            : _localStatement(line);
      case Tok.dbcolon:
        _advance();
        final name = _name();
        _expect(Tok.dbcolon, '::');
        return LabelStmt(line, name);
      case Tok.kBreak:
        _advance();
        if (_fs.loopDepth == 0) _error('no loop to break');
        return BreakStmt(line);
      case Tok.kGoto:
        _advance();
        return GotoStmt(line, _name());
      default:
        return _expressionStatement(line);
    }
  }

  Stmt _ifStatement(int line) {
    final conditions = <Expr>[];
    final blocks = <Block>[];
    Block? orElse;
    // `if` or `elseif`
    _advance();
    conditions.add(_expr());
    _expect(Tok.kThen, 'then');
    blocks.add(_scopedBlock());
    while (true) {
      if (_tok.type == Tok.kElseif) {
        _advance();
        conditions.add(_expr());
        _expect(Tok.kThen, 'then');
        blocks.add(_scopedBlock());
      } else if (_tok.type == Tok.kElse) {
        _advance();
        orElse = _scopedBlock();
        _expectMatch(Tok.kEnd, 'end', 'if', line);
        break;
      } else {
        _expectMatch(Tok.kEnd, 'end', 'if', line);
        break;
      }
    }
    return IfStmt(line, conditions, blocks, orElse);
  }

  Stmt _forStatement(int line) {
    _advance();
    final first = _name();
    if (_tok.type == Tok.assign) {
      _advance();
      final start = _expr();
      _expect(Tok.comma, ',');
      final limit = _expr();
      Expr? step;
      if (_accept(Tok.comma)) step = _expr();
      _expect(Tok.kDo, 'do');
      _fs.loopDepth++;
      _openScope();
      final variable = _declare(first);
      final body = _block();
      _closeScope();
      _fs.loopDepth--;
      _expectMatch(Tok.kEnd, 'end', 'for', line);
      return NumericForStmt(line, variable, start, limit, step, body);
    }
    final names = <String>[first];
    while (_accept(Tok.comma)) {
      names.add(_name());
    }
    _expect(Tok.kIn, 'in');
    final values = _exprList();
    _expect(Tok.kDo, 'do');
    _fs.loopDepth++;
    _openScope();
    final variables = [for (final name in names) _declare(name)];
    final body = _block();
    _closeScope();
    _fs.loopDepth--;
    _expectMatch(Tok.kEnd, 'end', 'for', line);
    return GenericForStmt(line, variables, values, body);
  }

  Stmt _functionStatement(int line) {
    _advance();
    var fullName = _tok.text;
    final nameLine = _tok.line;
    var target = _resolve(_name(), nameLine);
    var isMethod = false;
    while (_tok.type == Tok.dot || _tok.type == Tok.colon) {
      final colon = _tok.type == Tok.colon;
      _advance();
      final key = _name();
      fullName = '$fullName${colon ? ':' : '.'}$key';
      target = IndexExpr(nameLine, target, StringExpr(nameLine, key));
      if (colon) {
        isMethod = true;
        break;
      }
    }
    final function = _functionBody(fullName, line, isMethod);
    return AssignStmt(line, [target], [FunctionExpr(line, function)]);
  }

  Stmt _localFunction(int line) {
    final name = _name();
    final variable = _declare(name);
    final function = _functionBody(name, line, false);
    return LocalFunctionStmt(line, variable, function);
  }

  Stmt _localStatement(int line) {
    final names = <String>[_name()];
    while (_accept(Tok.comma)) {
      names.add(_name());
    }
    final values = _accept(Tok.assign) ? _exprList() : <Expr>[];
    final variables = [for (final name in names) _declare(name)];
    return LocalStmt(line, variables, values);
  }

  Stmt _returnStatement() {
    final line = _tok.line;
    _advance();
    final values = _blockFollow() || _tok.type == Tok.semicolon
        ? <Expr>[]
        : _exprList();
    _accept(Tok.semicolon);
    if (!_blockFollow()) _error("'<eof>' expected");
    return ReturnStmt(line, values);
  }

  Stmt _expressionStatement(int line) {
    final first = _suffixedExpr();
    if (_tok.type == Tok.assign || _tok.type == Tok.comma) {
      final targets = <Expr>[first];
      while (_accept(Tok.comma)) {
        targets.add(_suffixedExpr());
      }
      for (final target in targets) {
        if (target is! LocalExpr &&
            target is! UpvalExpr &&
            target is! GlobalExpr &&
            target is! IndexExpr) {
          _error('syntax error');
        }
      }
      _expect(Tok.assign, '=');
      return AssignStmt(line, targets, _exprList());
    }
    if (first is! CallExpr && first is! MethodCallExpr) _error('syntax error');
    return CallStmt(line, first);
  }

  // -- Functions ------------------------------------------------------------

  FunctionNode _functionBody(String name, int line, bool isMethod) {
    final node = FunctionNode(name, line);
    final state = _FuncState(_fs, node);
    _fs = state;
    _openScope();
    if (isMethod) node.params.add(_declare('self'));
    _expect(Tok.lparen, '(');
    if (_tok.type != Tok.rparen) {
      do {
        if (_tok.type == Tok.ellipsis) {
          _advance();
          node.isVararg = true;
          break;
        }
        node.params.add(_declare(_name()));
      } while (_accept(Tok.comma));
    }
    _expect(Tok.rparen, ')');
    node.body = _block();
    _expectMatch(Tok.kEnd, 'end', 'function', line);
    _closeScope();
    _fs = state.parent!;
    return node;
  }

  // -- Expressions ----------------------------------------------------------

  List<Expr> _exprList() {
    final list = <Expr>[_expr()];
    while (_accept(Tok.comma)) {
      list.add(_expr());
    }
    return list;
  }

  Expr _expr() => _subExpr(0);

  Expr _subExpr(int limit) {
    Expr left;
    final line = _tok.line;
    final unary = _tok.type == Tok.kNot
        ? UnOp.not
        : _tok.type == Tok.minus
        ? UnOp.neg
        : _tok.type == Tok.hash
        ? UnOp.len
        : null;
    if (unary != null) {
      _advance();
      final operand = _subExpr(_unaryPriority);
      if (unary == UnOp.neg && operand is NumberExpr) {
        left = NumberExpr(line, -operand.value);
      } else {
        left = UnaryExpr(line, unary, operand);
      }
    } else {
      left = _simpleExpr();
    }
    while (true) {
      final op = _tok.type;
      final (leftPriority, rightPriority) = _priority(op);
      if (leftPriority < 0 || leftPriority <= limit) break;
      final opLine = _tok.line;
      _advance();
      final right = _subExpr(rightPriority);
      left = _binary(opLine, op, left, right);
    }
    return left;
  }

  Expr _binary(int line, Tok op, Expr left, Expr right) => switch (op) {
    Tok.kAnd => AndExpr(line, left, right),
    Tok.kOr => OrExpr(line, left, right),
    Tok.plus => BinaryExpr(line, BinOp.add, left, right),
    Tok.minus => BinaryExpr(line, BinOp.sub, left, right),
    Tok.star => BinaryExpr(line, BinOp.mul, left, right),
    Tok.slash => BinaryExpr(line, BinOp.div, left, right),
    Tok.percent => BinaryExpr(line, BinOp.mod, left, right),
    Tok.caret => BinaryExpr(line, BinOp.pow, left, right),
    Tok.concat => BinaryExpr(line, BinOp.concat, left, right),
    Tok.eq => BinaryExpr(line, BinOp.eq, left, right),
    Tok.ne => BinaryExpr(line, BinOp.ne, left, right),
    Tok.lt => BinaryExpr(line, BinOp.lt, left, right),
    Tok.le => BinaryExpr(line, BinOp.le, left, right),
    Tok.gt => BinaryExpr(line, BinOp.gt, left, right),
    _ => BinaryExpr(line, BinOp.ge, left, right),
  };

  Expr _simpleExpr() {
    final line = _tok.line;
    switch (_tok.type) {
      case Tok.number:
        final value = _tok.number;
        _advance();
        return NumberExpr(line, value);
      case Tok.string:
        final value = _tok.text;
        _advance();
        return StringExpr(line, value);
      case Tok.kNil:
        _advance();
        return NilExpr(line);
      case Tok.kTrue:
        _advance();
        return TrueExpr(line);
      case Tok.kFalse:
        _advance();
        return FalseExpr(line);
      case Tok.ellipsis:
        if (!_fs.node.isVararg) {
          _error("cannot use '...' outside a vararg function");
        }
        _advance();
        return VarargExpr(line);
      case Tok.lbrace:
        return _tableConstructor();
      case Tok.kFunction:
        _advance();
        return FunctionExpr(line, _functionBody('?', line, false));
      default:
        return _suffixedExpr();
    }
  }

  Expr _primaryExpr() {
    final line = _tok.line;
    switch (_tok.type) {
      case Tok.name:
        return _resolve(_name(), line);
      case Tok.lparen:
        _advance();
        final inner = _expr();
        _expectMatch(Tok.rparen, ')', '(', line);
        return inner.isMulti ? ParenExpr(line, inner) : inner;
      default:
        _error('unexpected symbol');
    }
  }

  Expr _suffixedExpr() {
    var expr = _primaryExpr();
    while (true) {
      final line = _tok.line;
      switch (_tok.type) {
        case Tok.dot:
          _advance();
          expr = IndexExpr(line, expr, StringExpr(line, _name()));
        case Tok.lbracket:
          _advance();
          final key = _expr();
          _expect(Tok.rbracket, ']');
          expr = IndexExpr(line, expr, key);
        case Tok.colon:
          _advance();
          final method = _name();
          expr = MethodCallExpr(line, expr, method, _callArguments());
        case Tok.lparen:
        case Tok.string:
        case Tok.lbrace:
          expr = CallExpr(line, expr, _callArguments());
        default:
          return expr;
      }
    }
  }

  List<Expr> _callArguments() {
    switch (_tok.type) {
      case Tok.string:
        final arg = StringExpr(_tok.line, _tok.text);
        _advance();
        return [arg];
      case Tok.lbrace:
        return [_tableConstructor()];
      case Tok.lparen:
        final line = _tok.line;
        _advance();
        if (_accept(Tok.rparen)) return <Expr>[];
        final args = _exprList();
        _expectMatch(Tok.rparen, ')', '(', line);
        return args;
      default:
        _error('function arguments expected');
    }
  }

  Expr _tableConstructor() {
    final line = _tok.line;
    _expect(Tok.lbrace, '{');
    final items = <TableItem>[];
    while (_tok.type != Tok.rbrace) {
      if (_tok.type == Tok.lbracket) {
        _advance();
        final key = _expr();
        _expect(Tok.rbracket, ']');
        _expect(Tok.assign, '=');
        items.add(TableItem(key, _expr()));
      } else if (_tok.type == Tok.name && _peek().type == Tok.assign) {
        final keyLine = _tok.line;
        final key = StringExpr(keyLine, _name());
        _advance();
        items.add(TableItem(key, _expr()));
      } else {
        items.add(TableItem(null, _expr()));
      }
      if (!_accept(Tok.comma) && !_accept(Tok.semicolon)) break;
    }
    _expectMatch(Tok.rbrace, '}', '{', line);
    return TableExpr(line, items);
  }
}
