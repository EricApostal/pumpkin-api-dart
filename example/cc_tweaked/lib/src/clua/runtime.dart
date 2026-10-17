// Lua values and host functions on top of the C Lua module.
// ignore_for_file: import_internal_library
import 'dart:_wasm';

import '../lua/lua.dart';
import 'native.dart' as native;

/// A table, function or thread in the Lua state of a machine that is kept by
/// reference (in the registry) instead of being copied.
final class LuaRef extends LuaForeign {
  final int state;
  final int reference;

  const LuaRef(super.typeName, this.state, this.reference);
}

/// A native function the machine registered.
final class _HostFunction {
  final NativeImpl impl;
  final bool byReference;
  final Object owner;

  _HostFunction(this.impl, this.byReference, this.owner);
}

/// Called by the hook of a running machine: 0 to go on, 1 to abort, 2 to
/// yield.
typedef HookHandler = int Function(int thread);

/// The C Lua module of the program, shared by all machines.
final class CLua {
  CLua._();

  static bool _initialized = false;

  static final List<_HostFunction?> _functions = [null];
  static final List<int> _free = [];

  /// The hook of the machine whose Lua code is running.
  static HookHandler? activeHook;

  /// The Lua thread that called the host function being run, or 0.
  static int currentThread = 0;

  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    native.initialize();
  }

  /// Makes [impl] callable from Lua and returns its id.
  static int register(NativeImpl impl, Object owner, {bool byReference = false}) {
    final entry = _HostFunction(impl, byReference, owner);
    if (_free.isNotEmpty) {
      final id = _free.removeLast();
      _functions[id] = entry;
      return id;
    }
    _functions.add(entry);
    return _functions.length - 1;
  }

  /// Forgets every function registered by [owner].
  static void unregisterAll(Object owner) {
    for (var id = 1; id < _functions.length; id++) {
      if (identical(_functions[id]?.owner, owner)) {
        _functions[id] = null;
        _free.add(id);
      }
    }
  }

  /// Handles a call from the C module; see `host_call` in `cc_lua.c`.
  static int dispatch(int id, int l) {
    if (id == 0) return activeHook?.call(l) ?? 0;
    final function = id < _functions.length ? _functions[id] : null;
    if (function == null) {
      native.pushString(l, 'host function is gone');
      return _errorWithPosition;
    }
    final caller = currentThread;
    currentThread = l;
    try {
      final count = native.top(l);
      final args = <Object?>[
        for (var i = 1; i <= count; i++) readValue(l, i, byReference: function.byReference),
      ];
      native.setTop(l, 0);
      final results = function.impl(args);
      for (final value in results) {
        pushValue(l, value, function.owner);
      }
      return results.length;
    } on LuaError catch (e) {
      native.setTop(l, 0);
      pushValue(l, e.value, function.owner);
      return e.needsPosition && e.value is String ? _errorWithPosition : _error;
    } catch (e) {
      native.setTop(l, 0);
      native.pushString(l, 'internal error: $e');
      return _errorWithPosition;
    } finally {
      currentThread = caller;
    }
  }

  static const int _errorWithPosition = -1;
  static const int _error = -2;

  // -- Values --------------------------------------------------------------

  /// Reads the value at [index] of [l]. Tables are copied, unless
  /// [byReference] is set, in which case tables and functions become
  /// [LuaRef]s.
  static Object? readValue(
    int l,
    int index, {
    bool byReference = false,
    int depth = 0,
  }) {
    switch (native.typeOf(l, index)) {
      case native.typeNil:
        return null;
      case native.typeBoolean:
        return native.toBoolean(l, index);
      case native.typeNumber:
        return native.toNumber(l, index);
      case native.typeString:
        return native.toStringOrNull(l, index);
      case native.typeTable:
        if (byReference) return _reference(l, index, 'table');
        return _readTable(l, index, depth);
      case native.typeFunction:
        return byReference ? _reference(l, index, 'function') : const LuaForeign('function');
      default:
        return byReference ? _reference(l, index, 'thread') : const LuaForeign('thread');
    }
  }

  static LuaRef _reference(int l, int index, String typeName) {
    native.pushValue(l, index);
    return LuaRef(typeName, l, native.reference(l, native.registryIndex));
  }

  static LuaTable _readTable(int l, int index, int depth) {
    final table = LuaTable();
    if (depth > 16) return table;
    final absolute = index < 0 && index > native.registryIndex ? native.top(l) + index + 1 : index;
    native.pushNil(l);
    while (native.next(l, absolute)) {
      final key = readValue(l, -2, depth: depth + 1);
      final value = readValue(l, -1, depth: depth + 1);
      if (key != null && !(key is double && key.isNaN)) {
        table.set(key, value);
      }
      native.setTop(l, -2);
    }
    return table;
  }

  /// Pushes [value] on the stack of [l]. Native functions belong to [owner].
  static void pushValue(int l, Object? value, Object owner) {
    switch (value) {
      case null:
        native.pushNil(l);
      case bool():
        native.pushBoolean(l, value);
      case double():
        native.pushNumber(l, value);
      case int():
        native.pushNumber(l, value.toDouble());
      case String():
        native.pushString(l, value);
      case LuaTable():
        _pushTable(l, value, owner);
      case NativeFunction():
        native.pushHostFunction(l, register(value.impl, owner));
      case LuaRef():
        native.rawGetInt(l, native.registryIndex, value.reference);
        native.unreference(l, native.registryIndex, value.reference);
      default:
        native.pushNil(l);
    }
  }

  static void _pushTable(int l, LuaTable table, Object owner) {
    native.createTable(l, table.length, table.hashSize);
    var entry = table.next(null);
    while (entry != null) {
      pushValue(l, entry.$1, owner);
      pushValue(l, entry.$2, owner);
      native.rawSet(l, -3);
      entry = table.next(entry.$1);
    }
  }
}

/// The only function the C module imports (`host.call`); the component linker
/// routes it here (see `WasmCoreModuleAsset`).
@pragma('wasm:export', 'host_call')
WasmI32 hostCall(WasmI32 id, WasmI32 thread, WasmI32 unused1, WasmI32 unused2) {
  return WasmI32.fromInt(CLua.dispatch(id.toIntUnsigned(), thread.toIntUnsigned()));
}
