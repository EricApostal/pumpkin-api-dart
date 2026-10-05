// The peripherals this package implements: monitors and wireless modems.
import 'dart:math' as math;

import '../lua/lua.dart';
import 'api/os_api.dart' show copyPlain;
import 'api/term_api.dart';
import 'peripheral.dart';
import 'terminal.dart';

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

  /// Changes the size of the monitor wall in blocks.
  void resizeBlocks(int blocksWide, int blocksHigh) {
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
  /// monitor.
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
  final (double, double, double)? position;

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

