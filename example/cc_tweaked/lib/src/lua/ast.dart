// The syntax tree the parser builds and the compiler walks. Names are already
// resolved: a reference is a local, an upvalue or a global.

/// A local variable. The parser flags it when a nested function captures it,
/// the compiler assigns its stack slot.
final class VarInfo {
  final String name;
  bool captured = false;
  int slot = -1;

  VarInfo(this.name);
}

/// How a function captures one variable of its parent: a [local] of the
/// parent, or the parent's upvalue number [parentIndex].
final class UpvalRef {
  final String name;
  final VarInfo? local;
  final int parentIndex;

  const UpvalRef(this.name, this.local, this.parentIndex);
}

/// A function body.
final class FunctionNode {
  String name;
  final int line;
  final List<VarInfo> params = [];
  bool isVararg = false;
  late Block body;
  final List<UpvalRef> upvalues = [];

  FunctionNode(this.name, this.line);
}

final class Block {
  final List<Stmt> statements = [];
}

// -- Expressions ------------------------------------------------------------

sealed class Expr {
  final int line;

  Expr(this.line);

  /// Whether the expression can produce several values.
  bool get isMulti => false;
}

final class NilExpr extends Expr {
  NilExpr(super.line);
}

final class TrueExpr extends Expr {
  TrueExpr(super.line);
}

final class FalseExpr extends Expr {
  FalseExpr(super.line);
}

final class NumberExpr extends Expr {
  final double value;

  NumberExpr(super.line, this.value);
}

final class StringExpr extends Expr {
  final String value;

  StringExpr(super.line, this.value);
}

final class VarargExpr extends Expr {
  VarargExpr(super.line);

  @override
  bool get isMulti => true;
}

final class FunctionExpr extends Expr {
  final FunctionNode function;

  FunctionExpr(super.line, this.function);
}

final class LocalExpr extends Expr {
  final VarInfo variable;

  LocalExpr(super.line, this.variable);
}

final class UpvalExpr extends Expr {
  final int index;
  final String name;

  UpvalExpr(super.line, this.index, this.name);
}

final class GlobalExpr extends Expr {
  final String name;

  GlobalExpr(super.line, this.name);
}

/// A bare `_ENV`.
final class EnvExpr extends Expr {
  EnvExpr(super.line);
}

final class IndexExpr extends Expr {
  final Expr object;
  final Expr key;

  IndexExpr(super.line, this.object, this.key);
}

final class CallExpr extends Expr {
  final Expr function;
  final List<Expr> args;

  CallExpr(super.line, this.function, this.args);

  @override
  bool get isMulti => true;
}

final class MethodCallExpr extends Expr {
  final Expr object;
  final String method;
  final List<Expr> args;

  MethodCallExpr(super.line, this.object, this.method, this.args);

  @override
  bool get isMulti => true;
}

enum BinOp {
  add,
  sub,
  mul,
  div,
  mod,
  pow,
  concat,
  eq,
  ne,
  lt,
  le,
  gt,
  ge,
}

enum UnOp { neg, not, len }

final class BinaryExpr extends Expr {
  final BinOp op;
  final Expr left;
  final Expr right;

  BinaryExpr(super.line, this.op, this.left, this.right);
}

final class AndExpr extends Expr {
  final Expr left;
  final Expr right;

  AndExpr(super.line, this.left, this.right);
}

final class OrExpr extends Expr {
  final Expr left;
  final Expr right;

  OrExpr(super.line, this.left, this.right);
}

final class UnaryExpr extends Expr {
  final UnOp op;
  final Expr operand;

  UnaryExpr(super.line, this.op, this.operand);
}

/// `(expr)`, which cuts a multi-value expression down to one value.
final class ParenExpr extends Expr {
  final Expr inner;

  ParenExpr(super.line, this.inner);
}

/// One entry of a table constructor: `value`, `name = value` or
/// `[key] = value`. [key] is null for a positional entry.
final class TableItem {
  final Expr? key;
  final Expr value;

  const TableItem(this.key, this.value);
}

final class TableExpr extends Expr {
  final List<TableItem> items;

  TableExpr(super.line, this.items);
}

// -- Statements -------------------------------------------------------------

sealed class Stmt {
  final int line;

  Stmt(this.line);
}

final class LocalStmt extends Stmt {
  final List<VarInfo> variables;
  final List<Expr> values;

  LocalStmt(super.line, this.variables, this.values);
}

final class LocalFunctionStmt extends Stmt {
  final VarInfo variable;
  final FunctionNode function;

  LocalFunctionStmt(super.line, this.variable, this.function);
}

final class AssignStmt extends Stmt {
  final List<Expr> targets;
  final List<Expr> values;

  AssignStmt(super.line, this.targets, this.values);
}

final class CallStmt extends Stmt {
  final Expr call;

  CallStmt(super.line, this.call);
}

final class DoStmt extends Stmt {
  final Block body;

  DoStmt(super.line, this.body);
}

final class WhileStmt extends Stmt {
  final Expr condition;
  final Block body;

  WhileStmt(super.line, this.condition, this.body);
}

final class RepeatStmt extends Stmt {
  final Block body;
  final Expr condition;

  RepeatStmt(super.line, this.body, this.condition);
}

final class IfStmt extends Stmt {
  final List<Expr> conditions;
  final List<Block> blocks;
  final Block? orElse;

  IfStmt(super.line, this.conditions, this.blocks, this.orElse);
}

final class NumericForStmt extends Stmt {
  final VarInfo variable;
  final Expr start;
  final Expr limit;
  final Expr? step;
  final Block body;

  NumericForStmt(
    super.line,
    this.variable,
    this.start,
    this.limit,
    this.step,
    this.body,
  );
}

final class GenericForStmt extends Stmt {
  final List<VarInfo> variables;
  final List<Expr> values;
  final Block body;

  GenericForStmt(super.line, this.variables, this.values, this.body);
}

final class ReturnStmt extends Stmt {
  final List<Expr> values;

  ReturnStmt(super.line, this.values);
}

final class BreakStmt extends Stmt {
  BreakStmt(super.line);
}

final class GotoStmt extends Stmt {
  final String label;

  GotoStmt(super.line, this.label);
}

final class LabelStmt extends Stmt {
  final String name;

  LabelStmt(super.line, this.name);
}
