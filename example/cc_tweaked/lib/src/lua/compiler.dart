// Compiles the syntax tree into bytecode (see bytecode.dart).
import 'dart:typed_data';

import 'ast.dart';
import 'bytecode.dart';
import 'lexer.dart';

/// Compiles the parsed main function of a chunk into a prototype.
FunctionProto compileMain(FunctionNode main, String chunkName) =>
    _FunctionGen(main, chunkName, const []).compile();

final class _PendingGoto {
  final String label;
  final int jump;
  final int line;

  _PendingGoto(this.label, this.jump, this.line);
}

final class _BlockContext {
  final int savedSlot;
  final Map<String, int> labels = {};
  final List<_PendingGoto> pending = [];

  _BlockContext(this.savedSlot);
}

final class _LoopContext {
  final List<int> breaks = [];
}

final class _FunctionGen {
  final FunctionNode node;
  final String chunkName;
  final List<UpvalueDesc> upvalues;

  final List<int> _code = [];
  final List<int> _lines = [];
  final List<Object?> _constants = [];
  final Map<Object, int> _constantIndex = {};
  final List<FunctionProto> _protos = [];
  final Map<int, String> _hints = {};
  final List<_BlockContext> _blocks = [];
  final List<_LoopContext> _loops = [];
  int _nextSlot = 0;
  int _maxSlot = 0;
  int _line = 0;

  _FunctionGen(this.node, this.chunkName, this.upvalues);

  int get _pc => _code.length ~/ 3;

  FunctionProto compile() {
    for (final param in node.params) {
      param.slot = _allocSlot();
    }
    _line = node.line;
    for (final param in node.params) {
      if (param.captured) _emit(Op.wrapCell, param.slot);
    }
    _enterBlock();
    _statements(node.body);
    _exitBlock(isFunctionBody: true);
    _emit(Op.ret, 0);
    return FunctionProto(
      name: node.name,
      chunkName: chunkName,
      line: node.line,
      numParams: node.params.length,
      isVararg: node.isVararg,
      maxLocals: _maxSlot,
      code: Int32List.fromList(_code),
      lines: Int32List.fromList(_lines),
      constants: _constants,
      protos: _protos,
      upvalues: upvalues,
      hints: _hints,
    );
  }

  // -- Emission helpers -----------------------------------------------------

  int _emit(int op, [int a = 0, int b = 0]) {
    final pc = _pc;
    _code
      ..add(op)
      ..add(a)
      ..add(b);
    _lines.add(_line);
    return pc;
  }

  void _patchJump(int pc, int target) => _code[pc * 3 + 1] = target;

  void _patchB(int pc, int target) => _code[pc * 3 + 2] = target;

  int _constant(Object value) {
    final existing = _constantIndex[value];
    if (existing != null) return existing;
    _constants.add(value);
    return _constantIndex[value] = _constants.length - 1;
  }

  int _allocSlot() {
    final slot = _nextSlot++;
    if (_nextSlot > _maxSlot) _maxSlot = _nextSlot;
    return slot;
  }

  void _hint(int pc, String? text) {
    if (text != null) _hints[pc] = text;
  }

  String? _describe(Expr e) => switch (e) {
    LocalExpr(:final variable) => "local '${variable.name}'",
    UpvalExpr(:final name) => "upvalue '$name'",
    GlobalExpr(:final name) => "global '$name'",
    IndexExpr(key: StringExpr(:final value)) => "field '$value'",
    MethodCallExpr(:final method) => "method '$method'",
    _ => null,
  };

  // -- Blocks, loops and labels ----------------------------------------------

  void _enterBlock() => _blocks.add(_BlockContext(_nextSlot));

  void _exitBlock({bool isFunctionBody = false}) {
    final context = _blocks.removeLast();
    _nextSlot = context.savedSlot;
    if (isFunctionBody) {
      if (context.pending.isNotEmpty) {
        final goto = context.pending.first;
        throw LuaSyntaxError(
          "${chunkDisplayName(chunkName)}:${goto.line}: "
          "no visible label '${goto.label}' for goto",
        );
      }
      return;
    }
    _blocks.last.pending.addAll(context.pending);
  }

  void _defineLabel(String name, int line) {
    for (final context in _blocks) {
      if (context.labels.containsKey(name)) {
        throw LuaSyntaxError(
          "${chunkDisplayName(chunkName)}:$line: label '$name' already defined",
        );
      }
    }
    final context = _blocks.last;
    final target = _pc;
    context.labels[name] = target;
    context.pending.removeWhere((goto) {
      if (goto.label != name) return false;
      _patchJump(goto.jump, target);
      return true;
    });
  }

  void _goto(String name, int line) {
    for (var i = _blocks.length - 1; i >= 0; i--) {
      final target = _blocks[i].labels[name];
      if (target != null) {
        _emit(Op.jmp, target);
        return;
      }
    }
    _blocks.last.pending.add(_PendingGoto(name, _emit(Op.jmp, 0), line));
  }

  // -- Statements -----------------------------------------------------------

  void _statements(Block block) {
    for (final statement in block.statements) {
      _statement(statement);
    }
  }

  void _scopedBlock(Block block) {
    _enterBlock();
    _statements(block);
    _exitBlock();
  }

  void _statement(Stmt s) {
    _line = s.line;
    switch (s) {
      case LocalStmt():
        _exprListFixed(s.values, s.variables.length);
        for (final variable in s.variables) {
          variable.slot = _allocSlot();
        }
        for (var i = s.variables.length - 1; i >= 0; i--) {
          _declareStore(s.variables[i]);
        }
      case LocalFunctionStmt():
        final variable = s.variable;
        variable.slot = _allocSlot();
        if (variable.captured) {
          _emit(Op.loadNil);
          _emit(Op.newCell, variable.slot);
          _function(s.function);
          _emit(Op.setCell, variable.slot);
        } else {
          _function(s.function);
          _emit(Op.setLocal, variable.slot);
        }
      case AssignStmt():
        _assignment(s);
      case CallStmt():
        _call(s.call, 0);
      case DoStmt():
        _scopedBlock(s.body);
      case WhileStmt():
        final start = _pc;
        _expr(s.condition);
        final exit = _emit(Op.jmpFalse);
        final loop = _LoopContext();
        _loops.add(loop);
        _scopedBlock(s.body);
        _loops.removeLast();
        _emit(Op.jmp, start);
        final end = _pc;
        _patchJump(exit, end);
        for (final jump in loop.breaks) {
          _patchJump(jump, end);
        }
      case RepeatStmt():
        final start = _pc;
        final loop = _LoopContext();
        _loops.add(loop);
        _enterBlock();
        _statements(s.body);
        _expr(s.condition);
        _emit(Op.jmpFalse, start);
        _exitBlock();
        _loops.removeLast();
        final end = _pc;
        for (final jump in loop.breaks) {
          _patchJump(jump, end);
        }
      case IfStmt():
        _ifStatement(s);
      case NumericForStmt():
        _numericFor(s);
      case GenericForStmt():
        _genericFor(s);
      case ReturnStmt():
        _return(s);
      case BreakStmt():
        _loops.last.breaks.add(_emit(Op.jmp));
      case GotoStmt():
        _goto(s.label, s.line);
      case LabelStmt():
        _defineLabel(s.name, s.line);
    }
  }

  void _ifStatement(IfStmt s) {
    final endJumps = <int>[];
    for (var i = 0; i < s.conditions.length; i++) {
      _line = s.conditions[i].line;
      _expr(s.conditions[i]);
      final skip = _emit(Op.jmpFalse);
      _scopedBlock(s.blocks[i]);
      final isLast = i == s.conditions.length - 1 && s.orElse == null;
      if (!isLast) endJumps.add(_emit(Op.jmp));
      _patchJump(skip, _pc);
    }
    final orElse = s.orElse;
    if (orElse != null) _scopedBlock(orElse);
    for (final jump in endJumps) {
      _patchJump(jump, _pc);
    }
  }

  void _numericFor(NumericForStmt s) {
    _enterBlock();
    final base = _allocSlot();
    _allocSlot();
    _allocSlot();
    final variableSlot = _allocSlot();
    _expr(s.start);
    _expr(s.limit);
    final step = s.step;
    if (step == null) {
      _emit(Op.loadK, _constant(1.0));
    } else {
      _expr(step);
    }
    _emit(Op.setLocal, base + 2);
    _emit(Op.setLocal, base + 1);
    _emit(Op.setLocal, base);
    _line = s.line;
    final prep = _emit(Op.forPrep, base);
    final bodyStart = _pc;
    s.variable.slot = variableSlot;
    if (s.variable.captured) _emit(Op.wrapCell, variableSlot);
    final loop = _LoopContext();
    _loops.add(loop);
    _scopedBlock(s.body);
    _loops.removeLast();
    _line = s.line;
    _emit(Op.forLoop, base, bodyStart);
    final end = _pc;
    _patchB(prep, end);
    for (final jump in loop.breaks) {
      _patchJump(jump, end);
    }
    _exitBlock();
  }

  void _genericFor(GenericForStmt s) {
    _enterBlock();
    final f = _allocSlot();
    final state = _allocSlot();
    final control = _allocSlot();
    for (final variable in s.variables) {
      variable.slot = _allocSlot();
    }
    _exprListFixed(s.values, 3);
    _emit(Op.setLocal, control);
    _emit(Op.setLocal, state);
    _emit(Op.setLocal, f);
    _line = s.line;
    final start = _pc;
    _emit(Op.getLocal, f);
    _emit(Op.getLocal, state);
    _emit(Op.getLocal, control);
    _emit(Op.call, 2, s.variables.length);
    for (var i = s.variables.length - 1; i >= 0; i--) {
      _emit(Op.setLocal, s.variables[i].slot);
    }
    final first = s.variables.first.slot;
    _emit(Op.getLocal, first);
    final exit = _emit(Op.jmpNil);
    _emit(Op.getLocal, first);
    _emit(Op.setLocal, control);
    for (final variable in s.variables) {
      if (variable.captured) _emit(Op.wrapCell, variable.slot);
    }
    final loop = _LoopContext();
    _loops.add(loop);
    _scopedBlock(s.body);
    _loops.removeLast();
    _line = s.line;
    _emit(Op.jmp, start);
    final end = _pc;
    _patchJump(exit, end);
    for (final jump in loop.breaks) {
      _patchJump(jump, end);
    }
    _exitBlock();
  }

  void _return(ReturnStmt s) {
    final values = s.values;
    if (values.isEmpty) {
      _emit(Op.ret, 0);
      return;
    }
    if (values.last.isMulti) {
      for (var i = 0; i < values.length - 1; i++) {
        _expr(values[i]);
      }
      _exprMulti(values.last, -1);
      _emit(Op.retOpen, values.length - 1);
    } else {
      for (final value in values) {
        _expr(value);
      }
      _emit(Op.ret, values.length);
    }
  }

  // -- Assignment -----------------------------------------------------------

  void _assignment(AssignStmt s) {
    if (s.targets.length == 1 && s.values.length == 1) {
      _assignSingle(s.targets.first, s.values.first);
      return;
    }
    final savedSlot = _nextSlot;
    final temps = <Expr, (int, int)>{};
    for (final target in s.targets) {
      if (target is IndexExpr) {
        _expr(target.object);
        final objectSlot = _allocSlot();
        _emit(Op.setLocal, objectSlot);
        _expr(target.key);
        final keySlot = _allocSlot();
        _emit(Op.setLocal, keySlot);
        temps[target] = (objectSlot, keySlot);
      }
    }
    _exprListFixed(s.values, s.targets.length);
    final valueSlot = _allocSlot();
    for (var i = s.targets.length - 1; i >= 0; i--) {
      final target = s.targets[i];
      if (target is IndexExpr) {
        final (objectSlot, keySlot) = temps[target]!;
        _emit(Op.setLocal, valueSlot);
        _emit(Op.getLocal, objectSlot);
        _emit(Op.getLocal, keySlot);
        _emit(Op.getLocal, valueSlot);
        _hint(_emit(Op.setTable), _describe(target.object));
      } else {
        _storeTo(target);
      }
    }
    _nextSlot = savedSlot;
  }

  void _assignSingle(Expr target, Expr value) {
    switch (target) {
      case IndexExpr():
        _expr(target.object);
        final key = target.key;
        if (key is StringExpr) {
          _expr(value);
          _hint(
            _emit(Op.setField, _constant(key.value)),
            _describe(target.object),
          );
        } else {
          _expr(key);
          _expr(value);
          _hint(_emit(Op.setTable), _describe(target.object));
        }
      default:
        _expr(value);
        _storeTo(target);
    }
  }

  /// Pops the top of the stack into a non-index [target].
  void _storeTo(Expr target) {
    switch (target) {
      case LocalExpr():
        _store(target.variable);
      case UpvalExpr():
        _emit(Op.setUpval, target.index);
      case GlobalExpr():
        _emit(Op.setGlobal, _constant(target.name));
      default:
        throw StateError('Not an assignable expression');
    }
  }

  void _store(VarInfo variable) =>
      _emit(variable.captured ? Op.setCell : Op.setLocal, variable.slot);

  void _declareStore(VarInfo variable) =>
      _emit(variable.captured ? Op.newCell : Op.setLocal, variable.slot);

  // -- Expressions ----------------------------------------------------------

  /// Compiles [e] so that it leaves exactly one value.
  void _expr(Expr e) {
    if (e.line > 0) _line = e.line;
    switch (e) {
      case NilExpr():
        _emit(Op.loadNil);
      case TrueExpr():
        _emit(Op.loadTrue);
      case FalseExpr():
        _emit(Op.loadFalse);
      case NumberExpr():
        _emit(Op.loadK, _constant(e.value));
      case StringExpr():
        _emit(Op.loadK, _constant(e.value));
      case VarargExpr():
        _emit(Op.vararg, 1);
      case FunctionExpr():
        _function(e.function);
      case LocalExpr():
        _emit(e.variable.captured ? Op.getCell : Op.getLocal, e.variable.slot);
      case UpvalExpr():
        _emit(Op.getUpval, e.index);
      case GlobalExpr():
        _emit(Op.getGlobal, _constant(e.name));
      case EnvExpr():
        _emit(Op.getEnv);
      case IndexExpr():
        _expr(e.object);
        final key = e.key;
        if (key is StringExpr) {
          _hint(
            _emit(Op.getField, _constant(key.value)),
            _describe(e.object),
          );
        } else {
          _expr(key);
          _hint(_emit(Op.getTable), _describe(e.object));
        }
      case CallExpr():
      case MethodCallExpr():
        _call(e, 1);
      case BinaryExpr():
        _binary(e);
      case AndExpr():
        _expr(e.left);
        final jump = _emit(Op.jmpFalseKeep);
        _expr(e.right);
        _patchJump(jump, _pc);
      case OrExpr():
        _expr(e.left);
        final jump = _emit(Op.jmpTrueKeep);
        _expr(e.right);
        _patchJump(jump, _pc);
      case UnaryExpr():
        _expr(e.operand);
        final pc = _emit(switch (e.op) {
          UnOp.neg => Op.unm,
          UnOp.not => Op.not,
          UnOp.len => Op.len,
        });
        _hint(pc, _describe(e.operand));
      case ParenExpr():
        _expr(e.inner);
      case TableExpr():
        _table(e);
    }
  }

  void _binary(BinaryExpr e) {
    _expr(e.left);
    _expr(e.right);
    final op = switch (e.op) {
      BinOp.add => Op.add,
      BinOp.sub => Op.sub,
      BinOp.mul => Op.mul,
      BinOp.div => Op.div,
      BinOp.mod => Op.mod,
      BinOp.pow => Op.pow,
      BinOp.concat => Op.concat,
      BinOp.eq => Op.eq,
      BinOp.ne => Op.ne,
      BinOp.lt => Op.lt,
      BinOp.le => Op.le,
      BinOp.gt => Op.gt,
      BinOp.ge => Op.ge,
    };
    _line = e.line;
    final pc = _emit(op);
    if (op <= Op.pow && op >= Op.add || op == Op.concat) {
      final left = _describe(e.left);
      final right = _describe(e.right);
      if (left != null || right != null) {
        _hints[pc] = '${left ?? ''}|${right ?? ''}';
      }
    }
  }

  /// Compiles [e] (a call or `...`) so that it leaves [want] values, or all of
  /// them followed by their count when [want] is -1.
  void _exprMulti(Expr e, int want) {
    switch (e) {
      case CallExpr():
      case MethodCallExpr():
        _call(e, want);
      case VarargExpr():
        _emit(Op.vararg, want);
      default:
        throw StateError('Not a multi-value expression');
    }
  }

  void _call(Expr e, int want) {
    final List<Expr> args;
    var extra = 0;
    String? hint;
    if (e is CallExpr) {
      _expr(e.function);
      args = e.args;
      hint = _describe(e.function);
    } else {
      final call = e as MethodCallExpr;
      _expr(call.object);
      _emit(Op.dup);
      _hint(_emit(Op.getField, _constant(call.method)), _describe(call.object));
      _emit(Op.swap);
      args = call.args;
      extra = 1;
      hint = "method '${call.method}'";
    }
    final open = args.isNotEmpty && args.last.isMulti;
    if (open) {
      for (var i = 0; i < args.length - 1; i++) {
        _expr(args[i]);
      }
      _exprMulti(args.last, -1);
    } else {
      for (final arg in args) {
        _expr(arg);
      }
    }
    _line = e.line;
    final fixed = open ? args.length - 1 : args.length;
    final pc = _emit(open ? Op.callOpen : Op.call, fixed + extra, want);
    _hint(pc, hint);
  }

  /// Pushes exactly [want] values from [values].
  void _exprListFixed(List<Expr> values, int want) {
    final n = values.length;
    if (n == 0) {
      for (var i = 0; i < want; i++) {
        _emit(Op.loadNil);
      }
      return;
    }
    for (var i = 0; i < n; i++) {
      final e = values[i];
      final isLast = i == n - 1;
      if (!isLast) {
        _expr(e);
        if (i >= want) _emit(Op.pop);
      } else {
        final need = want - i;
        if (need <= 0) {
          _expr(e);
          _emit(Op.pop);
        } else if (e.isMulti) {
          _exprMulti(e, need);
        } else {
          _expr(e);
          for (var k = 1; k < need; k++) {
            _emit(Op.loadNil);
          }
        }
      }
    }
  }

  void _function(FunctionNode function) {
    final descriptors = [
      for (final ref in function.upvalues)
        UpvalueDesc(
          ref.name,
          ref.local != null,
          ref.local != null ? ref.local!.slot : ref.parentIndex,
        ),
    ];
    final proto = _FunctionGen(function, chunkName, descriptors).compile();
    _protos.add(proto);
    _emit(Op.closure, _protos.length - 1);
  }

  void _table(TableExpr e) {
    _emit(Op.newTable);
    var index = 1;
    for (var i = 0; i < e.items.length; i++) {
      final item = e.items[i];
      final key = item.key;
      if (key == null) {
        final isLast = i == e.items.length - 1;
        if (isLast && item.value.isMulti) {
          _exprMulti(item.value, -1);
          _emit(Op.tableSetList, index);
        } else {
          _expr(item.value);
          _emit(Op.tableSetIndex, index);
          index++;
        }
      } else if (key is StringExpr) {
        _expr(item.value);
        _emit(Op.tableSetField, _constant(key.value));
      } else {
        _expr(key);
        _expr(item.value);
        _emit(Op.tableSetKey);
      }
    }
  }
}
