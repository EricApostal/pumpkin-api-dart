// The `os` API: events, timers, alarms, the clock and the power controls.
// CraftOS adds `pullEvent`, `sleep` and friends in Lua on top of this.
import '../../lua/lua.dart';
import 'lua_date.dart';

/// What the `os` API needs from its computer.
abstract interface class OsHost {
  int get computerId;

  String? get label;
  set label(String? value);

  /// Queues an event for the program (arguments are copied).
  void queueEvent(String name, List<Object?> args);

  /// Starts a timer that fires a `timer` event after [ticks] server ticks and
  /// returns its id.
  int startTimer(int ticks);

  void cancelTimer(int id);

  void shutdown();

  void reboot();

  /// The in-game time of day in hours, 0 to 24.
  double get timeOfDay;

  /// The in-game day, starting at 1.
  int get day;
}

/// Copies a Lua value the way CC: Tweaked passes events and messages between
/// computers: numbers, booleans, strings and tables survive, everything else
/// (functions, threads, metatables) is dropped.
Object? copyPlain(Object? value, [Map<Object, Object?>? seen]) {
  if (value is LuaTable) {
    final copies = seen ?? <Object, Object?>{};
    final existing = copies[value];
    if (existing != null) return existing;
    final copy = LuaTable();
    copies[value] = copy;
    var entry = value.next(null);
    while (entry != null) {
      final key = copyPlain(entry.$1, copies);
      final item = copyPlain(entry.$2, copies);
      if (key != null && item != null) copy.set(key, item);
      entry = value.next(entry.$1);
    }
    return copy;
  }
  if (value is String || value is double || value is bool) return value;
  return null;
}

/// The state behind the `os` table: alarms and the tick counter.
final class OsApi {
  final OsHost _host;
  final Map<int, (double, int)> _alarms = {};
  int _clock = 0;
  double _time = 0;
  int _day = 1;
  int _nextAlarm = 0;

  OsApi(this._host);

  /// Called when the computer starts.
  void startup() {
    _time = _host.timeOfDay;
    _day = _host.day;
    _clock = 0;
    _alarms.clear();
  }

  void shutdown() => _alarms.clear();

  /// Called once per tick while the computer is on.
  void update() {
    _clock++;
    final time = _host.timeOfDay;
    final day = _host.day;
    if (time > _time || day > _day) {
      final now = _day * 24.0 + _time;
      for (final id in _alarms.keys.toList()) {
        final (alarmTime, alarmDay) = _alarms[id]!;
        if (now >= alarmDay * 24.0 + alarmTime) {
          _host.queueEvent('alarm', [id.toDouble()]);
          _alarms.remove(id);
        }
      }
    }
    _time = time;
    _day = day;
  }

  LuaTable build() {
    final table = LuaTable();
    void def(List<String> names, NativeImpl impl) {
      for (final name in names) {
        table.setString(name, NativeFunction(name, impl));
      }
    }

    def(['queueEvent'], (list) {
      final args = Args('queueEvent', list);
      _host.queueEvent(args.string(0), list.sublist(1));
      return noValues;
    });

    def(['startTimer'], (list) {
      final seconds = _finite(Args('startTimer', list), 0);
      return one(_host.startTimer((seconds / 0.05).round()).toDouble());
    });

    def(['cancelTimer'], (list) {
      _host.cancelTimer(Args('cancelTimer', list).integer(0));
      return noValues;
    });

    def(['setAlarm'], (list) {
      final args = Args('setAlarm', list);
      final time = _finite(args, 0);
      if (time < 0 || time >= 24) throw LuaError.message('Number out of range');
      final day = time > _time ? _day : _day + 1;
      _alarms[_nextAlarm] = (time, day);
      return one((_nextAlarm++).toDouble());
    });

    def(['cancelAlarm'], (list) {
      _alarms.remove(Args('cancelAlarm', list).integer(0));
      return noValues;
    });

    def(['shutdown'], (_) {
      _host.shutdown();
      return noValues;
    });

    def(['reboot'], (_) {
      _host.reboot();
      return noValues;
    });

    def(['getComputerID', 'computerID'], (_) => one(_host.computerId.toDouble()));

    def(['getComputerLabel', 'computerLabel'], (_) {
      final label = _host.label;
      return label == null ? one(null) : one(label);
    });

    def(['setComputerLabel'], (list) {
      final args = Args('setComputerLabel', list);
      _host.label = args.isNone(0) ? null : normaliseLabel(args.string(0));
      return noValues;
    });

    def(['clock'], (_) => one(_clock * 0.05));

    def(['time'], (list) {
      final args = Args('time', list);
      final value = args[0];
      if (value is LuaTable) return one(timeFromTable(value));
      switch (args.optString(0, 'ingame').toLowerCase()) {
        case 'utc':
        case 'local':
          final now = DateTime.now().toUtc();
          return one(now.hour + now.minute / 60 + now.second / 3600);
        case 'ingame':
          return one(_time);
        default:
          throw LuaError.message('Unsupported operation');
      }
    });

    def(['day'], (list) {
      switch (Args('day', list).optString(0, 'ingame').toLowerCase()) {
        case 'utc':
        case 'local':
          final now = DateTime.now().toUtc();
          return one((now.difference(DateTime.utc(1970)).inDays + 1).toDouble());
        case 'ingame':
          return one(_day.toDouble());
        default:
          throw LuaError.message('Unsupported operation');
      }
    });

    def(['epoch'], (list) {
      switch (Args('epoch', list).optString(0, 'ingame').toLowerCase()) {
        case 'utc':
        case 'local':
          return one(DateTime.now().toUtc().millisecondsSinceEpoch.toDouble());
        case 'ingame':
          return one((_day * 86400000 + (_time * 3600000).truncate()).toDouble());
        default:
          throw LuaError.message('Unsupported operation');
      }
    });

    def(['date'], (list) {
      final args = Args('date', list);
      var format = args.optString(0, '%c');
      final seconds = args.isNone(1)
          ? DateTime.now().millisecondsSinceEpoch ~/ 1000
          : args.integer(1);
      if (format.startsWith('!')) format = format.substring(1);
      final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
      if (format == '*t') return one(dateTable(date));
      return one(formatDate(format, date));
    });

    return table;
  }
}

double _finite(Args args, int index) {
  final value = args.number(index);
  if (value.isNaN || value.isInfinite) args.wrongType(index, 'number');
  return value;
}

/// Computer labels are at most 32 printable characters.
String normaliseLabel(String text) {
  final length = text.length < 32 ? text.length : 32;
  final out = StringBuffer();
  for (var i = 0; i < length; i++) {
    final c = text.codeUnitAt(i);
    final allowed = (c >= 32 && c <= 126) || (c >= 161 && c <= 255 && c != 167);
    out.write(allowed ? text[i] : '?');
  }
  return out.toString();
}
