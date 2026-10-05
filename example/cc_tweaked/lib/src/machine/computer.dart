// A computer: its terminal, redstone, file system, peripherals and event
// queue, and the state machine that boots, runs and stops its Lua machine
// (`Computer` and `ComputerExecutor` in CC: Tweaked).
//
// Everything runs on the server thread. Instead of a thread per computer with
// a 7 second timeout, the host calls [Computer.tick] once per server tick with
// a budget; the Lua VM stops after any instruction when its time slice is used
// up and continues on the next tick. A program that never yields is still
// aborted after the same 7 seconds of *execution time* CC allows.
import 'dart:collection';

import '../lua/lua.dart';
import 'api/fs_api.dart';
import 'api/os_api.dart';
import 'api/peripheral_api.dart';
import 'api/redstone_api.dart';
import 'api/term_api.dart';
import 'craftos.dart';
import 'filesystem.dart';
import 'input.dart';
import 'lua_machine.dart';
import 'peripheral.dart';
import 'redstone.dart';
import 'side.dart';
import 'terminal.dart';

/// The kinds of computer. Advanced computers have colour and mouse support.
enum ComputerFamily { normal, advanced }

/// What a computer looks like from outside, for blocks and items.
enum ComputerState { off, on, blinking }

/// Limits and settings shared by all computers.
final class MachineConfig {
  /// How long one computer may run per server tick, in microseconds.
  final int sliceMicros;

  /// How long all computers together may run per server tick.
  final int tickBudgetMicros;

  /// How long a program may run without yielding before it is told to stop
  /// ("Too long without yielding"), in microseconds. CC: 7 seconds.
  final int timeoutMicros;

  /// How much longer it gets to react before the computer is shut down. CC:
  /// 1.5 seconds.
  final int abortGraceMicros;

  /// The quota of a computer's disk in bytes. CC: 1 000 000.
  final int diskQuota;

  /// How many files a program may keep open. CC: 128.
  final int maxOpenFiles;

  /// The terminal size of a computer. CC: 51 x 19.
  final int terminalWidth;
  final int terminalHeight;

  /// Settings every computer starts with, as `name=value,name=value`.
  final String defaultSettings;

  /// The most events waiting for one computer; further ones are dropped.
  final int eventQueueLimit;

  const MachineConfig({
    this.sliceMicros = 3000,
    this.tickBudgetMicros = 12000,
    this.timeoutMicros = 7000000,
    this.abortGraceMicros = 1500000,
    this.diskQuota = 1000000,
    this.maxOpenFiles = 128,
    this.terminalWidth = 51,
    this.terminalHeight = 19,
    this.defaultSettings = '',
    this.eventQueueLimit = 256,
  });
}

/// What computers need from the server they run on.
abstract interface class ComputerServices {
  CraftOsImage get image;

  ProtoCache get cache;

  MachineConfig get config;

  /// A monotonic clock in microseconds.
  int get nowMicros;

  /// The in-game time of day in hours (0 to 24) and the in-game day (from 1).
  double get timeOfDay;

  int get day;

  /// The writable disk of computer [id].
  WritableMount createRootMount(int id, int quota);

  void log(String message);
}

/// The least number of ticks between two starts of a computer (CC: 50).
const int _startDelayTicks = 50;

/// The most events one computer handles per tick.
const int _maxEventsPerTick = 100;

enum _Command { turnOn, shutdown, reboot, abortTimeout }

final class _Event {
  final String name;
  final List<Object?> args;

  const _Event(this.name, this.args);
}

final class _SideAccess implements PeripheralAccess {
  final Computer _computer;
  final ComputerSide _side;

  _SideAccess(this._computer, this._side);

  @override
  int get computerId => _computer.id;

  @override
  String get attachmentName => _side.luaName;

  @override
  void queueEvent(String name, List<Object?> args) => _computer.queueEvent(name, args);
}

final class _Attachment {
  final Peripheral peripheral;
  final _SideAccess access;
  bool attached = false;

  _Attachment(this.peripheral, this.access);
}

final class Computer implements OsHost, PeripheralLookup {
  final int id;
  final ComputerFamily family;
  final ComputerServices _services;
  final Terminal terminal;
  final RedstoneState redstone = RedstoneState();

  /// Called when the label or the power state changed (to save them).
  void Function()? onChanged;

  String? _label;
  bool _on = false;
  bool _closed = false;
  bool _startRequested = false;
  int _ticksSinceStart = -1;
  _Command? _command;
  final Queue<_Event> _events = Queue();
  bool _wasPaused = false;
  int _executionMicros = 0;
  bool _softAborted = false;

  FileSystem? _fileSystem;
  LuaMachine? _machine;
  late final OsApi _os = OsApi(this);
  final List<_Attachment?> _attachments = List<_Attachment?>.filled(6, null);
  final Map<int, int> _timers = {};
  int _nextTimer = 0;

  Computer({
    required this.id,
    required this.family,
    required ComputerServices services,
    String? label,
  }) : _services = services,
       terminal = Terminal(
         services.config.terminalWidth,
         services.config.terminalHeight,
         family == ComputerFamily.advanced,
       ) {
    _label = label;
  }

  // -- State ----------------------------------------------------------------

  bool get isOn => _on;

  /// Whether the computer is being removed and accepts no more commands.
  bool get isClosed => _closed;

  /// Off, on, or on with a blinking cursor.
  ComputerState get state {
    if (!_on) return ComputerState.off;
    final blinking =
        terminal.cursorBlink &&
        terminal.cursorX >= 0 &&
        terminal.cursorX < terminal.width &&
        terminal.cursorY >= 0 &&
        terminal.cursorY < terminal.height;
    return blinking ? ComputerState.blinking : ComputerState.on;
  }

  @override
  int get computerId => id;

  @override
  String? get label => _label;

  @override
  set label(String? value) {
    if (_label == value) return;
    _label = value;
    onChanged?.call();
  }

  @override
  double get timeOfDay => _services.timeOfDay;

  @override
  int get day => _services.day;

  /// The file system while the computer is on.
  FileSystem? get fileSystem => _fileSystem;

  // -- Commands -------------------------------------------------------------

  /// Asks the computer to start. It starts on the next tick, but not within
  /// 50 ticks of its last start.
  void turnOn() => _startRequested = true;

  @override
  void shutdown() {
    if (_closed || !_on) return;
    _command ??= _Command.shutdown;
  }

  @override
  void reboot() {
    if (_closed || !_on) return;
    _command ??= _Command.reboot;
  }

  /// Stops the computer for good (it is being removed or the server stops).
  void unload() {
    if (_closed) return;
    if (_on) _stop();
    _closed = true;
    _events.clear();
    _command = null;
  }

  @override
  void queueEvent(String name, List<Object?> args) {
    if (!_on || _closed || _command != null) return;
    if (_events.length >= _services.config.eventQueueLimit) return;
    _events.add(_Event(name, [for (final arg in args) copyPlain(arg)]));
  }

  /// Queues an event whose arguments are handed to the program as they are:
  /// unlike [queueEvent] they are not copied, so they may hold functions (the
  /// `file_transfer` event).
  void queueRawEvent(String name, List<Object?> args) {
    if (!_on || _closed || _command != null) return;
    if (_events.length >= _services.config.eventQueueLimit) return;
    _events.add(_Event(name, args));
  }

  /// The input handler for a player using this computer's terminal.
  ComputerInput createInput() => ComputerInput(queueEvent, terminal);

  // -- Timers ---------------------------------------------------------------

  @override
  int startTimer(int ticks) {
    _timers[_nextTimer] = ticks;
    return _nextTimer++;
  }

  @override
  void cancelTimer(int id) => _timers.remove(id);

  void _tickTimers() {
    for (final id in _timers.keys.toList()) {
      final left = _timers[id]! - 1;
      if (left <= 0) {
        _timers.remove(id);
        queueEvent('timer', [id.toDouble()]);
      } else {
        _timers[id] = left;
      }
    }
  }

  // -- Peripherals ----------------------------------------------------------

  /// Attaches [peripheral] to [side] (null removes it). The computer gets a
  /// `peripheral` or `peripheral_detach` event if it is on.
  void setPeripheral(ComputerSide side, Peripheral? peripheral) {
    final existing = _attachments[side.index];
    if (existing != null && peripheral != null && existing.peripheral.sameAs(peripheral)) {
      return;
    }
    if (existing != null) {
      if (existing.attached) existing.peripheral.detach(existing.access);
      _attachments[side.index] = null;
      queueEvent('peripheral_detach', [side.luaName]);
    }
    if (peripheral != null) {
      final attachment = _Attachment(peripheral, _SideAccess(this, side));
      _attachments[side.index] = attachment;
      if (_on) {
        peripheral.attach(attachment.access);
        attachment.attached = true;
      }
      queueEvent('peripheral', [side.luaName]);
    }
  }

  /// The peripheral on [side], if any.
  Peripheral? peripheralOn(ComputerSide side) => _attachments[side.index]?.peripheral;

  @override
  (Peripheral, PeripheralAccess)? attached(ComputerSide side) {
    final attachment = _attachments[side.index];
    if (attachment == null || !attachment.attached) return null;
    return (attachment.peripheral, attachment.access);
  }

  void _attachAll() {
    for (final attachment in _attachments) {
      if (attachment != null && !attachment.attached) {
        attachment.peripheral.attach(attachment.access);
        attachment.attached = true;
      }
    }
  }

  void _detachAll() {
    for (final attachment in _attachments) {
      if (attachment != null && attachment.attached) {
        attachment.peripheral.detach(attachment.access);
        attachment.attached = false;
      }
    }
  }

  // -- The server tick --------------------------------------------------------

  /// Advances the computer by one server tick. It may run Lua for at most
  /// [budgetMicros] microseconds; with 0 it only does its bookkeeping.
  /// Returns the microseconds spent running Lua.
  int tick(int budgetMicros) {
    if (_closed) return 0;
    if (_ticksSinceStart >= 0 && _ticksSinceStart <= _startDelayTicks) {
      _ticksSinceStart++;
    }
    if (_startRequested &&
        (_ticksSinceStart < 0 || _ticksSinceStart > _startDelayTicks)) {
      _startRequested = false;
      if (!_on) {
        _ticksSinceStart = 0;
        _command ??= _Command.turnOn;
      }
    }
    if (_on) {
      _os.update();
      _tickTimers();
    }
    if (redstone.pollInputChanged()) queueEvent('redstone', const []);
    return _work(budgetMicros);
  }

  int _work(int budgetMicros) {
    var used = 0;
    var handled = 0;
    while (true) {
      final command = _command;
      if (command != null) {
        _command = null;
        _wasPaused = false;
        switch (command) {
          case _Command.turnOn:
            if (!_on) _start();
          case _Command.shutdown:
            if (_on) {
              terminal.reset();
              _stop();
            }
          case _Command.reboot:
            if (_on) {
              terminal.reset();
              _stop();
              _startRequested = true;
            }
          case _Command.abortTimeout:
            if (_on) {
              _displayFailure('Error running computer', 'Too long without yielding');
              _stop();
            }
        }
        continue;
      }
      if (!_on) {
        _events.clear();
        return used;
      }
      if (!_wasPaused && _events.isEmpty) return used;
      final remaining = budgetMicros - used;
      if (remaining <= 0 || handled >= _maxEventsPerTick) return used;
      handled++;
      used += _run(remaining);
    }
  }

  /// Resumes the machine with the next event (or continues a paused one) for
  /// at most [budget] microseconds. Returns the time it ran.
  int _run(int budget) {
    final machine = _machine!;
    final config = _services.config;
    final slice = budget < config.sliceMicros ? budget : config.sliceMicros;
    final event = _wasPaused ? null : _events.removeFirst();
    if (event != null) {
      _executionMicros = 0;
      _softAborted = false;
    }
    final start = _services.nowMicros;
    machine.setSlice(slice);
    final MachineResult result;
    try {
      result = machine.handleEvent(event?.name, event?.args ?? const []);
    } catch (e) {
      _services.log('Computer $id crashed the machine: $e');
      _displayFailure('Error running computer', 'An internal error occurred, see logs.');
      _stop();
      return _services.nowMicros - start;
    }
    final elapsed = _services.nowMicros - start;
    _executionMicros += elapsed;
    switch (result.status) {
      case MachineStatus.ok:
        _wasPaused = false;
      case MachineStatus.pause:
        _wasPaused = true;
        if (_executionMicros >= config.timeoutMicros + config.abortGraceMicros) {
          _command = _Command.abortTimeout;
        } else if (_executionMicros >= config.timeoutMicros && !_softAborted) {
          _softAborted = true;
          machine.requestAbort();
        }
      case MachineStatus.error:
        _displayFailure('Error running computer', result.message);
        _stop();
    }
    return elapsed;
  }

  // -- Boot and shutdown ----------------------------------------------------

  FileSystem? _createFileSystem() {
    final config = _services.config;
    try {
      final fileSystem = FileSystem(maxOpenFiles: config.maxOpenFiles);
      fileSystem.mount('hdd', '', _services.createRootMount(id, config.diskQuota));
      final rom = _services.image.rom;
      if (rom != null) fileSystem.mount('rom', 'rom', rom);
      return fileSystem;
    } on FileSystemException catch (e) {
      _services.log('Computer $id cannot mount its disk: $e');
      _displayFailure('Cannot mount computer system', null);
      return null;
    }
  }

  void _start() {
    terminal.reset();
    _events.clear();
    _timers.clear();
    final fileSystem = _createFileSystem();
    if (fileSystem == null) return;
    _fileSystem = fileSystem;
    _os.startup();
    _attachAll();
    final machine = _createMachine();
    if (machine == null) {
      _stop();
      return;
    }
    _machine = machine;
    _on = true;
    _wasPaused = true;
    _executionMicros = 0;
    _softAborted = false;
    onChanged?.call();
  }

  LuaMachine? _createMachine() {
    final image = _services.image;
    final config = _services.config;
    final apis = <String, LuaTable>{
      'term': buildTermApi(terminal),
      'fs': buildFsApi(() => _fileSystem!),
      'peripheral': buildPeripheralApi(this),
    };
    final redstoneApi = buildRedstoneApi(redstone);
    apis['rs'] = redstoneApi;
    apis['redstone'] = redstoneApi;
    apis['os'] = _os.build();
    try {
      return LuaMachine.create(
        cache: _services.cache,
        bios: image.bios,
        apis: apis,
        hostString: 'ComputerCraft ${image.modVersion ?? '1.120.3'} (Minecraft 26.3)',
        defaultSettings: config.defaultSettings,
      );
    } on MachineException catch (e) {
      _displayFailure('Error loading bios.lua', e.message);
      return null;
    }
  }

  void _stop() {
    final wasOn = _on;
    _on = false;
    _wasPaused = false;
    _events.clear();
    _timers.clear();
    _machine?.close();
    _machine = null;
    _os.shutdown();
    _detachAll();
    redstone.clearOutput();
    _fileSystem?.close();
    _fileSystem = null;
    if (wasOn) onChanged?.call();
  }

  void _displayFailure(String message, String? extra) {
    terminal.reset();
    if (terminal.isColour) terminal.setTextColour(14);
    terminal.write(message);
    if (extra != null) {
      terminal.setCursorPos(0, terminal.cursorY + 1);
      terminal.write(extra);
    }
  }
}
