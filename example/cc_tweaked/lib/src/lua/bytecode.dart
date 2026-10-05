// The instruction set of the VM and the compiled function prototype.
//
// The VM is a stack machine. Every function activation has a window of
// `maxLocals` local slots at its base, with the operand stack on top of it.
// An instruction is three integers in [FunctionProto.code]: `op a b`.
import 'dart:typed_data';

/// Opcodes. Comments show the stack effect (`..., x -> ..., y`).
abstract final class Op {
  /// `-> k`: push `consts[a]`.
  static const int loadK = 0;
  static const int loadNil = 1;
  static const int loadTrue = 2;
  static const int loadFalse = 3;

  /// `x ->`
  static const int pop = 4;

  /// Locals: `getLocal a` pushes slot `a`, `setLocal a` pops into it.
  static const int getLocal = 5;
  static const int setLocal = 6;

  /// Boxed locals (captured by a closure): the slot holds a `Cell`.
  static const int getCell = 7;
  static const int setCell = 8;

  /// `v ->`: puts a new `Cell(v)` in slot `a`.
  static const int newCell = 9;

  /// Wraps the value already in slot `a` into a new `Cell`.
  static const int wrapCell = 10;

  static const int getUpval = 11;
  static const int setUpval = 12;

  /// Globals of the closure's environment; `a` is a string constant.
  static const int getGlobal = 13;
  static const int setGlobal = 14;

  /// `-> env`: the function's environment table (`_ENV`).
  static const int getEnv = 15;

  /// `t k -> v`
  static const int getTable = 16;

  /// `t k v ->`
  static const int setTable = 17;

  /// `t -> v` with the key `consts[a]`.
  static const int getField = 18;

  /// `t v ->` with the key `consts[a]`.
  static const int setField = 19;

  /// `x -> x x`
  static const int dup = 20;

  /// `-> t`
  static const int newTable = 21;

  /// `t v -> t`: `t[a] = v` (array item of a constructor).
  static const int tableSetIndex = 22;

  /// `t k v -> t`
  static const int tableSetKey = 23;

  /// `t v -> t` with the key `consts[a]`.
  static const int tableSetField = 24;

  /// `t v1 .. vn n -> t`: stores an open list of values at `a`, `a + 1`, ...
  static const int tableSetList = 25;

  static const int add = 26;
  static const int sub = 27;
  static const int mul = 28;
  static const int div = 29;
  static const int mod = 30;
  static const int pow = 31;
  static const int concat = 32;
  static const int eq = 33;
  static const int ne = 34;
  static const int lt = 35;
  static const int le = 36;
  static const int gt = 37;
  static const int ge = 38;
  static const int unm = 39;
  static const int not = 40;
  static const int len = 41;

  /// `jmp a`: continue at instruction `a`.
  static const int jmp = 42;

  /// `x ->`: jump to `a` if `x` is false (`jmpFalse`) or true (`jmpTrue`).
  static const int jmpFalse = 43;
  static const int jmpTrue = 44;

  /// `x -> x` or `x ->`: if `x` is false (`jmpFalseKeep`) or true
  /// (`jmpTrueKeep`) jump to `a` keeping it, otherwise pop it.
  static const int jmpFalseKeep = 45;
  static const int jmpTrueKeep = 46;

  /// `x ->`: jump to `a` if `x` is nil.
  static const int jmpNil = 47;

  /// `fn arg1 .. argA -> r1 .. rB`; B is -1 for all results, which pushes
  /// the results and their count.
  static const int call = 48;

  /// Like [call], with `a` fixed arguments followed by an open list (the
  /// count of the open part is on top of the stack).
  static const int callOpen = 49;

  /// `v1 .. va ->` returns `a` values.
  static const int ret = 50;

  /// `v1 .. va open n ->` returns `a` fixed values and an open list.
  static const int retOpen = 51;

  /// `-> v1 .. va` (`a` >= 0), or `-> v1 .. vn n` for `a` = -1.
  static const int vararg = 52;

  /// `-> f`: a closure of prototype `a`.
  static const int closure = 53;

  /// Numeric for: slots `a` (index), `a + 1` (limit), `a + 2` (step) and
  /// `a + 3` (the visible variable). `forPrep` jumps to `b` when the loop
  /// does not run, `forLoop` jumps to `b` (the body) while it continues.
  static const int forPrep = 54;
  static const int forLoop = 55;

  /// `x y -> y x`
  static const int swap = 56;
}

/// How a closure captures one variable of the enclosing function.
final class UpvalueDesc {
  final String name;

  /// Captures local slot [index] of the enclosing function (true) or its
  /// upvalue number [index] (false).
  final bool fromLocal;
  final int index;

  const UpvalueDesc(this.name, this.fromLocal, this.index);
}

/// A compiled function. Prototypes are immutable and shared by all closures
/// (and all computers) created from them.
final class FunctionProto {
  final String name;
  final String chunkName;
  final int line;
  final int numParams;
  final bool isVararg;

  /// Number of local slots (parameters, locals and hidden loop state).
  final int maxLocals;

  /// Instructions, three integers each.
  final Int32List code;

  /// The source line of each instruction.
  final Int32List lines;
  final List<Object?> constants;
  final List<FunctionProto> protos;
  final List<UpvalueDesc> upvalues;

  /// Hints for error messages, by instruction: `global 'x'`, `method 'y'`.
  final Map<int, String> hints;

  const FunctionProto({
    required this.name,
    required this.chunkName,
    required this.line,
    required this.numParams,
    required this.isVararg,
    required this.maxLocals,
    required this.code,
    required this.lines,
    required this.constants,
    required this.protos,
    required this.upvalues,
    required this.hints,
  });
}
