// The Lua machine of one computer: a VM, its APIs and the main coroutine that
// runs `bios.lua`, driven by events (`CobaltLuaMachine` in CC: Tweaked).
//
// CraftOS is one coroutine that yields to the host whenever it waits for an
// event (`os.pullEventRaw` is `coroutine.yield`). The host resumes it with the
// next event; the value it yielded is the *filter*: events with another name
// do not wake it (except `terminate`).
import '../lua/lua.dart';

/// The ways running the machine can end.
enum MachineStatus {
  /// The program yielded and waits for the next event.
  ok,

  /// The time slice ran out; resume to continue.
  pause,

  /// The machine failed and must shut down.
  error,
}

/// The result of [LuaMachine.handleEvent].
final class MachineResult {
  final MachineStatus status;

  /// The error message, if any. Null for a generic failure (the main
  /// coroutine returned).
  final String? message;

  const MachineResult(this.status, [this.message]);

  static const MachineResult ok = MachineResult(MachineStatus.ok);
  static const MachineResult pause = MachineResult(MachineStatus.pause);
}

/// The bios could not be loaded.
final class MachineException implements Exception {
  final String message;

  const MachineException(this.message);

  @override
  String toString() => message;
}

final class LuaMachine {
  final LuaVm vm;
  final Coroutine _main;
  String? _eventFilter;
  bool _closed = false;

  LuaMachine._(this.vm, this._main);

  /// Creates a machine that will run [bios] with [apis] as globals (and as
  /// loaded modules).
  factory LuaMachine.create({
    required ProtoCache cache,
    required String bios,
    required Map<String, LuaTable> apis,
    required String hostString,
    required String defaultSettings,
  }) {
    final vm = LuaVm(cache: cache);
    installStandardLibrary(vm);
    vm.globals
      ..setString('_HOST', hostString)
      ..setString('_CC_DEFAULT_SETTINGS', defaultSettings);
    for (final entry in apis.entries) {
      vm.globals.setString(entry.key, entry.value);
    }
    final LuaClosure function;
    try {
      function = vm.load(bios, '@bios.lua');
    } on LuaSyntaxError catch (e) {
      throw MachineException(e.message);
    }
    final main = vm.newCoroutine(function);
    vm.rootCoroutine = main;
    return LuaMachine._(vm, main);
  }

  /// Gives the machine until [micros] microseconds from now to run.
  void setSlice(int micros) {
    vm.deadlineMicros = vm.clock.elapsedMicroseconds + micros;
  }

  /// Makes the running Lua code fail with "Too long without yielding".
  void requestAbort() => vm.abortRequested = true;

  /// Resumes the machine. [name] is null to start it or to continue after a
  /// pause. Events the program is not waiting for are dropped.
  MachineResult handleEvent(String? name, List<Object?> args) {
    if (_closed) throw StateError('The machine has been closed');
    final filter = _eventFilter;
    if (filter != null && name != null && name != filter && name != 'terminate') {
      return MachineResult.ok;
    }
    final resumeArgs = name == null ? const <Object?>[] : <Object?>[name, ...args];
    final outcome = vm.resume(_main, resumeArgs);
    switch (outcome) {
      case Preempted():
        return MachineResult.pause;
      case Yielded(:final values):
        final first = values.isEmpty ? null : values.first;
        _eventFilter = first is String ? first : null;
        return MachineResult.ok;
      case Finished():
        close();
        return const MachineResult(MachineStatus.error);
      case Failed(:final error):
        close();
        return MachineResult(MachineStatus.error, errorMessage(error));
    }
  }

  /// The message shown for [error]: a string, or a note for other values.
  static String errorMessage(LuaError error) {
    final value = error.value;
    if (value is String) return value;
    if (value is double) return formatNumber(value);
    return 'error object is a ${luaTypeName(value)} value';
  }

  void close() => _closed = true;
}
