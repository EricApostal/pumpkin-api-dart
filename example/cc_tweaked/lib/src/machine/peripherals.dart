// The peripherals this package implements, after the Java ones of the same
// name (`shared/peripheral/**`, `shared/computer/blocks/ComputerPeripheral`).
//
// Each class cites its Java source and keeps the Lua-visible surface (method
// names, argument checks and messages) as close as the host allows; the
// differences are noted where they exist. The classes are binding-free: the
// plugin drives them (the world side is `plugin/world_peripherals.dart`).
import 'dart:math' as math;
import 'dart:typed_data';

import '../lua/lua.dart';
import 'api/os_api.dart' show copyPlain;
import 'api/term_api.dart';
import 'media.dart';
import 'peripheral.dart';
import 'redstone.dart';
import 'side.dart';
import 'terminal.dart';

/// The normalised form of a label (`StringUtil.normaliseLabel`): the first 32
/// characters, with a character that may not appear in a label replaced by `?`.
String normaliseLabel(String text) {
  final length = text.length < 32 ? text.length : 32;
  final out = StringBuffer();
  for (var i = 0; i < length; i++) {
    final c = text.codeUnitAt(i);
    out.write(c >= 32 && c != 127 ? text[i] : '?');
  }
  return out.toString();
}

// -- Monitors -----------------------------------------------------------------

/// A monitor made of [width] by [height] blocks. Its terminal size follows
/// from the text scale, exactly as `ServerMonitor.rebuild` computes it.
final class MonitorPeripheral extends MethodPeripheral {
  static const double _border = 2.0 / 16.0;
  static const double _margin = 0.5 / 16.0;
  static const double _pixelScale = 1.0 / 64.0;

  final bool advanced;
  final Set<PeripheralAccess> _computers = {};
  final void Function()? onChanged;

  int _blocksWide;
  int _blocksHigh;

  /// The text scale in half steps: 1 is 0.5, 10 is 5.
  int _textScale = 2;
  late final Terminal terminal;

  MonitorPeripheral(this._blocksWide, this._blocksHigh, {required this.advanced, this.onChanged}) {
    final size = _terminalSize();
    terminal = Terminal(size.$1, size.$2, advanced, onChanged: onChanged);
    final termMethods = LuaTable();
    addTermMethods(termMethods, () => terminal);
    var entry = termMethods.next(null);
    while (entry != null) {
      final name = entry.$1! as String;
      final function = entry.$2! as NativeFunction;
      method(name, (computer, args) => function.impl(args));
      entry = termMethods.next(entry.$1);
    }
    method('setTextScale', (computer, args) {
      final a = Args('setTextScale', args);
      final value = a.number(0);
      if (value.isNaN || value.isInfinite) a.wrongType(0, 'number');
      final scale = (value * 2).truncate();
      if (scale < 1 || scale > 10) {
        throw LuaError.message('Expected number in range 0.5-5');
      }
      _setTextScale(scale);
      return noValues;
    });
    method('getTextScale', (computer, args) => one(_textScale / 2));
  }

  /// The size of the monitor wall in blocks (`MonitorBlockEntity.getWidth`).
  int get blocksWide => _blocksWide;
  int get blocksHigh => _blocksHigh;

  /// Whether a computer has wrapped this monitor: Java builds the terminal the
  /// first time a computer looks at the monitor (`peripheral()` →
  /// `createServerTerminal`), and `monitor_client` carries no terminal while
  /// none has.
  bool get hasComputers => _computers.isNotEmpty;

  (int, int) _terminalSize() {
    final scale = _textScale * 0.5;
    final inner = 2.0 * (_border + _margin);
    final width = ((_blocksWide - inner) / (scale * 6.0 * _pixelScale)).round();
    final height = ((_blocksHigh - inner) / (scale * 9.0 * _pixelScale)).round();
    return (width < 1 ? 1 : width, height < 1 ? 1 : height);
  }

  void _setTextScale(int scale) {
    if (scale == _textScale) return;
    _textScale = scale;
    _rebuild();
  }

  /// Changes the size of the monitor wall in blocks (`MonitorBlockEntity.resize`
  /// + `ServerMonitor.rebuild`).
  void resizeBlocks(int blocksWide, int blocksHigh) {
    if (blocksWide == _blocksWide && blocksHigh == _blocksHigh) return;
    _blocksWide = blocksWide;
    _blocksHigh = blocksHigh;
    _rebuild();
  }

  void _rebuild() {
    final size = _terminalSize();
    if (size.$1 == terminal.width && size.$2 == terminal.height) return;
    terminal
      ..resize(size.$1, size.$2)
      ..clear();
    for (final computer in _computers) {
      computer.queueEvent('monitor_resize', [computer.attachmentName]);
    }
  }

  /// A player touched character cell ([x], [y]) (1-based) of an advanced
  /// monitor (`MonitorBlockEntity.monitorTouched`).
  void touch(int x, int y) {
    if (!advanced) return;
    for (final computer in _computers) {
      computer.queueEvent('monitor_touch', [computer.attachmentName, x.toDouble(), y.toDouble()]);
    }
  }

  @override
  String get type => 'monitor';

  @override
  void attach(PeripheralAccess computer) => _computers.add(computer);

  @override
  void detach(PeripheralAccess computer) => _computers.remove(computer);
}

// -- Wireless modems ----------------------------------------------------------

/// Wireless modems that can reach each other.
final class WirelessNetwork {
  final List<WirelessModem> _modems = [];

  void _add(WirelessModem modem) => _modems.add(modem);

  void _remove(WirelessModem modem) => _modems.remove(modem);

  void _transmit(WirelessModem sender, int channel, int replyChannel, Object? payload) {
    for (final receiver in List<WirelessModem>.of(_modems)) {
      if (identical(receiver, sender) || !receiver._open.contains(channel)) continue;
      final distance = sender._distanceTo(receiver);
      if (distance != null && !sender._inRange(distance, receiver)) continue;
      for (final computer in receiver._computers) {
        computer.queueEvent('modem_message', [
          computer.attachmentName,
          channel.toDouble(),
          replyChannel.toDouble(),
          copyPlain(payload),
          distance ?? 0.0,
        ]);
      }
    }
  }
}

/// A wireless modem with its open channels.
final class WirelessModem extends MethodPeripheral {
  static const int _maxOpenChannels = 128;

  final WirelessNetwork network;
  final bool advanced;

  /// How far the modem reaches, in blocks (ignored by advanced modems).
  final double range;

  /// Where the modem is, if known; without positions every message arrives.
  /// A turtle's modem follows its turtle.
  (double, double, double)? position;

  final Set<int> _open = {};
  final Set<PeripheralAccess> _computers = {};

  WirelessModem({
    required this.network,
    required this.advanced,
    this.range = 64,
    this.position,
  }) {
    int channel(Args args, int index) {
      final value = args.integer(index);
      if (value < 0 || value > 65535) {
        throw LuaError.message('Expected number in range 0-65535');
      }
      return value;
    }

    method('open', (computer, list) {
      final c = channel(Args('open', list), 0);
      if (!_open.contains(c) && _open.length >= _maxOpenChannels) {
        throw LuaError.message('Too many open channels');
      }
      _open.add(c);
      return noValues;
    });
    method('isOpen', (computer, list) => one(_open.contains(channel(Args('isOpen', list), 0))));
    method('close', (computer, list) {
      _open.remove(channel(Args('close', list), 0));
      return noValues;
    });
    method('closeAll', (computer, list) {
      _open.clear();
      return noValues;
    });
    method('transmit', (computer, list) {
      final args = Args('transmit', list);
      final target = channel(args, 0);
      final reply = channel(args, 1);
      network._transmit(this, target, reply, args[2]);
      return noValues;
    });
    method('isWireless', (computer, list) => one(true));
  }

  double? _distanceTo(WirelessModem other) {
    final a = position;
    final b = other.position;
    if (a == null || b == null) return null;
    final dx = a.$1 - b.$1;
    final dy = a.$2 - b.$2;
    final dz = a.$3 - b.$3;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  bool _inRange(double distance, WirelessModem receiver) =>
      advanced || receiver.advanced || distance <= range;

  @override
  String get type => 'modem';

  @override
  void attach(PeripheralAccess computer) {
    _computers.add(computer);
    network._add(this);
  }

  @override
  void detach(PeripheralAccess computer) {
    _computers.remove(computer);
    if (_computers.isEmpty) network._remove(this);
  }
}

// -- Wired modems and their network -------------------------------------------

/// One wired element on a network: the peripheral a block exposes to the
/// network under [name] (`WiredModemLocalPeripheral`: `<type>_<id>`, the type
/// being the peripheral's own type and the id a per-type counter).
final class WiredElement {
  /// The name other computers see, e.g. `computer_3`; null when this element
  /// has no peripheral (a modem with nothing attached).
  final String? name;

  /// What a remote computer gets when it wraps [name].
  final Peripheral? peripheral;

  const WiredElement(this.name, this.peripheral);
}

/// A wired network: the wired modems that are connected to each other
/// (`WiredNetwork`/`WiredNode` in CC). The plugin makes one per connected
/// component of cables and modems.
final class WiredNetwork {
  final Set<WiredModem> _modems = {};

  void _add(WiredModem modem) => _modems.add(modem);

  void _remove(WiredModem modem) => _modems.remove(modem);

  /// The elements of the network except [self]'s own (`getRemotePeripherals`).
  List<(String, Peripheral)> remoteOf(WiredModem self) {
    final out = <(String, Peripheral)>[];
    for (final modem in _modems) {
      final element = modem.element;
      final name = element.name;
      final peripheral = element.peripheral;
      if (name == null || peripheral == null) continue;
      if (identical(modem, self)) continue;
      out.add((name, peripheral));
    }
    return out;
  }

  /// `transmit` of a wired modem: the message reaches the computers of the
  /// other modems on the network, at distance 0 (`PacketNetwork.transmit…`,
  /// the wired network has no range).
  void transmit(WiredModem sender, int channel, int replyChannel, Object? payload) {
    for (final modem in List<WiredModem>.of(_modems)) {
      if (identical(modem, sender)) continue;
      if (!modem._open.contains(channel)) continue;
      for (final computer in modem._computers) {
        computer.queueEvent('modem_message', [
          computer.attachmentName,
          channel.toDouble(),
          replyChannel.toDouble(),
          copyPlain(payload),
          0.0,
        ]);
      }
    }
  }
}

/// A wired modem: a modem whose messages travel over the cables it is attached
/// to, and which can wrap the peripherals of the other blocks on that network
/// (`WiredModemPeripheral`, type `modem` with the additional type
/// `peripheral_hub`).
final class WiredModem extends MethodPeripheral {
  static const int _maxOpenChannels = 128;

  /// The network this modem is on. The plugin moves a modem between networks
  /// when the cables around it change ([rejoin]).
  WiredNetwork network;

  /// What this element exposes to the network, set by the plugin: the
  /// peripheral of the block the modem is attached to, with its network name.
  WiredElement element = const WiredElement(null, null);

  /// Whether this is the advanced modem (it has no effect on a wired modem,
  /// which always reaches the whole network: `isWireless` is false).
  final bool advanced;

  final Set<int> _open = {};
  final Set<PeripheralAccess> _computers = {};

  /// The remote peripherals each computer has wrapped, by name
  /// (`WiredModemPeripheral.peripheralWrappers`).
  final Map<PeripheralAccess, Map<String, _RemotePeripheral>> _remotes = Map.identity();

  WiredModem({required this.network, this.advanced = false}) {
    int channel(Args args, int index) {
      final value = args.integer(index);
      if (value < 0 || value > 65535) {
        throw LuaError.message('Expected number in range 0-65535');
      }
      return value;
    }

    method('open', (computer, list) {
      final c = channel(Args('open', list), 0);
      if (!_open.contains(c) && _open.length >= _maxOpenChannels) {
        throw LuaError.message('Too many open channels');
      }
      _open.add(c);
      return noValues;
    });
    method('isOpen', (computer, list) => one(_open.contains(channel(Args('isOpen', list), 0))));
    method('close', (computer, list) {
      _open.remove(channel(Args('close', list), 0));
      return noValues;
    });
    method('closeAll', (computer, list) {
      _open.clear();
      return noValues;
    });
    method('transmit', (computer, list) {
      final args = Args('transmit', list);
      final target = channel(args, 0);
      final reply = channel(args, 1);
      network.transmit(this, target, reply, args[2]);
      return noValues;
    });
    method('isWireless', (computer, list) => one(false));

    // The `peripheral_hub` methods.
    method('getNamesRemote', (computer, list) {
      final remotes = _wrappers(computer);
      final names = LuaTable();
      var i = 1;
      for (final name in remotes.keys) {
        names.setInt(i++, name);
      }
      return one(names);
    });
    method('isPresentRemote', (computer, list) {
      final args = Args('isPresentRemote', list);
      return one(_wrappers(computer).containsKey(args.string(0)));
    });
    method('getTypeRemote', (computer, list) {
      final args = Args('getTypeRemote', list);
      final remote = _wrappers(computer)[args.string(0)];
      if (remote == null) return one(null);
      return <Object?>[remote.peripheral.type, ...remote.peripheral.additionalTypes];
    });
    method('hasTypeRemote', (computer, list) {
      final args = Args('hasTypeRemote', list);
      final remote = _wrappers(computer)[args.string(0)];
      if (remote == null) return one(null);
      final type = args.string(1);
      return one(remote.peripheral.type == type || remote.peripheral.additionalTypes.contains(type));
    });
    method('getMethodsRemote', (computer, list) {
      final args = Args('getMethodsRemote', list);
      final remote = _wrappers(computer)[args.string(0)];
      if (remote == null) return one(null);
      final methods = LuaTable();
      var i = 1;
      for (final name in remote.peripheral.methodNames) {
        methods.setInt(i++, name);
      }
      return one(methods);
    });
    method('callRemote', (computer, list) {
      final args = Args('callRemote', list);
      final name = args.string(0);
      final method = args.string(1);
      final remote = _wrappers(computer)[name];
      if (remote == null) throw LuaError.message('No peripheral: $name');
      return remote.peripheral.call(remote.access, method, list.sublist(2));
    });
    method('getNameLocal', (computer, list) {
      final name = element.name;
      return name == null ? noValues : one(name);
    });
  }

  Map<String, _RemotePeripheral> _wrappers(PeripheralAccess computer) =>
      _remotes.putIfAbsent(computer, () => {});

  /// Moves this modem to [network] (the cables around it changed): it leaves the
  /// old one and tells both sides' computers that their remote peripherals
  /// changed (`WiredElement#connect`/`disconnect`).
  void rejoin(WiredNetwork network) {
    if (identical(this.network, network)) return;
    final previous = this.network;
    previous._remove(this);
    this.network = network;
    network._add(this);
    for (final modem in previous._modems.toList()) {
      modem.networkChanged();
    }
  }

  /// The element this modem exposes to the network changed, or the network
  /// gained or lost an element: the remotes the computers have wrapped are
  /// brought up to date, with a `peripheral`/`peripheral_detach` event
  /// (`WiredModemElement.attachPeripheral`/`detachPeripheral`).
  void networkChanged() {
    for (final entry in _remotes.entries.toList()) {
      final computer = entry.key;
      final wrappers = entry.value;
      final wanted = {for (final (name, peripheral) in network.remoteOf(this)) name: peripheral};

      for (final name in wrappers.keys.toList()) {
        if (wanted.containsKey(name)) continue;
        wrappers.remove(name)?.detach();
        computer.queueEvent('peripheral_detach', [name]);
      }
      for (final wanted_ in wanted.entries) {
        if (wrappers.containsKey(wanted_.key)) continue;
        final remote = _RemotePeripheral(wanted_.key, wanted_.value, computer);
        wrappers[wanted_.key] = remote;
        remote.attach();
        computer.queueEvent('peripheral', [wanted_.key]);
      }
    }
  }

  @override
  String get type => 'modem';

  @override
  Set<String> get additionalTypes => const {'peripheral_hub'};

  @override
  void attach(PeripheralAccess computer) {
    _computers.add(computer);
    network._add(this);
    // A modem that comes on to a network gives its computers the remotes.
    _remotes.putIfAbsent(computer, () => {});
    networkChanged();
  }

  @override
  void detach(PeripheralAccess computer) {
    _computers.remove(computer);
    final wrappers = _remotes.remove(computer);
    if (wrappers != null) {
      for (final remote in wrappers.values) {
        remote.detach();
      }
    }
    if (_computers.isEmpty) {
      network._remove(this);
      // The other modems of the network lose this element.
      for (final modem in network._modems.toList()) {
        modem.networkChanged();
      }
    }
  }
}

/// A peripheral of the network that one computer has wrapped
/// (`WiredModemPeripheral.RemotePeripheralWrapper`): the remote peripheral is
/// attached with an access that carries the computer's id, the remote's name
/// and the computer's file system (so a disk drive on the network can mount).
final class _RemotePeripheral {
  final String name;
  final Peripheral peripheral;
  final PeripheralAccess computer;
  late final _RemoteAccess access = _RemoteAccess(computer, name);

  _RemotePeripheral(this.name, this.peripheral, this.computer);

  void attach() => peripheral.attach(access);

  void detach() => peripheral.detach(access);
}

/// `IComputerAccess` of a wrapped remote peripheral: the events and the mounts
/// go to the computer that wrapped it, under the remote's name.
final class _RemoteAccess implements PeripheralAccess {
  final PeripheralAccess _computer;
  final String _name;

  _RemoteAccess(this._computer, this._name);

  @override
  int get computerId => _computer.computerId;

  @override
  String get attachmentName => _name;

  @override
  void queueEvent(String name, List<Object?> args) => _computer.queueEvent(name, args);

  @override
  String? mountDisk(Object mount) => _computer.mountDisk(mount);

  @override
  void unmountDisk(String path) => _computer.unmountDisk(path);
}

// -- Speaker ------------------------------------------------------------------

/// A sound the speaker plays (`SpeakerPeripheral.PendingSound`): the id of a
/// sound event, its volume (0 to 3) and its pitch.
final class SpeakerSound {
  final String id;
  final double volume;
  final double pitch;

  const SpeakerSound(this.id, this.volume, this.pitch);
}

/// An encoded chunk of audio, with the state of the DFPWM codec before it
/// (`SpeakerAudioClientMessage`).
final class SpeakerAudioChunk {
  final int charge;
  final int strength;
  final bool previousBit;
  final Uint8List audio;
  final double volume;

  const SpeakerAudioChunk(this.charge, this.strength, this.previousBit, this.audio, this.volume);
}

/// Where a speaker sends what it plays: the `speaker_play`, `speaker_audio`,
/// `speaker_stop` and `speaker_move` payloads of the players that can hear it
/// (Java: `ServerNetworking.sendToAllAround`/`sendToAllTracking`).
abstract interface class SpeakerSink {
  /// Play the sound event [sound] (`speaker_play`).
  void play(SpeakerSound sound);

  /// Play one block of encoded audio (`speaker_audio`).
  void playAudio(SpeakerAudioChunk chunk);

  /// Stop everything (`speaker_stop`).
  void stop();

  /// The speaker moved and the listeners should be told (`speaker_move`).
  void moved();
}

/// The DFPWM encoder and the playback state of a speaker (`DfpwmState`): the
/// samples of `playAudio` are encoded here, and the state of the codec travels
/// with each chunk so the client can decode from any point.
final class SpeakerAudioState {
  static const int _precision = 10;

  /// The client buffers half a second of audio; below that we send more.
  static const int _clientBufferNanos = 500 * 1000 * 1000;

  int charge = 0;
  int strength = 0;
  bool previousBit = false;

  bool _unplayed = true;
  int _clientEndTime = 0;
  double _pendingVolume = 1;
  SpeakerAudioChunk? _pending;

  /// Encodes [size] samples of [levels] (a Lua table, 1-based, each between
  /// -128 and 127) and holds them for [shouldSend]. Returns false when a chunk
  /// is still waiting (Java: `pushBuffer`).
  bool pushBuffer(LuaTable levels, int size, double? volume, int nowNanos) {
    if (_pending != null) return false;

    final outSize = size ~/ 8;
    final buffer = Uint8List(outSize);
    final initialCharge = charge;
    final initialStrength = strength;
    final initialPreviousBit = previousBit;

    for (var i = 0; i < outSize; i++) {
      var thisByte = 0;
      for (var j = 1; j <= 8; j++) {
        final value = levels.getInt(i * 8 + j);
        final level = value is double ? value.toInt() : (value is int ? value : 0);
        if (level < -128 || level > 127) {
          throw LuaError.message('table item #${i * 8 + j} must be between -128 and 127');
        }

        final currentBit = level > charge || (level == charge && charge == 127);
        final target = currentBit ? 127 : -128;

        // q' <- q + (s * (t - q) + 128)/256
        var nextCharge = charge + ((strength * (target - charge) + (1 << (_precision - 1))) >> _precision);
        if (nextCharge == charge && nextCharge != target) nextCharge += currentBit ? 1 : -1;

        final z = currentBit == previousBit ? (1 << _precision) - 1 : 0;

        var nextStrength = strength;
        if (strength != z) nextStrength += currentBit == previousBit ? 1 : -1;
        if (nextStrength < 2 << (_precision - 8)) nextStrength = 2 << (_precision - 8);

        charge = nextCharge;
        strength = nextStrength;
        previousBit = currentBit;

        thisByte = (thisByte >> 1) + (currentBit ? 128 : 0);
      }
      buffer[i] = thisByte;
    }

    _pending = SpeakerAudioChunk(initialCharge, initialStrength, initialPreviousBit, buffer, 0);
    _pendingVolume = clampVolume(volume ?? _pendingVolume);
    return true;
  }

  /// Whether the client needs another chunk (`shouldSendPending`).
  bool shouldSend(int nowNanos) => _pending != null && nowNanos >= _clientEndTime - _clientBufferNanos;

  /// Takes the waiting chunk and works out when the client will need more
  /// (`pullPending`).
  SpeakerAudioChunk pull(int nowNanos) {
    final chunk = _pending!;
    _pending = null;
    final nanos = chunk.audio.length * 8 * _nanosPerSecond ~/ SpeakerPeripheral.sampleRate;
    final base = nowNanos > _clientEndTime ? nowNanos : _clientEndTime;
    _clientEndTime = base + nanos;
    _unplayed = false;
    return SpeakerAudioChunk(chunk.charge, chunk.strength, chunk.previousBit, chunk.audio, _pendingVolume);
  }

  /// Whether the client may still be playing (`isPlaying`).
  bool isPlaying(int nowNanos) => _unplayed || _clientEndTime >= nowNanos;

  /// Drops any waiting chunk (`dfpwmState = null` on a stop).
  void clear() => _pending = null;
}

const int _nanosPerSecond = 1000 * 1000 * 1000;

/// Plays a bitmap of the volume arguments: `clampVolume`.
double clampVolume(double volume) => volume < 0 ? 0 : (volume > 3 ? 3 : volume);

/// The vanilla note block instruments to the sound they play
/// (`NoteBlockInstrument`, `block.note_block.<name>`).
const Map<String, String> _instruments = {
  'harp': 'minecraft:block.note_block.harp',
  'basedrum': 'minecraft:block.note_block.basedrum',
  'snare': 'minecraft:block.note_block.snare',
  'hat': 'minecraft:block.note_block.hat',
  'bass': 'minecraft:block.note_block.bass',
  'flute': 'minecraft:block.note_block.flute',
  'bell': 'minecraft:block.note_block.bell',
  'guitar': 'minecraft:block.note_block.guitar',
  'chime': 'minecraft:block.note_block.chime',
  'xylophone': 'minecraft:block.note_block.xylophone',
  'iron_xylophone': 'minecraft:block.note_block.iron_xylophone',
  'cow_bell': 'minecraft:block.note_block.cow_bell',
  'didgeridoo': 'minecraft:block.note_block.didgeridoo',
  'bit': 'minecraft:block.note_block.bit',
  'banjo': 'minecraft:block.note_block.banjo',
  'pling': 'minecraft:block.note_block.pling',
};

/// A speaker (`SpeakerPeripheral`): a note block instrument, a sound named by
/// the program, or DFPWM audio the program streams.
final class SpeakerPeripheral extends MethodPeripheral {
  /// Number of samples a second of a DFPWM track has.
  static const int sampleRate = 48000;

  static const int _maxSoundLength = 512;
  static const int _maxNotesPerTick = 8;
  static const int _maxAudioSamples = 128 * 1024;

  final SpeakerSink sink;

  /// Where the speaker is; null for a speaker that never moves (a pocket
  /// computer's, a `/cc` attached one). A turtle's follows the turtle: its
  /// world layer updates it every tick.
  (double, double, double)? position;

  final Set<PeripheralAccess> _computers = {};
  final List<SpeakerSound> _pendingNotes = [];
  SpeakerSound? _pendingSound;
  SpeakerAudioState? _audio;
  bool _shouldStop = false;

  /// What the last `playSound`/`playNote` used, for `madeSound`.
  int _lastPlayTick = 0;
  int _tick = 0;

  /// Whether this speaker has ever played anything: a stop is sent to the
  /// listeners only then (Java guards it with `lastPosition != null`, and a
  /// speaker of this port may have no position at all).
  bool _played = false;

  /// The last position a move was sent for (`syncedPosition`).
  (double, double, double)? _lastPosition;
  int _lastPositionTick = 0;

  /// The last clock [update] saw; the Lua methods that need "now" (the client
  /// audio buffer estimate) read it.
  int _lastNow = 0;

  SpeakerPeripheral({required this.sink, this.position}) {
    _addMethods();
  }

  void _addMethods() {
    method('playNote', (computer, list) {
      final args = Args('playNote', list);
      // Java: `Optional<Double> volumeA`/`pitchA` with the defaults 1.0/1.0, so
      // an absent argument is not an error.
      final volume = clampVolume(_finite(args.optNumber(1, 1), args, 1));
      final pitch = _finite(args.optNumber(2, 1), args, 2);

      final name = args.string(0).toLowerCase();
      final soundId = _instruments[name];
      if (soundId == null) throw LuaError.message('Invalid instrument, "${args.string(0)}"!');

      if (_pendingNotes.length >= _maxNotesPerTick) return one(false);
      _pendingNotes.add(SpeakerSound(soundId, volume, math.pow(2.0, (pitch - 12.0) / 12.0).toDouble()));
      return one(true);
    });

    method('playSound', (computer, list) {
      final args = Args('playSound', list);
      final volume = clampVolume(_finite(args.optNumber(1, 1), args, 1));
      final pitch = _finite(args.optNumber(2, 1), args, 2);

      final name = args.string(0);
      if (!_isIdentifier(name)) throw LuaError.message('bad argument #1 (malformed sound name)');
      if (name.length > _maxSoundLength) throw LuaError.message('bad argument #1 (sound name is too long)');

      // Java refuses a jukebox song here (`BuiltInRegistries.SOUND_EVENT` and
      // the `JUKEBOX_SONG` registry), which this server cannot read: a music
      // disc may therefore be played through a speaker. Documented.
      if (_pendingSound != null || (_audio?.isPlaying(_lastNow) ?? false)) return one(false);
      _audio = null;
      _pendingSound = SpeakerSound(name.contains(':') ? name : 'minecraft:$name', volume, pitch);
      return one(true);
    });

    method('playAudio', (computer, list) {
      final args = Args('playAudio', list);
      final audio = args.table(0);
      _finite(args.optNumber(1, 0), args, 1);

      final length = audio.length;
      if (length <= 0) throw LuaError.message('Cannot play empty audio');
      if (length > _maxAudioSamples) throw LuaError.message('Audio data is too large');

      final state = _audio = _audio ?? SpeakerAudioState();
      _pendingSound = null;
      return one(state.pushBuffer(audio, length, args.isNone(1) ? null : args.number(1), _lastNow));
    });

    method('stop', (computer, list) {
      _shouldStop = true;
      return noValues;
    });
  }

  /// One server tick (`SpeakerPeripheral.update`): plays what the programs
  /// queued and, when the client's buffer runs low, the next audio chunk (with
  /// a `speaker_audio_empty` event on the computers).
  void update(int nowNanos) {
    _lastNow = nowNanos;
    _tick++;

    if (_pendingNotes.isNotEmpty) {
      for (final sound in _pendingNotes) {
        _lastPlayTick = _tick;
        _played = true;
        sink.play(sound);
      }
      _pendingNotes.clear();
    }

    var shouldStop = _shouldStop;
    var sound = _pendingSound;
    var audio = _audio;
    _pendingSound = null;
    if (shouldStop) {
      audio = _audio = null;
      sound = null;
      _shouldStop = false;
    }

    if (shouldStop) {
      if (_played) {
        _played = false;
        _lastPosition = null;
        sink.stop();
        return;
      }
    }

    if (sound != null) {
      _lastPlayTick = _tick;
      sink.play(sound);
      _syncedPosition();
    } else if (audio != null && audio.shouldSend(nowNanos)) {
      sink.playAudio(audio.pull(nowNanos));
      _syncedPosition();
      for (final computer in _computers) {
        computer.queueEvent('speaker_audio_empty', [computer.attachmentName]);
      }
    }

    // Tell the listeners when the speaker moved (`speaker_move`), at most once
    // a second.
    final position = this.position;
    final last = _lastPosition;
    if (last != null && position != null && _tick - _lastPositionTick >= 20) {
      final dx = position.$1 - last.$1;
      final dy = position.$2 - last.$2;
      final dz = position.$3 - last.$3;
      if (dx * dx + dy * dy + dz * dz > 0.1 * 0.1) {
        sink.moved();
        _syncedPosition();
      }
    }
  }

  double _finite(double value, Args args, int index) {
    if (value.isNaN || value.isInfinite) args.wrongType(index, 'number');
    return value;
  }

  static bool _isIdentifier(String name) {
    if (name.isEmpty) return false;
    final parts = name.split(':');
    if (parts.length > 2) return false;
    for (final part in parts) {
      if (part.isEmpty || !RegExp(r'^[a-z0-9_.\-/]+$').hasMatch(part)) return false;
    }
    return true;
  }

  void _syncedPosition() {
    _played = true;
    _lastPosition = position;
    _lastPositionTick = _tick;
  }

  /// Whether the speaker played a note in the last second or is playing audio
  /// (`madeSound`).
  bool madeSound(int nowNanos) => _tick - _lastPlayTick <= 20 || (_audio?.isPlaying(nowNanos) ?? false);

  @override
  String get type => 'speaker';

  @override
  void attach(PeripheralAccess computer) => _computers.add(computer);

  @override
  void detach(PeripheralAccess computer) => _computers.remove(computer);
}

// -- Disk drives and their media ----------------------------------------------

/// The drive behind a [DiskDrivePeripheral]: the disk it holds and what
/// ejecting does (Java: `DiskDriveBlockEntity`).
///
/// `playAudio`/`stopAudio` are **not** here: playing a record sends the
/// `play_record` payload, which carries the jukebox song from the datapack
/// registry `minecraft:jukebox_song`; the host does not expose that registry,
/// so a record's song cannot be named. A program that calls them gets "No such
/// method" rather than a call that quietly does nothing.
abstract interface class DiskDrive {
  /// The disk in the drive, or null when it is empty (`getMedia`).
  Media? get media;

  /// `ejectDisk`: the disk leaves the drive (the world drops it in front).
  void eject();
}

/// A disk drive (`DiskDrivePeripheral`, type `drive`).
final class DiskDrivePeripheral extends MethodPeripheral {
  final DiskDrive drive;

  /// The mount of the disk in each computer, by the path the computer gave it
  /// (`DiskDriveBlockEntity.MountInfo.mountPath`).
  final Map<PeripheralAccess, String> _mounts = Map.identity();

  DiskDrivePeripheral(this.drive) {
    method('isDiskPresent', (computer, list) => one(drive.media != null));
    method('getDiskLabel', (computer, list) {
      final media = drive.media;
      return media == null ? one(null) : one(media.label);
    });
    method('setDiskLabel', (computer, list) {
      final args = Args('setDiskLabel', list);
      final label = args.isNone(0) ? null : normaliseLabel(args.string(0));
      final media = drive.media;
      if (media == null) return noValues;
      if (!media.setLabel(label)) throw LuaError.message('Disk label cannot be changed');
      return noValues;
    });
    method('hasData', (computer, list) => one(_mounts[computer] != null));
    method('getMountPath', (computer, list) {
      final path = _mounts[computer];
      return path == null ? one(null) : one(path);
    });
    method('hasAudio', (computer, list) => one(drive.media?.hasAudio ?? false));
    method('getAudioTitle', (computer, list) {
      final media = drive.media;
      if (media == null) return one(false);
      return one(media.audioTitle);
    });
    method('ejectDisk', (computer, list) {
      drive.eject();
      return noValues;
    });
    method('getDiskID', (computer, list) {
      final id = drive.media?.diskId;
      return id == null ? one(null) : one(id.toDouble());
    });
  }

  /// The disk changed (it was put in or ejected): every computer unmounts the
  /// old one and mounts the new (`DiskDriveBlockEntity.updateMedia`).
  void mediaChanged() {
    for (final computer in _mounts.keys.toList()) {
      _unmount(computer);
    }
    for (final computer in _computers) {
      _mount(computer);
    }
  }

  final Set<PeripheralAccess> _computers = {};

  void _mount(PeripheralAccess computer) {
    final media = drive.media;
    final mount = media?.createDataMount();
    if (mount == null) return;
    final path = computer.mountDisk(mount);
    if (path != null) _mounts[computer] = path;
  }

  void _unmount(PeripheralAccess computer) {
    final path = _mounts.remove(computer);
    if (path != null) computer.unmountDisk(path);
  }

  @override
  String get type => 'drive';

  @override
  void attach(PeripheralAccess computer) {
    _computers.add(computer);
    _mount(computer);
  }

  @override
  void detach(PeripheralAccess computer) {
    _computers.remove(computer);
    _unmount(computer);
  }
}

// -- Printer ------------------------------------------------------------------

/// A page of a printed item (`PrintoutData`): a title and 21 lines of 25
/// characters with their colour codes.
final class Printout {
  final String title;
  final List<(String, String)> lines;

  const Printout(this.title, this.lines);
}

/// What a printer does with a finished page (`PrinterBlockEntity.outputPage`):
/// the world puts the printed page item in the printer's output tray.
typedef PrinterPageOutput = void Function(Printout page);

/// A printer (`PrinterPeripheral`, type `printer`). The page, the ink and the
/// paper are this object's (Java keeps them in the block entity, whose
/// inventory this server cannot have: the plugin fills the ink and the paper
/// when a player puts them in).
final class PrinterPeripheral extends MethodPeripheral {
  /// `PrintoutData.LINE_LENGTH` and `LINES_PER_PAGE`.
  static const int pageWidth = 25;
  static const int pageHeight = 21;

  final PrinterPageOutput onPage;

  late final Terminal page = Terminal(pageWidth, pageHeight, true);

  /// The printout of the paper that will be loaded by the next `newPage`
  /// (`PrinterBlockEntity.inputPage` reads it back from the paper stack).
  Printout? _nextPrintout;
  String _pageTitle = '';

  /// The state of the printer, as the plugin reports it.
  int _ink = 0;
  int _paper = 0;

  /// The colour of the ink (`ColourUtils.getDyeColour`), 15 = black.
  int _inkColour = 15;

  PrinterPeripheral({required this.onPage}) {
    method('write', (computer, list) {
      final args = Args('write', list);
      final text = args.string(0);
      final page = _currentPage();
      // Java: `page.write(text)` writes at the cursor without moving it, then
      // the peripheral moves it by the length. This terminal's `write` moves
      // the cursor itself, so the position is set to the same absolute spot.
      final x = page.cursorX;
      final y = page.cursorY;
      page.write(text);
      page.setCursorPos(x + text.length, y);
      return noValues;
    });
    method('getCursorPos', (computer, list) {
      final page = _currentPage();
      return <Object?>[(page.cursorX + 1).toDouble(), (page.cursorY + 1).toDouble()];
    });
    method('setCursorPos', (computer, list) {
      final args = Args('setCursorPos', list);
      final x = args.integer(0);
      final y = args.integer(1);
      _currentPage().setCursorPos(x - 1, y - 1);
      return noValues;
    });
    method('getPageSize', (computer, list) => <Object?>[pageWidth.toDouble(), pageHeight.toDouble()]);
    method('newPage', (computer, list) => one(_startNewPage()));
    method('endPage', (computer, list) {
      _currentPage();
      return one(_endCurrentPage());
    });
    method('setPageTitle', (computer, list) {
      final args = Args('setPageTitle', list);
      _currentPage();
      if (_printing) _pageTitle = args.isNone(0) ? '' : normaliseLabel(args.string(0));
      return noValues;
    });
    method('getInkLevel', (computer, list) => one(_ink.toDouble()));
    method('getPaperLevel', (computer, list) => one(_paper.toDouble()));
  }

  bool _printing = false;

  /// The paper and the ink the printer holds, as the plugin counts them
  /// (`PrinterBlockEntity.getInkLevel`/`getPaperLevel`).
  void setSupplies({int? ink, int? paper, int? inkColour}) {
    if (ink != null) _ink = ink;
    if (paper != null) _paper = paper;
    if (inkColour != null) _inkColour = inkColour;
  }

  int get inkLevel => _ink;
  int get paperLevel => _paper;

  /// A printed page (of `printed_page`/`printed_pages`) was put in the printer:
  /// the next `newPage` loads its contents, as Java does.
  void setNextPrintout(Printout? printout) => _nextPrintout = printout;

  /// Whether a page is being printed.
  bool get isPrinting => _printing;

  Terminal _currentPage() {
    if (!_printing) throw LuaError.message('Page not started');
    return page;
  }

  bool _startNewPage() {
    if (_ink <= 0 || _paper <= 0) return false;
    if (_printing && !_endCurrentPage()) return false;
    _printing = true;
    _ink--;
    _paper--;
    page
      ..setTextColour(_inkColour)
      ..clear();
    final printout = _nextPrintout;
    if (printout != null) {
      _nextPrintout = null;
      _pageTitle = printout.title;
      for (var y = 0; y < pageHeight && y < printout.lines.length; y++) {
        final (text, colours) = printout.lines[y];
        page.setTextColour(0);
        page.setCursorPos(0, y);
        page.write(text);
        for (var x = 0; x < colours.length && x < pageWidth; x++) {
          page.setTextColour(_colourIndex(colours.codeUnitAt(x)));
          page.setCursorPos(x, y);
          page.write(text[x]);
        }
      }
      page.setCursorPos(0, 0);
      page.setTextColour(_inkColour);
    } else {
      _pageTitle = '';
    }
    return true;
  }

  bool _endCurrentPage() {
    if (!_printing) return false;
    final lines = <(String, String)>[];
    for (var y = 0; y < pageHeight; y++) {
      final text = page.lineText(y);
      final colours = page.foregroundLine(y);
      lines.add((text, String.fromCharCodes([for (final c in colours) _colourChar(c)])));
    }
    onPage(Printout(_pageTitle, lines));
    _printing = false;
    return true;
  }

  static int _colourIndex(int char) {
    final c = char >= 97 && char <= 122 ? char - 32 : char;
    if (c >= 65 && c <= 70) return c - 65 + 10;
    if (c >= 48 && c <= 57) return c - 48;
    return 15;
  }

  static int _colourChar(int index) =>
      index < 10 ? 48 + index : (index >= 10 && index < 16 ? 97 + index - 10 : 102);

  @override
  String get type => 'printer';
}

// -- A computer as a peripheral ------------------------------------------------

/// What [ComputerPeripheral] needs of the computer it stands for
/// (`AbstractComputerBlockEntity` + `ServerComputer`); the plugin passes the
/// computer's record so a suspended computer still answers.
abstract interface class ComputerController {
  int get id;
  String? get label;
  bool get isOn;
  void turnOn();
  void shutdown();
  void reboot();
}

/// A computer block as a peripheral of the computers next to it
/// (`ComputerPeripheral`, type `computer` for a computer and `turtle` for a
/// turtle; a command computer is not registered as one in CC either).
final class ComputerPeripheral extends MethodPeripheral {
  @override
  final String type;
  final ComputerController computer;

  ComputerPeripheral(this.type, this.computer) {
    method('turnOn', (access, list) {
      computer.turnOn();
      return noValues;
    });
    method('shutdown', (access, list) {
      computer.shutdown();
      return noValues;
    });
    method('reboot', (access, list) {
      computer.reboot();
      return noValues;
    });
    method('getID', (access, list) => one(computer.id.toDouble()));
    method('isOn', (access, list) => one(computer.isOn));
    method('getLabel', (access, list) => one(computer.label));
  }
}

// -- Command blocks ------------------------------------------------------------

/// What [CommandBlockPeripheral] needs of a vanilla command block: its command
/// and running it (`CommandBlockEntity.getCommandBlock()`).
abstract interface class CommandBlockHost {
  /// The `Command` of the block entity, or null when there is none.
  String get command;

  /// Writes the command back to the block entity.
  void setCommand(String command);

  /// Runs the command once: whether it succeeded and, when it did not, the
  /// message Java reports ("Command failed").
  (bool, String?) run();
}

/// A vanilla command block as a peripheral (`CommandBlockPeripheral`, type
/// `command`). Not the `commands` API of a command computer, which is a
/// different thing (`shared/computer/apis/CommandAPI.java`).
final class CommandBlockPeripheral extends MethodPeripheral {
  final CommandBlockHost block;

  CommandBlockPeripheral(this.block) {
    method('getCommand', (computer, list) => one(block.command));
    method('setCommand', (computer, list) {
      block.setCommand(Args('setCommand', list).string(0));
      return noValues;
    });
    method('runCommand', (computer, list) {
      final (ok, error) = block.run();
      return ok ? one(true) : <Object?>[false, error ?? 'Command failed'];
    });
  }

  @override
  String get type => 'command';
}

// -- The redstone relay --------------------------------------------------------

/// A redstone relay (`RedstoneRelayPeripheral`, type `redstone_relay`): the
/// redstone methods of a computer, on a block of its own, so several signals
/// can be driven through one wired modem.
final class RedstoneRelayPeripheral extends MethodPeripheral {
  /// The relay's own state; the plugin copies the world's signals into it and
  /// the outputs back out (`RedstoneRelayBlockEntity.redstone`).
  final RedstoneState redstone;

  final Set<PeripheralAccess> _computers = {};

  RedstoneRelayPeripheral([RedstoneState? state]) : redstone = state ?? RedstoneState() {
    ComputerSide side(Args args, int index) {
      final name = args.string(index);
      final parsed = ComputerSide.parse(name);
      if (parsed == null) args.bad(index, "unknown option '$name'");
      return parsed;
    }

    void def(List<String> names, NativeImpl Function(String name) make) {
      for (final name in names) {
        method(name, (computer, list) => make(name)(list));
      }
    }

    def(['setOutput'], (name) => (list) {
      final args = Args(name, list);
      redstone.setOutput(side(args, 0), args.boolean(1) ? 15 : 0);
      return noValues;
    });
    def(['getOutput'], (name) => (list) {
      final args = Args(name, list);
      return one(redstone.getOutput(side(args, 0)) > 0);
    });
    def(['getInput'], (name) => (list) {
      final args = Args(name, list);
      return one(redstone.getInput(side(args, 0)) > 0);
    });
    def(['setAnalogOutput', 'setAnalogueOutput'], (name) => (list) {
      final args = Args(name, list);
      final s = side(args, 0);
      final level = args.integer(1);
      if (level < 0 || level > 15) throw LuaError.message('Expected number in range 0-15');
      redstone.setOutput(s, level);
      return noValues;
    });
    def(['getAnalogOutput', 'getAnalogueOutput'], (name) => (list) {
      final args = Args(name, list);
      return one(redstone.getOutput(side(args, 0)).toDouble());
    });
    def(['getAnalogInput', 'getAnalogueInput'], (name) => (list) {
      final args = Args(name, list);
      return one(redstone.getInput(side(args, 0)).toDouble());
    });
    def(['setBundledOutput'], (name) => (list) {
      final args = Args(name, list);
      redstone.setBundledOutput(side(args, 0), args.integer(1) & 0xFFFF);
      return noValues;
    });
    def(['getBundledOutput'], (name) => (list) {
      final args = Args(name, list);
      return one(redstone.getBundledOutput(side(args, 0)).toDouble());
    });
    def(['getBundledInput'], (name) => (list) {
      final args = Args(name, list);
      return one(redstone.getBundledInput(side(args, 0)).toDouble());
    });
    def(['testBundledInput'], (name) => (list) {
      final args = Args(name, list);
      final mask = args.integer(1);
      return one((redstone.getBundledInput(side(args, 0)) & mask) == mask);
    });
  }

  /// `queueRedstoneEvent`: the inputs of the relay changed.
  void redstoneChanged() {
    for (final computer in _computers) {
      computer.queueEvent('redstone', const []);
    }
  }

  @override
  String get type => 'redstone_relay';

  @override
  void attach(PeripheralAccess computer) => _computers.add(computer);

  @override
  void detach(PeripheralAccess computer) => _computers.remove(computer);
}

// -- Stubs ---------------------------------------------------------------------

/// A peripheral that exists so programs find the type they look for, but whose
/// methods only answer "not supported": the crafting table of a turtle (the
/// server has no recipe API, see docs/host-requirements.md). Its [type] is what
/// `peripheral.getType` says.
final class StubPeripheral extends MethodPeripheral {
  @override
  final String type;

  StubPeripheral(this.type, Map<String, List<Object?> Function(List<Object?> args)> methods) {
    methods.forEach((name, body) => method(name, (computer, args) => body(args)));
  }

  /// `workbench`: `craft` returns `false` and a message.
  factory StubPeripheral.workbench() => StubPeripheral('workbench', {
    'craft': (_) => [false, 'Crafting is not supported on this server'],
  });
}