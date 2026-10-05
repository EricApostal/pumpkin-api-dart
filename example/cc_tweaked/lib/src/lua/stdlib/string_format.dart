// `string.format`.
import '../value.dart';
import '../vm.dart';
import 'args.dart';

/// Implements `string.format(format, ...)`; [list] holds the format string
/// and its arguments.
String formatString(LuaVm vm, List<Object?> list) {
  final args = Args('format', list);
  final format = args.string(0);
  final out = StringBuffer();
  var argIndex = 0;
  for (var i = 0; i < format.length; i++) {
    final c = format.codeUnitAt(i);
    if (c != 37) {
      out.writeCharCode(c);
      continue;
    }
    i++;
    if (i >= format.length) {
      throw LuaError.message("invalid option '%' to 'format'");
    }
    if (format.codeUnitAt(i) == 37) {
      out.writeCharCode(37);
      continue;
    }
    var left = false;
    var plus = false;
    var space = false;
    var alternate = false;
    var zero = false;
    flags:
    while (i < format.length) {
      switch (format.codeUnitAt(i)) {
        case 45:
          left = true;
        case 43:
          plus = true;
        case 32:
          space = true;
        case 35:
          alternate = true;
        case 48:
          zero = true;
        default:
          break flags;
      }
      i++;
    }
    var width = 0;
    while (i < format.length && _isDigit(format.codeUnitAt(i))) {
      width = width * 10 + format.codeUnitAt(i) - 48;
      i++;
    }
    int? precision;
    if (i < format.length && format.codeUnitAt(i) == 46) {
      i++;
      precision = 0;
      while (i < format.length && _isDigit(format.codeUnitAt(i))) {
        precision = precision! * 10 + format.codeUnitAt(i) - 48;
        i++;
      }
    }
    if (width > 99 || (precision ?? 0) > 99) {
      throw LuaError.message("invalid format (width or precision too long)");
    }
    if (i >= format.length) {
      throw LuaError.message("invalid option '%' to 'format'");
    }
    final conversion = format[i];
    argIndex++;
    if (argIndex >= list.length && conversion != '%') {
      args.bad(argIndex, 'no value');
    }
    String sign(bool negative) =>
        negative ? '-' : (plus ? '+' : (space ? ' ' : ''));

    switch (conversion) {
      case 'd':
      case 'i':
        final value = args.integer(argIndex);
        var digits = value.abs().toString();
        if (value == -9223372036854775808) digits = '9223372036854775808';
        if (precision != null) digits = digits.padLeft(precision, '0');
        out.write(_pad(sign(value < 0), digits, width, left, zero && precision == null));
      case 'u':
        final value = args.integer(argIndex);
        var digits = _unsigned(value, 10);
        if (precision != null) digits = digits.padLeft(precision, '0');
        out.write(_pad('', digits, width, left, zero && precision == null));
      case 'o':
      case 'x':
      case 'X':
        final value = args.integer(argIndex);
        var digits = _unsigned(value, conversion == 'o' ? 8 : 16);
        if (conversion == 'X') digits = digits.toUpperCase();
        if (precision != null) digits = digits.padLeft(precision, '0');
        var prefix = '';
        if (alternate && value != 0) {
          prefix = conversion == 'o' ? '0' : (conversion == 'x' ? '0x' : '0X');
        }
        out.write(_pad(prefix, digits, width, left, zero && precision == null));
      case 'c':
        out.write(_pad('', String.fromCharCode(args.integer(argIndex) & 255), width, left, false));
      case 'e':
      case 'E':
      case 'f':
      case 'F':
      case 'g':
      case 'G':
        final value = args.number(argIndex);
        if (value.isNaN || value.isInfinite) {
          var text = value.isNaN ? 'nan' : 'inf';
          if (conversion == 'E' || conversion == 'F' || conversion == 'G') {
            text = text.toUpperCase();
          }
          out.write(_pad(sign(value < 0), text, width, left, false));
        } else {
          final negative = value < 0 || (value == 0 && value.isNegative);
          out.write(
            _pad(
              sign(negative),
              _formatFloat(value.abs(), conversion, precision, alternate),
              width,
              left,
              zero,
            ),
          );
        }
      case 's':
        var text = vm.tostring(args.any(argIndex));
        if (precision != null && precision < text.length) {
          text = text.substring(0, precision);
        }
        out.write(_pad('', text, width, left, false));
      case 'q':
        out.write(_quote(args.string(argIndex)));
      default:
        throw LuaError.message("invalid option '%$conversion' to 'format'");
    }
  }
  return out.toString();
}

bool _isDigit(int c) => c >= 48 && c <= 57;

String _unsigned(int value, int radix) =>
    value >= 0
        ? value.toRadixString(radix)
        : BigInt.from(value).toUnsigned(64).toRadixString(radix);

String _pad(String prefix, String body, int width, bool left, bool zero) {
  final length = prefix.length + body.length;
  if (length >= width) return '$prefix$body';
  final fill = width - length;
  if (left) return '$prefix$body${' ' * fill}';
  if (zero) return '$prefix${'0' * fill}$body';
  return '${' ' * fill}$prefix$body';
}

String _formatFloat(double value, String conversion, int? precision, bool alternate) {
  final p = precision ?? 6;
  switch (conversion) {
    case 'f':
    case 'F':
      var text = _fixed(value, p);
      if (alternate && p == 0) text = '$text.';
      return text;
    case 'e':
    case 'E':
      var text = _exponential(value, p);
      if (alternate && p == 0) text = text.replaceFirst('e', '.e');
      return conversion == 'E' ? text.toUpperCase() : text;
    default:
      return formatG(value, p, alternate: alternate, upper: conversion == 'G');
  }
}

String _fixed(double value, int precision) {
  if (value >= 1e21) {
    final integer = BigInt.from(value).toString();
    return precision == 0 ? integer : '$integer.${'0' * precision}';
  }
  if (precision <= 20) return value.toStringAsFixed(precision);
  return '${value.toStringAsFixed(20)}${'0' * (precision - 20)}';
}

String _exponential(double value, int precision) {
  final text = value.toStringAsExponential(precision > 20 ? 20 : precision);
  final e = text.indexOf('e');
  final mantissa = text.substring(0, e);
  final sign = text[e + 1];
  final digits = text.substring(e + 2).padLeft(2, '0');
  final extra = precision > 20 ? '0' * (precision - 20) : '';
  final withExtra = extra.isEmpty
      ? mantissa
      : '${mantissa.contains('.') ? mantissa : '$mantissa.'}$extra';
  return '${withExtra}e$sign$digits';
}

String _quote(String s) {
  final out = StringBuffer('"');
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    switch (c) {
      case 34:
        out.write('\\"');
      case 92:
        out.write('\\\\');
      case 10:
        out.write('\\\n');
      case 13:
        out.write('\\r');
      case 0:
        out.write('\\000');
      default:
        out.writeCharCode(c);
    }
  }
  out.write('"');
  return out.toString();
}
