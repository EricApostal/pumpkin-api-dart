// Dates for `os.date` and `os.time`. Times are UTC: a server has no
// meaningful local time zone, and wasm has no zone database.
import '../../lua/lua.dart';

const List<String> _weekdays = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

const List<String> _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _two(int n) => n.toString().padLeft(2, '0');

int _dayOfYear(DateTime t) =>
    t.difference(DateTime.utc(t.year, 1, 1)).inDays + 1;

/// `os.date("*t")`.
LuaTable dateTable(DateTime t) {
  return LuaTable()
    ..setString('year', t.year.toDouble())
    ..setString('month', t.month.toDouble())
    ..setString('day', t.day.toDouble())
    ..setString('hour', t.hour.toDouble())
    ..setString('min', t.minute.toDouble())
    ..setString('sec', t.second.toDouble())
    ..setString('wday', (t.weekday % 7 + 1).toDouble())
    ..setString('yday', _dayOfYear(t).toDouble())
    ..setString('isdst', false);
}

/// `os.time{...}`: seconds since the epoch for the fields of [table].
double timeFromTable(LuaTable table) {
  double field(String name, double? fallback) {
    final value = table.getString(name);
    if (value is double) return value;
    if (value is String) {
      final parsed = parseLuaNumber(value);
      if (parsed != null) return parsed;
    }
    if (fallback != null) return fallback;
    throw LuaError.message("field '$name' missing in date table");
  }

  final date = DateTime.utc(
    field('year', null).toInt(),
    field('month', null).toInt(),
    field('day', null).toInt(),
    field('hour', 12).toInt(),
    field('min', 0).toInt(),
    field('sec', 0).toInt(),
  );
  return (date.millisecondsSinceEpoch ~/ 1000).toDouble();
}

/// `os.date(format, time)` with [t] already converted.
String formatDate(String format, DateTime t) {
  final out = StringBuffer();
  for (var i = 0; i < format.length; i++) {
    final c = format[i];
    if (c != '%') {
      out.write(c);
      continue;
    }
    i++;
    if (i >= format.length) {
      throw LuaError.message("bad argument #1 to 'date' (invalid conversion specifier '%')");
    }
    final spec = format[i];
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    switch (spec) {
      case 'a':
        out.write(_weekdays[t.weekday % 7].substring(0, 3));
      case 'A':
        out.write(_weekdays[t.weekday % 7]);
      case 'b':
      case 'h':
        out.write(_months[t.month - 1].substring(0, 3));
      case 'B':
        out.write(_months[t.month - 1]);
      case 'c':
        out.write(
          '${_weekdays[t.weekday % 7].substring(0, 3)} '
          '${_months[t.month - 1].substring(0, 3)} '
          '${t.day.toString().padLeft(2)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)} ${t.year}',
        );
      case 'd':
        out.write(_two(t.day));
      case 'e':
        out.write(t.day.toString().padLeft(2));
      case 'H':
        out.write(_two(t.hour));
      case 'I':
        out.write(_two(hour12));
      case 'j':
        out.write(_dayOfYear(t).toString().padLeft(3, '0'));
      case 'm':
        out.write(_two(t.month));
      case 'M':
        out.write(_two(t.minute));
      case 'n':
        out.write('\n');
      case 'p':
        out.write(t.hour < 12 ? 'AM' : 'PM');
      case 'S':
        out.write(_two(t.second));
      case 't':
        out.write('\t');
      case 'U':
        out.write(_two((_dayOfYear(t) - 1 + 7 - t.weekday % 7) ~/ 7));
      case 'w':
        out.write(t.weekday % 7);
      case 'W':
        out.write(_two((_dayOfYear(t) - 1 + 7 - (t.weekday + 6) % 7) ~/ 7));
      case 'x':
        out.write('${_two(t.month)}/${_two(t.day)}/${_two(t.year % 100)}');
      case 'X':
        out.write('${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}');
      case 'y':
        out.write(_two(t.year % 100));
      case 'Y':
        out.write(t.year);
      case 'Z':
        out.write('UTC');
      case '%':
        out.write('%');
      default:
        throw LuaError.message("bad argument #1 to 'date' (invalid conversion specifier '%$spec')");
    }
  }
  return out.toString();
}
