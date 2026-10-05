// The Lua virtual machine: a stack machine with explicit call frames.
//
// Lua-to-Lua calls, metamethods called from instructions, `pcall` and
// coroutines never recurse on the Dart stack: each coroutine owns its value
// stack and its frame list, so a coroutine can yield from any depth (across
// `pcall` and metamethods), and the machine can stop after any instruction
// when its time slice is used up and resume later.
//
// Two things do recurse: resuming a coroutine from Lua, and calls from
// library functions into Lua (`table.sort` comparators, `string.gsub`
// callbacks, ...). A coroutine cannot yield through the latter, and the VM
// cannot be preempted inside them; they get a bounded overshoot instead.
import 'dart:math' as math;
import 'dart:typed_data';

import 'bytecode.dart';
import 'compiler.dart';
import 'lexer.dart';
import 'parser.dart';
import 'value.dart';

const int _kLua = 0;
const int _kPcall = 1;
const int _kXpcall = 2;

/// Results of `_precall`.
const int _completed = 0;
const int _pushed = 1;
const int _preemptRequest = 2;
const int _yielded = 3;

/// Result transformations for comparison metamethods.
const int _xformNone = 0;
const int _xformBool = 1;
const int _xformNotBool = 2;

final Int32List _noCode = Int32List(0);

/// One activation: a Lua function, or a marker for a `pcall`/`xpcall`.
final class Frame {
  final LuaClosure? closure;
  final Int32List code;
  final List<Object?> constants;
  final int base;
  final int fnIndex;
  final int wanted;
  final List<Object?> varargs;
  final int kind;
  final int xform;
  int pc = 0;

  /// The message handler of an `xpcall`.
  Object? handler;

  /// The coroutine's non-yieldable depth when the `pcall` started.
  int nativeDepth = 0;

  Frame.lua(
    LuaClosure this.closure,
    this.base,
    this.fnIndex,
    this.wanted,
    this.varargs,
    this.xform,
  ) : code = closure.proto.code,
      constants = closure.proto.constants,
      kind = _kLua;

  Frame.marker(this.kind, this.fnIndex, this.wanted, this.nativeDepth)
    : closure = null,
      code = _noCode,
      constants = const [],
      base = 0,
      varargs = noValues,
      xform = _xformNone;

  bool get isLua => kind == _kLua;
}

/// The life cycle of a coroutine.
enum CoStatus { fresh, suspended, running, normal, dead, preempted }

/// A Lua thread: its own value stack and call frames.
final class Coroutine {
  final LuaFunction function;
  final List<Object?> stack = <Object?>[];
  final List<Frame> frames = <Frame>[];
  CoStatus status = CoStatus.fresh;

  /// How many library calls into Lua are active on this coroutine.
  int nativeDepth = 0;

  /// The values of the last `yield`.
  List<Object?> transfer = noValues;

  /// How many results the `yield` call site wanted.
  int yieldWanted = 0;

  Coroutine(this.function);
}

/// What happened when a coroutine ran.
sealed class ResumeOutcome {
  const ResumeOutcome();
}

/// The coroutine yielded [values].
final class Yielded extends ResumeOutcome {
  final List<Object?> values;

  const Yielded(this.values);
}

/// The coroutine's function returned [values].
final class Finished extends ResumeOutcome {
  final List<Object?> values;

  const Finished(this.values);
}

/// The time slice ran out. Call `resume` again to continue.
final class Preempted extends ResumeOutcome {
  const Preempted();
}

/// The coroutine failed.
final class Failed extends ResumeOutcome {
  final LuaError error;

  const Failed(this.error);
}

enum _Exec { done, yielded, preempted }

/// Caches compiled chunks across VMs. Prototypes are immutable, so every
/// computer can share them.
final class ProtoCache {
  final Map<int, List<(String, String, FunctionProto)>> _buckets = {};

  FunctionProto compile(String source, String chunkName) {
    final bucket = _buckets.putIfAbsent(source.hashCode, () => []);
    for (final (cachedSource, cachedName, proto) in bucket) {
      if (cachedName == chunkName && cachedSource == source) return proto;
    }
    final proto = compileMain(parseLua(source, chunkName), chunkName);
    bucket.add((source, chunkName, proto));
    return proto;
  }
}

/// The interpreter. One instance runs one computer's Lua state.
final class LuaVm {
  /// The global table of new chunks.
  final LuaTable globals = LuaTable();

  /// The metatable shared by all strings (`__index` is the string library).
  final LuaTable stringMeta = LuaTable();

  /// A clock for time slices.
  final Stopwatch clock = Stopwatch()..start();

  /// Where the current time slice ends, in [clock] microseconds.
  int deadlineMicros = 1 << 60;

  /// How far past the deadline code that cannot be preempted may run before
  /// it fails with "Too long without yielding".
  int overshootMicros = 2000000;

  /// Makes the running code fail once with "Too long without yielding".
  bool abortRequested = false;

  /// The deepest call stack of one coroutine.
  final int maxCallDepth;

  /// The coroutine the host treats as the main thread (`coroutine.running`).
  Coroutine? rootCoroutine;

  /// The longest string `..` and `string.rep` may build.
  final int maxStringLength;

  final ProtoCache _cache;
  Coroutine? _current;
  int _syncDepth = 0;
  int _resumeDepth = 0;
  int _ticks = 0;

  LuaVm({
    ProtoCache? cache,
    this.maxCallDepth = 7000,
    this.maxStringLength = 64 * 1024 * 1024,
  }) : _cache = cache ?? ProtoCache();

  /// The coroutine that is running, if any.
  Coroutine? get current => _current;

  // -- Loading --------------------------------------------------------------

  /// Compiles [source] into a function. Throws [LuaSyntaxError].
  LuaClosure load(String source, String chunkName, {LuaTable? env}) {
    final proto = _cache.compile(source, chunkName);
    return LuaClosure(proto, const <Cell>[], env ?? globals);
  }

  // -- Calling from the host ------------------------------------------------

  /// Calls [function] and returns its results. May be called from library
  /// functions while Lua runs. Errors are thrown as [LuaError].
  List<Object?> call(Object? function, List<Object?> args) {
    final co = _current;
    if (co == null) {
      final target = function is LuaFunction
          ? function
          : throw LuaError.message('attempt to call a ${luaTypeName(function)} value');
      final temp = Coroutine(target);
      _syncDepth++;
      try {
        final outcome = resume(temp, args);
        return switch (outcome) {
          Finished(:final values) => values,
          Failed(:final error) => throw error,
          _ => throw LuaError.message('attempt to yield from outside a coroutine'),
        };
      } finally {
        _syncDepth--;
      }
    }
    final stack = co.stack;
    final frames = co.frames;
    final fnIndex = stack.length;
    final depth = frames.length;
    stack
      ..add(function)
      ..addAll(args);
    co.nativeDepth++;
    _syncDepth++;
    try {
      final status = _precall(co, fnIndex, args.length, -1, _xformNone, null);
      if (status == _pushed) _run(co, depth);
      final count = stack.removeLast() as int;
      final results = stack.sublist(fnIndex, fnIndex + count);
      stack.length = fnIndex;
      return results;
    } catch (_) {
      if (frames.length > depth) frames.removeRange(depth, frames.length);
      if (stack.length > fnIndex) stack.length = fnIndex;
      rethrow;
    } finally {
      co.nativeDepth--;
      _syncDepth--;
    }
  }

  /// A new coroutine that will run [function].
  Coroutine newCoroutine(LuaFunction function) => Coroutine(function);

  // -- Coroutines -------------------------------------------------------------

  /// Starts or continues [co]. [args] are the arguments of the function the
  /// first time, and the results of `yield` afterwards. After [Preempted],
  /// resuming continues where the coroutine stopped and ignores [args].
  ResumeOutcome resume(Coroutine co, List<Object?> args) {
    switch (co.status) {
      case CoStatus.dead:
        return Failed(LuaError('cannot resume dead coroutine'));
      case CoStatus.running:
      case CoStatus.normal:
        return Failed(LuaError('cannot resume non-suspended coroutine'));
      case CoStatus.fresh:
      case CoStatus.suspended:
      case CoStatus.preempted:
        break;
    }
    if (_resumeDepth >= 100) return Failed(LuaError('C stack overflow'));
    final previous = _current;
    final before = co.status;
    previous?.status = CoStatus.normal;
    _current = co;
    co.status = CoStatus.running;
    _resumeDepth++;
    try {
      final _Exec exec;
      final stack = co.stack;
      if (before == CoStatus.fresh) {
        stack
          ..add(co.function)
          ..addAll(args);
        final status = _precall(co, 0, args.length, -1, _xformNone, null);
        exec = _afterPrecall(co, status);
      } else if (before == CoStatus.suspended) {
        _deliver(co, stack.length, args, co.yieldWanted, _xformNone);
        _finishMarkers(co, 0);
        exec = co.frames.isEmpty ? _Exec.done : _run(co, 0);
      } else {
        exec = _run(co, 0);
      }
      switch (exec) {
        case _Exec.done:
          co.status = CoStatus.dead;
          final count = stack.removeLast() as int;
          final values = stack.sublist(0, count);
          stack.clear();
          return Finished(values);
        case _Exec.yielded:
          co.status = CoStatus.suspended;
          return Yielded(co.transfer);
        case _Exec.preempted:
          co.status = CoStatus.preempted;
          return const Preempted();
      }
    } on LuaError catch (e) {
      return _die(co, e);
    } catch (e) {
      return _die(co, LuaError('Java Exception Thrown: $e'));
    } finally {
      _resumeDepth--;
      _current = previous;
      previous?.status = CoStatus.running;
    }
  }

  Failed _die(Coroutine co, LuaError error) {
    co.status = CoStatus.dead;
    co.frames.clear();
    co.stack.clear();
    return Failed(error);
  }

  _Exec _afterPrecall(Coroutine co, int status) {
    switch (status) {
      case _pushed:
        return _run(co, 0);
      case _yielded:
        return _Exec.yielded;
      case _preemptRequest:
        return _Exec.preempted;
      default:
        return co.frames.isEmpty ? _Exec.done : _run(co, 0);
    }
  }

  // -- Metatables -----------------------------------------------------------

  /// The metatable of [value], if it has one.
  LuaTable? metatableOf(Object? value) {
    if (value is LuaTable) return value.meta;
    if (value is String) return stringMeta;
    return null;
  }

  /// The metamethod [event] of [value], or null.
  Object? metamethod(Object? value, String event) =>
      metatableOf(value)?.getString(event);

  // -- Operations for library code ------------------------------------------

  /// `value[key]` with metamethods. Metamethods run to completion (they
  /// cannot yield).
  Object? index(Object? value, Object? key) {
    var object = value;
    for (var i = 0; i < 100; i++) {
      Object? handler;
      if (object is LuaTable) {
        final raw = object.get(key);
        if (raw != null) return raw;
        final meta = object.meta;
        if (meta == null) return null;
        handler = meta.getString('__index');
        if (handler == null) return null;
      } else {
        handler = metamethod(object, '__index');
        if (handler == null) {
          throw LuaError.message(
            'attempt to index a ${luaTypeName(object)} value',
          );
        }
      }
      if (handler is LuaFunction) {
        final results = call(handler, [object, key]);
        return results.isEmpty ? null : results.first;
      }
      object = handler;
    }
    throw LuaError.message("loop in gettable");
  }

  /// `value[key] = newValue` with metamethods.
  void setIndex(Object? value, Object? key, Object? newValue) {
    var object = value;
    for (var i = 0; i < 100; i++) {
      Object? handler;
      if (object is LuaTable) {
        final meta = object.meta;
        if (meta == null || object.get(key) != null) {
          _rawSet(object, key, newValue);
          return;
        }
        handler = meta.getString('__newindex');
        if (handler == null) {
          _rawSet(object, key, newValue);
          return;
        }
      } else {
        handler = metamethod(object, '__newindex');
        if (handler == null) {
          throw LuaError.message(
            'attempt to index a ${luaTypeName(object)} value',
          );
        }
      }
      if (handler is LuaFunction) {
        call(handler, [object, key, newValue]);
        return;
      }
      object = handler;
    }
    throw LuaError.message("loop in settable");
  }

  void _rawSet(LuaTable table, Object? key, Object? value) {
    if (key == null) throw LuaError.message('table index is nil');
    if (key is double && key.isNaN) {
      throw LuaError.message('table index is NaN');
    }
    table.set(key, value);
  }

  /// `tostring` with `__tostring`.
  String tostring(Object? value) {
    final handler = metamethod(value, '__tostring');
    if (handler != null) {
      final results = call(handler, [value]);
      final first = results.isEmpty ? null : results.first;
      if (first is String) return first;
      if (first is double) return formatNumber(first);
      throw LuaError.message("'__tostring' must return a string");
    }
    return rawToString(value);
  }

  /// The `chunk:line:` prefix of the function [level] levels up the call
  /// stack of the running coroutine (1 is the innermost Lua function), or an
  /// empty string.
  String where(int level) {
    final co = _current;
    if (co == null || level < 1) return '';
    final index = co.frames.length - level;
    if (index < 0) return '';
    return _position(co.frames[index]);
  }

  String _position(Frame frame) {
    final closure = frame.closure;
    if (closure == null) return '';
    final proto = closure.proto;
    final pc = frame.pc > 0 ? frame.pc - 1 : 0;
    final line = pc < proto.lines.length ? proto.lines[pc] : proto.line;
    return '${chunkDisplayName(proto.chunkName)}:$line: ';
  }

  /// A traceback of the running coroutine.
  String traceback([String? message, int level = 1]) {
    final out = StringBuffer();
    if (message != null) out.writeln(message);
    out.write('stack traceback:');
    final co = _current;
    if (co != null) {
      var shown = 0;
      for (var i = co.frames.length - level; i >= 0 && shown < 22; i--) {
        final frame = co.frames[i];
        final closure = frame.closure;
        if (closure == null) {
          out.write('\n\t[C]: in function \'pcall\'');
        } else {
          final position = _position(frame);
          out.write('\n\t${position.substring(0, position.length - 1)} in function <${closure.proto.name}>');
        }
        shown++;
      }
    }
    return out.toString();
  }

  // -- The call machinery -------------------------------------------------

  String _callError(Object? value, Frame? caller) {
    final hint = caller == null ? null : _hintOf(caller);
    final suffix = hint == null ? '' : ' ($hint)';
    return 'attempt to call a ${luaTypeName(value)} value$suffix';
  }

  String? _hintOf(Frame frame) {
    final closure = frame.closure;
    if (closure == null || frame.pc == 0) return null;
    return closure.proto.hints[frame.pc - 1];
  }

  /// Calls the function at `stack[fnIndex]` with the [nargs] values above it.
  ///
  /// Returns [_pushed] if a Lua frame was pushed (the caller continues in it),
  /// [_completed] if the call finished and its results are on the stack,
  /// [_yielded] after a `coroutine.yield`, or [_preemptRequest] if a nested
  /// coroutine used up the time slice.
  int _precall(
    Coroutine co,
    int fnIndex,
    int nargs,
    int wanted,
    int xform,
    Frame? caller,
  ) {
    final stack = co.stack;
    var function = stack[fnIndex];
    while (function is! LuaFunction) {
      final handler = metamethod(function, '__call');
      if (handler == null) throw LuaError.message(_callError(function, caller));
      stack.insert(fnIndex, handler);
      nargs++;
      function = handler;
    }
    if (function is LuaClosure) {
      _enter(co, function, fnIndex, nargs, wanted, xform);
      return _pushed;
    }
    final native = function as NativeFunction;
    switch (native.kind) {
      case NativeKind.normal:
        final args = stack.sublist(fnIndex + 1, fnIndex + 1 + nargs);
        final results = native.impl(args);
        _deliver(co, fnIndex, results, wanted, xform);
        return _completed;
      case NativeKind.pcall:
        if (nargs < 1) {
          throw LuaError.message("bad argument #1 to 'pcall' (value expected)");
        }
        co.frames.add(Frame.marker(_kPcall, fnIndex, wanted, co.nativeDepth));
        final status = _precall(co, fnIndex + 1, nargs - 1, -1, _xformNone, null);
        if (status == _completed) _finishTopMarker(co);
        return status;
      case NativeKind.xpcall:
        if (nargs < 2) {
          throw LuaError.message(
            "bad argument #2 to 'xpcall' (value expected)",
          );
        }
        final handler = stack[fnIndex + 2];
        stack.removeAt(fnIndex + 2);
        final marker = Frame.marker(_kXpcall, fnIndex, wanted, co.nativeDepth)
          ..handler = handler;
        co.frames.add(marker);
        final status = _precall(co, fnIndex + 1, nargs - 2, -1, _xformNone, null);
        if (status == _completed) _finishTopMarker(co);
        return status;
      case NativeKind.yield:
        if (co.nativeDepth > 0) {
          throw LuaError.message(
            'attempt to yield across a C-call boundary',
          );
        }
        co.transfer = stack.sublist(fnIndex + 1, fnIndex + 1 + nargs);
        stack.length = fnIndex;
        co.yieldWanted = wanted;
        return _yielded;
      case NativeKind.resume:
        final target = nargs >= 1 ? stack[fnIndex + 1] : null;
        if (target is! Coroutine) {
          throw LuaError.message(
            "bad argument #1 to 'resume' (coroutine expected)",
          );
        }
        final args = target.status == CoStatus.preempted
            ? noValues
            : stack.sublist(fnIndex + 2, fnIndex + 1 + nargs);
        final outcome = resume(target, args);
        if (outcome is Preempted) return _preemptRequest;
        final List<Object?> results = switch (outcome) {
          Yielded(:final values) => [true, ...values],
          Finished(:final values) => [true, ...values],
          Failed(:final error) => [false, error.value],
          Preempted() => noValues,
        };
        _deliver(co, fnIndex, results, wanted, xform);
        return _completed;
      case NativeKind.wrap:
        final target = native.data! as Coroutine;
        final args = target.status == CoStatus.preempted
            ? noValues
            : stack.sublist(fnIndex + 1, fnIndex + 1 + nargs);
        final outcome = resume(target, args);
        if (outcome is Preempted) return _preemptRequest;
        final List<Object?> results = switch (outcome) {
          Yielded(:final values) => values,
          Finished(:final values) => values,
          Failed(:final error) => throw error,
          Preempted() => noValues,
        };
        _deliver(co, fnIndex, results, wanted, xform);
        return _completed;
    }
  }

  /// Replaces the call at [fnIndex] by its [results], adjusted to [wanted].
  void _deliver(
    Coroutine co,
    int fnIndex,
    List<Object?> results,
    int wanted,
    int xform,
  ) {
    final stack = co.stack;
    stack.length = fnIndex;
    stack.addAll(results);
    _adjust(stack, fnIndex, results.length, wanted);
    if (xform != _xformNone) {
      final value = stack.removeLast();
      stack.add(xform == _xformBool ? isTruthy(value) : !isTruthy(value));
    }
  }

  /// Fixes the number of values at the top of the stack: [n] values start at
  /// [fnIndex]; [wanted] is how many the caller wants (-1: all, followed by
  /// their count as an `int`).
  void _adjust(List<Object?> stack, int fnIndex, int n, int wanted) {
    if (wanted < 0) {
      stack.add(n);
    } else if (n > wanted) {
      stack.length = fnIndex + wanted;
    } else {
      for (var k = n; k < wanted; k++) {
        stack.add(null);
      }
    }
  }

  void _enter(
    Coroutine co,
    LuaClosure closure,
    int fnIndex,
    int nargs,
    int wanted,
    int xform,
  ) {
    final frames = co.frames;
    if (frames.length >= maxCallDepth) {
      throw LuaError.message('stack overflow');
    }
    final stack = co.stack;
    final proto = closure.proto;
    final base = fnIndex + 1;
    List<Object?> varargs = noValues;
    if (nargs > proto.numParams) {
      if (proto.isVararg) {
        varargs = stack.sublist(base + proto.numParams, base + nargs);
      }
      stack.length = base + proto.numParams;
    }
    stack.length = base + proto.maxLocals;
    frames.add(Frame.lua(closure, base, fnIndex, wanted, varargs, xform));
  }

  /// Completes the `pcall` marker on top of the frame list: its callee's
  /// results (and their count) are on the stack.
  void _finishTopMarker(Coroutine co) {
    final stack = co.stack;
    final marker = co.frames.removeLast();
    final count = stack.removeLast() as int;
    stack[marker.fnIndex] = true;
    _adjust(stack, marker.fnIndex, count + 1, marker.wanted);
  }

  void _finishMarkers(Coroutine co, int stopDepth) {
    final frames = co.frames;
    while (frames.length > stopDepth && !frames.last.isLua) {
      _finishTopMarker(co);
    }
  }

  void _return(Coroutine co, int count, int stopDepth) {
    final stack = co.stack;
    final frame = co.frames.removeLast();
    final fnIndex = frame.fnIndex;
    final start = stack.length - count;
    if (start != fnIndex) stack.setRange(fnIndex, fnIndex + count, stack, start);
    stack.length = fnIndex + count;
    _adjust(stack, fnIndex, count, frame.wanted);
    if (frame.xform != _xformNone) {
      final value = stack.removeLast();
      stack.add(frame.xform == _xformBool ? isTruthy(value) : !isTruthy(value));
    }
    _finishMarkers(co, stopDepth);
  }

  // -- Errors -----------------------------------------------------------------

  /// Looks for a `pcall` above [stopDepth] to deliver [error] to.
  bool _recover(Coroutine co, LuaError error, int stopDepth) {
    final frames = co.frames;
    if (error.needsPosition) {
      error.needsPosition = false;
      final value = error.value;
      if (value is String && frames.isNotEmpty && frames.last.isLua) {
        error.value = '${_position(frames.last)}$value';
      }
    }
    var index = frames.length - 1;
    while (index >= stopDepth && frames[index].isLua) {
      index--;
    }
    if (index < stopDepth) return false;
    final marker = frames[index];
    var value = error.value;
    if (marker.kind == _kXpcall && marker.handler != null) {
      try {
        final results = call(marker.handler, [value]);
        value = results.isEmpty ? null : results.first;
      } on LuaError catch (inner) {
        value = inner.value;
      }
    }
    frames.removeRange(index, frames.length);
    final stack = co.stack;
    stack.length = marker.fnIndex;
    co.nativeDepth = marker.nativeDepth;
    _deliver(co, marker.fnIndex, [false, value], marker.wanted, _xformNone);
    _finishMarkers(co, stopDepth);
    return true;
  }

  _Exec _run(Coroutine co, int stopDepth) {
    while (true) {
      try {
        return _loop(co, stopDepth);
      } on LuaError catch (e) {
        if (!_recover(co, e, stopDepth)) rethrow;
      } catch (e) {
        final converted = LuaError.message('Java Exception Thrown: $e');
        if (!_recover(co, converted, stopDepth)) throw converted;
      }
    }
  }

  // -- The interpreter loop -------------------------------------------------

  _Exec _loop(Coroutine co, int stopDepth) {
    final frames = co.frames;
    final stack = co.stack;
    if (frames.length <= stopDepth) return _Exec.done;
    var frame = frames.last;
    while (true) {
      if ((++_ticks & 0xFF) == 0) {
        if (abortRequested) {
          abortRequested = false;
          throw LuaError('Too long without yielding');
        }
        final now = clock.elapsedMicroseconds;
        if (now >= deadlineMicros) {
          if (_syncDepth == 0) return _Exec.preempted;
          if (now >= deadlineMicros + overshootMicros) {
            throw LuaError('Too long without yielding');
          }
        }
      }
      final pc = frame.pc;
      frame.pc = pc + 1;
      final code = frame.code;
      final at = pc * 3;
      final op = code[at];
      final a = code[at + 1];
      switch (op) {
        case Op.loadK:
          stack.add(frame.constants[a]);
        case Op.loadNil:
          stack.add(null);
        case Op.loadTrue:
          stack.add(true);
        case Op.loadFalse:
          stack.add(false);
        case Op.pop:
          stack.removeLast();
        case Op.dup:
          stack.add(stack.last);
        case Op.swap:
          final top = stack.length - 1;
          final tmp = stack[top];
          stack[top] = stack[top - 1];
          stack[top - 1] = tmp;
        case Op.getLocal:
          stack.add(stack[frame.base + a]);
        case Op.setLocal:
          stack[frame.base + a] = stack.removeLast();
        case Op.getCell:
          stack.add((stack[frame.base + a]! as Cell).value);
        case Op.setCell:
          (stack[frame.base + a]! as Cell).value = stack.removeLast();
        case Op.newCell:
          stack[frame.base + a] = Cell(stack.removeLast());
        case Op.wrapCell:
          stack[frame.base + a] = Cell(stack[frame.base + a]);
        case Op.getUpval:
          stack.add(frame.closure!.upvalues[a].value);
        case Op.setUpval:
          frame.closure!.upvalues[a].value = stack.removeLast();
        case Op.getGlobal:
          final env = frame.closure!.env;
          final name = frame.constants[a]! as String;
          final value = env.getString(name);
          if (value != null || env.meta == null) {
            stack.add(value);
          } else if (_indexSlow(co, frame, env, name)) {
            frame = frames.last;
          }
        case Op.setGlobal:
          final env = frame.closure!.env;
          final name = frame.constants[a]! as String;
          final value = stack.removeLast();
          if (env.meta == null) {
            env.setString(name, value);
          } else if (_setIndexSlow(co, env, name, value)) {
            frame = frames.last;
          }
        case Op.getEnv:
          stack.add(frame.closure!.env);
        case Op.getTable:
          final key = stack.removeLast();
          final object = stack.removeLast();
          if (object is LuaTable) {
            final value = object.get(key);
            if (value != null || object.meta == null) {
              stack.add(value);
              break;
            }
          }
          if (_indexSlow(co, frame, object, key)) frame = frames.last;
        case Op.getField:
          final key = frame.constants[a]! as String;
          final object = stack.removeLast();
          if (object is LuaTable) {
            final value = object.getString(key);
            if (value != null || object.meta == null) {
              stack.add(value);
              break;
            }
          }
          if (_indexSlow(co, frame, object, key)) frame = frames.last;
        case Op.setTable:
          final value = stack.removeLast();
          final key = stack.removeLast();
          final object = stack.removeLast();
          if (object is LuaTable && object.meta == null) {
            _rawSet(object, key, value);
            break;
          }
          if (_setIndexSlow(co, object, key, value, frame)) {
            frame = frames.last;
          }
        case Op.setField:
          final value = stack.removeLast();
          final key = frame.constants[a]! as String;
          final object = stack.removeLast();
          if (object is LuaTable && object.meta == null) {
            object.setString(key, value);
            break;
          }
          if (_setIndexSlow(co, object, key, value, frame)) {
            frame = frames.last;
          }
        case Op.newTable:
          stack.add(LuaTable());
        case Op.tableSetIndex:
          final value = stack.removeLast();
          (stack.last! as LuaTable).setInt(a, value);
        case Op.tableSetKey:
          final value = stack.removeLast();
          final key = stack.removeLast();
          _rawSet(stack.last! as LuaTable, key, value);
        case Op.tableSetField:
          final value = stack.removeLast();
          (stack.last! as LuaTable).setString(frame.constants[a]! as String, value);
        case Op.tableSetList:
          final count = stack.removeLast() as int;
          final start = stack.length - count;
          final table = stack[start - 1]! as LuaTable;
          for (var i = 0; i < count; i++) {
            table.setInt(a + i, stack[start + i]);
          }
          stack.length = start;
        case Op.add:
        case Op.sub:
        case Op.mul:
        case Op.div:
        case Op.mod:
        case Op.pow:
          final y = stack.removeLast();
          final x = stack.removeLast();
          if (x is double && y is double) {
            stack.add(_arithmetic(op - Op.add, x, y));
          } else if (_arithSlow(co, frame, op - Op.add, x, y)) {
            frame = frames.last;
          }
        case Op.concat:
          final y = stack.removeLast();
          final x = stack.removeLast();
          if (x is String && y is String) {
            if (x.length + y.length > maxStringLength) {
              throw LuaError.message('not enough memory');
            }
            stack.add(x + y);
          } else if (_concatSlow(co, frame, x, y)) {
            frame = frames.last;
          }
        case Op.eq:
        case Op.ne:
          final y = stack.removeLast();
          final x = stack.removeLast();
          final equal = x == y;
          if (!equal && x is LuaTable && y is LuaTable) {
            final handler = _eqHandler(x, y);
            if (handler != null) {
              if (_callMeta(
                co,
                handler,
                [x, y],
                1,
                op == Op.eq ? _xformBool : _xformNotBool,
              )) {
                frame = frames.last;
              }
              break;
            }
          }
          stack.add(op == Op.eq ? equal : !equal);
        case Op.lt:
        case Op.le:
        case Op.gt:
        case Op.ge:
          final y = stack.removeLast();
          final x = stack.removeLast();
          if (x is double && y is double) {
            stack.add(switch (op) {
              Op.lt => x < y,
              Op.le => x <= y,
              Op.gt => x > y,
              _ => x >= y,
            });
          } else if (x is String && y is String) {
            final order = x.compareTo(y);
            stack.add(switch (op) {
              Op.lt => order < 0,
              Op.le => order <= 0,
              Op.gt => order > 0,
              _ => order >= 0,
            });
          } else {
            final swap = op == Op.gt || op == Op.ge;
            final isLess = op == Op.lt || op == Op.gt;
            if (_compareSlow(
              co,
              isLess,
              swap ? y : x,
              swap ? x : y,
            )) {
              frame = frames.last;
            }
          }
        case Op.unm:
          final x = stack.removeLast();
          if (x is double) {
            stack.add(-x);
          } else if (_unaryMinusSlow(co, frame, x)) {
            frame = frames.last;
          }
        case Op.not:
          stack.add(!isTruthy(stack.removeLast()));
        case Op.len:
          final x = stack.removeLast();
          if (x is String) {
            stack.add(x.length.toDouble());
          } else if (_lengthSlow(co, frame, x)) {
            frame = frames.last;
          }
        case Op.jmp:
          frame.pc = a;
        case Op.jmpFalse:
          if (!isTruthy(stack.removeLast())) frame.pc = a;
        case Op.jmpTrue:
          if (isTruthy(stack.removeLast())) frame.pc = a;
        case Op.jmpFalseKeep:
          if (isTruthy(stack.last)) {
            stack.removeLast();
          } else {
            frame.pc = a;
          }
        case Op.jmpTrueKeep:
          if (isTruthy(stack.last)) {
            frame.pc = a;
          } else {
            stack.removeLast();
          }
        case Op.jmpNil:
          if (stack.removeLast() == null) frame.pc = a;
        case Op.call:
        case Op.callOpen:
          var nargs = a;
          if (op == Op.callOpen) nargs += stack.removeLast() as int;
          final fnIndex = stack.length - nargs - 1;
          final status = _precall(co, fnIndex, nargs, code[at + 2], _xformNone, frame);
          switch (status) {
            case _pushed:
              frame = frames.last;
            case _yielded:
              return _Exec.yielded;
            case _preemptRequest:
              frame.pc = pc;
              if (op == Op.callOpen) stack.add(nargs - a);
              return _Exec.preempted;
          }
        case Op.ret:
          _return(co, a, stopDepth);
          if (frames.length <= stopDepth) return _Exec.done;
          frame = frames.last;
        case Op.retOpen:
          _return(co, a + (stack.removeLast() as int), stopDepth);
          if (frames.length <= stopDepth) return _Exec.done;
          frame = frames.last;
        case Op.vararg:
          final varargs = frame.varargs;
          if (a >= 0) {
            for (var i = 0; i < a; i++) {
              stack.add(i < varargs.length ? varargs[i] : null);
            }
          } else {
            stack
              ..addAll(varargs)
              ..add(varargs.length);
          }
        case Op.closure:
          final proto = frame.closure!.proto.protos[a];
          final cells = <Cell>[];
          for (final upvalue in proto.upvalues) {
            cells.add(
              upvalue.fromLocal
                  ? stack[frame.base + upvalue.index]! as Cell
                  : frame.closure!.upvalues[upvalue.index],
            );
          }
          stack.add(LuaClosure(proto, cells, frame.closure!.env));
        case Op.forPrep:
          final slot = frame.base + a;
          final start = _forNumber(stack[slot], 'initial');
          final limit = _forNumber(stack[slot + 1], 'limit');
          final step = _forNumber(stack[slot + 2], 'step');
          if (step == 0) throw LuaError.message("'for' step is zero");
          stack[slot] = start;
          stack[slot + 1] = limit;
          stack[slot + 2] = step;
          if (step > 0 ? start <= limit : start >= limit) {
            stack[slot + 3] = start;
          } else {
            frame.pc = code[at + 2];
          }
        case Op.forLoop:
          final slot = frame.base + a;
          final step = stack[slot + 2]! as double;
          final index = (stack[slot]! as double) + step;
          final limit = stack[slot + 1]! as double;
          stack[slot] = index;
          if (step > 0 ? index <= limit : index >= limit) {
            stack[slot + 3] = index;
            frame.pc = code[at + 2];
          }
        default:
          throw StateError('Unknown opcode $op');
      }
    }
  }

  double _forNumber(Object? value, String what) {
    final number = _toNumber(value);
    if (number == null) {
      throw LuaError.message("'for' $what value must be a number");
    }
    return number;
  }

  // -- Slow paths of the instructions ---------------------------------------

  static double? _toNumber(Object? value) {
    if (value is double) return value;
    if (value is String) return parseLuaNumber(value);
    return null;
  }

  static double _arithmetic(int kind, double x, double y) => switch (kind) {
    0 => x + y,
    1 => x - y,
    2 => x * y,
    3 => x / y,
    4 => x - (x / y).floorToDouble() * y,
    _ => math.pow(x, y).toDouble(),
  };

  static const List<String> _arithEvents = [
    '__add',
    '__sub',
    '__mul',
    '__div',
    '__mod',
    '__pow',
  ];

  /// Calls [handler] with [args], leaving its first result on the stack (the
  /// instruction's result). Returns true if a Lua frame was pushed.
  bool _callMeta(
    Coroutine co,
    Object? handler,
    List<Object?> args,
    int wanted,
    int xform,
  ) {
    final stack = co.stack;
    final fnIndex = stack.length;
    stack
      ..add(handler)
      ..addAll(args);
    if (handler is NativeFunction) {
      _syncDepth++;
      try {
        return _precall(co, fnIndex, args.length, wanted, xform, null) == _pushed;
      } finally {
        _syncDepth--;
      }
    }
    return _precall(co, fnIndex, args.length, wanted, xform, null) == _pushed;
  }

  bool _arithSlow(Coroutine co, Frame frame, int kind, Object? x, Object? y) {
    final a = _toNumber(x);
    final b = _toNumber(y);
    if (a != null && b != null) {
      co.stack.add(_arithmetic(kind, a, b));
      return false;
    }
    final handler =
        metamethod(x, _arithEvents[kind]) ?? metamethod(y, _arithEvents[kind]);
    if (handler != null) return _callMeta(co, handler, [x, y], 1, _xformNone);
    final badFirst = a == null;
    throw LuaError.message(
      _operandError('perform arithmetic on', badFirst ? x : y, frame, badFirst),
    );
  }

  String _operandError(String action, Object? value, Frame frame, bool first) {
    final hint = _hintOf(frame);
    var description = '';
    if (hint != null) {
      final parts = hint.split('|');
      final text = parts.length == 2 ? parts[first ? 0 : 1] : hint;
      if (text.isNotEmpty) description = ' ($text)';
    }
    return 'attempt to $action a ${luaTypeName(value)} value$description';
  }

  bool _concatSlow(Coroutine co, Frame frame, Object? x, Object? y) {
    final xIsText = x is String || x is double;
    final yIsText = y is String || y is double;
    if (xIsText && yIsText) {
      final text = _text(x) + _text(y);
      if (text.length > maxStringLength) {
        throw LuaError.message('not enough memory');
      }
      co.stack.add(text);
      return false;
    }
    final handler = metamethod(x, '__concat') ?? metamethod(y, '__concat');
    if (handler != null) return _callMeta(co, handler, [x, y], 1, _xformNone);
    final badFirst = !xIsText;
    throw LuaError.message(
      _operandError('concatenate', badFirst ? x : y, frame, badFirst),
    );
  }

  static String _text(Object? value) =>
      value is double ? formatNumber(value) : value! as String;

  bool _unaryMinusSlow(Coroutine co, Frame frame, Object? x) {
    final number = _toNumber(x);
    if (number != null) {
      co.stack.add(-number);
      return false;
    }
    final handler = metamethod(x, '__unm');
    if (handler != null) return _callMeta(co, handler, [x, x], 1, _xformNone);
    throw LuaError.message(_operandError('perform arithmetic on', x, frame, true));
  }

  bool _lengthSlow(Coroutine co, Frame frame, Object? x) {
    final handler = metamethod(x, '__len');
    if (handler != null) return _callMeta(co, handler, [x], 1, _xformNone);
    if (x is LuaTable) {
      co.stack.add(x.length.toDouble());
      return false;
    }
    throw LuaError.message(_operandError('get length of', x, frame, true));
  }

  Object? _eqHandler(LuaTable x, LuaTable y) =>
      x.meta?.getString('__eq') ?? y.meta?.getString('__eq');

  bool _compareSlow(Coroutine co, bool isLess, Object? x, Object? y) {
    final event = isLess ? '__lt' : '__le';
    final handler = metamethod(x, event) ?? metamethod(y, event);
    if (handler != null) return _callMeta(co, handler, [x, y], 1, _xformBool);
    if (!isLess) {
      final fallback = metamethod(x, '__lt') ?? metamethod(y, '__lt');
      if (fallback != null) {
        return _callMeta(co, fallback, [y, x], 1, _xformNotBool);
      }
    }
    final tx = luaTypeName(x);
    final ty = luaTypeName(y);
    throw LuaError.message(
      tx == ty
          ? 'attempt to compare two $tx values'
          : 'attempt to compare $tx with $ty',
    );
  }

  /// `object[key]` where the fast path failed. Pushes the value, or sets up
  /// the call of an `__index` function. Returns true if a frame was pushed.
  bool _indexSlow(Coroutine co, Frame frame, Object? object, Object? key) {
    var target = object;
    for (var i = 0; i < 100; i++) {
      Object? handler;
      if (target is LuaTable) {
        final value = target.get(key);
        if (value != null) {
          co.stack.add(value);
          return false;
        }
        final meta = target.meta;
        handler = meta?.getString('__index');
        if (handler == null) {
          co.stack.add(null);
          return false;
        }
      } else {
        handler = metamethod(target, '__index');
        if (handler == null) {
          final hint = _hintOf(frame);
          final suffix = hint == null || hint.contains('|') ? '' : ' ($hint)';
          throw LuaError.message(
            'attempt to index a ${luaTypeName(target)} value$suffix',
          );
        }
      }
      if (handler is LuaFunction) {
        return _callMeta(co, handler, [target, key], 1, _xformNone);
      }
      target = handler;
    }
    throw LuaError.message("loop in gettable");
  }

  /// `object[key] = value` where the fast path failed. Returns true if a
  /// frame was pushed.
  bool _setIndexSlow(
    Coroutine co,
    Object? object,
    Object? key,
    Object? value, [
    Frame? frame,
  ]) {
    var target = object;
    for (var i = 0; i < 100; i++) {
      Object? handler;
      if (target is LuaTable) {
        final meta = target.meta;
        if (meta == null || target.get(key) != null) {
          _rawSet(target, key, value);
          return false;
        }
        handler = meta.getString('__newindex');
        if (handler == null) {
          _rawSet(target, key, value);
          return false;
        }
      } else {
        handler = metamethod(target, '__newindex');
        if (handler == null) {
          final hint = frame == null ? null : _hintOf(frame);
          final suffix = hint == null ? '' : ' ($hint)';
          throw LuaError.message(
            'attempt to index a ${luaTypeName(target)} value$suffix',
          );
        }
      }
      if (handler is LuaFunction) {
        final stack = co.stack;
        final fnIndex = stack.length;
        stack
          ..add(handler)
          ..add(target)
          ..add(key)
          ..add(value);
        return _precall(co, fnIndex, 3, 0, _xformNone, null) == _pushed;
      }
      target = handler;
    }
    throw LuaError.message("loop in settable");
  }
}
