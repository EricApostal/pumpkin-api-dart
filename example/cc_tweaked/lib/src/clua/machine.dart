// The Lua machine of one computer on the C Lua module: the same job as
// `LuaMachine`, run by PUC Lua 5.2 compiled to WebAssembly.
import '../lua/lua.dart';
import '../machine/lua_host.dart';
import '../machine/lua_machine.dart';
import 'native.dart' as native;
import 'runtime.dart';

/// The instructions between two calls of the hook.
const int _hookInterval = 4000;

final class CLuaMachine implements Machine, LuaHost {
  final int _state;
  final int _main;
  final Stopwatch _clock = Stopwatch()..start();
  final int _hardLimitMicros;

  String? _eventFilter;
  bool _closed = false;
  bool _abortRequested = false;
  int _deadlineMicros = 0;
  int _hardDeadlineMicros = 0;

  CLuaMachine._(this._state, this._main, this._hardLimitMicros);

  /// Creates a machine that will run [bios] with [apis] as globals.
  ///
  /// [hardLimitMicros] bounds one resume of code that cannot be paused
  /// (anything but the main coroutine's own code); it is aborted like CC
  /// aborts code that does not yield.
  factory CLuaMachine.create({
    required String bios,
    required Map<String, LuaTable> apis,
    required String hostString,
    required String defaultSettings,
    Map<String, HostApiBuilder> vmApis = const {},
    int hardLimitMicros = 7000000,
    int memoryLimit = 128 << 20,
  }) {
    CLua.ensureInitialized();
    final state = native.newState(memoryLimit);
    if (state == 0) throw const MachineException('Could not create the Lua state');
    final main = native.newThread(state);
    final machine = CLuaMachine._(state, main, hardLimitMicros);

    try {
      native.getGlobal(state, '__cc_set_root');
      native.pushValue(state, 1);
      native.pcall(state, 1, 0);
      machine._setGlobal('_HOST', hostString);
      machine._setGlobal('_CC_DEFAULT_SETTINGS', defaultSettings);
      for (final entry in apis.entries) {
        machine._setGlobal(entry.key, entry.value);
      }
      for (final entry in vmApis.entries) {
        machine._setGlobal(entry.key, entry.value(machine));
      }

      final code = native.loadString(main, bios, '@bios.lua');
      if (code != native.statusOk) {
        throw MachineException(
          native.toStringOrNull(main, -1) ?? 'Could not load bios.lua',
        );
      }
    } catch (_) {
      machine.close();
      rethrow;
    }
    native.setCountHook(state, _hookInterval);
    return machine;
  }

  void _setGlobal(String name, Object? value) {
    CLua.pushValue(_state, value, this);
    native.setGlobal(_state, name);
  }

  @override
  void setSlice(int micros) {
    _deadlineMicros = _clock.elapsedMicroseconds + micros;
  }

  @override
  void requestAbort() => _abortRequested = true;

  int _onHook(int thread) {
    if (_abortRequested) return 1;
    final now = _clock.elapsedMicroseconds;
    if (now >= _hardDeadlineMicros) return 1;
    if (now >= _deadlineMicros && thread == _main) return 2;
    return 0;
  }

  @override
  MachineResult handleEvent(String? name, List<Object?> args) {
    if (_closed) throw StateError('The machine has been closed');
    final filter = _eventFilter;
    if (filter != null && name != null && name != filter && name != 'terminate') {
      return MachineResult.ok;
    }

    var count = 0;
    if (name != null) {
      CLua.pushValue(_main, name, this);
      count++;
      for (final arg in args) {
        CLua.pushValue(_main, arg, this);
        count++;
      }
    }

    _hardDeadlineMicros = _clock.elapsedMicroseconds + _hardLimitMicros;
    final previousHook = CLua.activeHook;
    CLua.activeHook = _onHook;
    final int code;
    try {
      code = native.resume(_main, _state, count);
    } finally {
      CLua.activeHook = previousHook;
    }

    if (code == native.statusYield) {
      if (native.takePreempted()) {
        native.setTop(_main, 0);
        return MachineResult.pause;
      }
      final first = native.top(_main) == 0 ? null : CLua.readValue(_main, 1);
      native.setTop(_main, 0);
      _eventFilter = first is String ? first : null;
      return MachineResult.ok;
    }
    if (code == native.statusOk) {
      close();
      return const MachineResult(MachineStatus.error);
    }
    final message = _errorMessage(CLua.readValue(_main, -1));
    close();
    return MachineResult(MachineStatus.error, message);
  }

  static String _errorMessage(Object? value) {
    if (value is String) return value;
    if (value is double) return formatNumber(value);
    return 'error object is a ${luaTypeName(value)} value';
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    native.closeState(_state);
    CLua.unregisterAll(this);
  }

  // -- LuaHost ---------------------------------------------------------------

  @override
  Object load(String source, String chunkName) {
    final code = native.loadString(_state, source, chunkName);
    if (code != native.statusOk) {
      final message = native.toStringOrNull(_state, -1) ?? 'syntax error';
      native.setTop(_state, -2);
      throw MachineException(message);
    }
    final function = CLua.readValue(_state, -1, byReference: true)!;
    native.setTop(_state, -2);
    return function;
  }

  @override
  List<Object?> call(Object function, List<Object?> args) {
    final base = native.top(_state);
    CLua.pushValue(_state, function, this);
    for (final arg in args) {
      CLua.pushValue(_state, arg, this);
    }
    final code = native.pcall(_state, args.length, -1);
    if (code != native.statusOk) {
      final message = _errorMessage(CLua.readValue(_state, -1));
      native.setTop(_state, base);
      throw MachineException(message);
    }
    final count = native.top(_state) - base;
    final results = <Object?>[
      for (var i = 1; i <= count; i++)
        CLua.readValue(_state, base + i, byReference: true),
    ];
    native.setTop(_state, base);
    return results;
  }

  @override
  String where(int level) {
    final thread = CLua.currentThread;
    if (thread == 0) return '';
    native.pushWhere(thread, level);
    final text = native.toStringOrNull(thread, -1) ?? '';
    native.setTop(thread, -2);
    return text;
  }
}
