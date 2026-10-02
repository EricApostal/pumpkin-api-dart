/// Converting doubles to and from strings, with exact (BigInt) arithmetic.
///
/// Standalone dart2wasm leaves these to the embedder, which has no floating
/// point formatting of its own. The functions here are pure Dart so they can be
/// tested against the VM's own results.
library;

import 'dart:typed_data';

/// Dart's `double.toString`: the shortest digits that round-trip, with `.0` for
/// integers and exponent notation for very large and small values.
String doubleToString(double value) {
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value.isNegative ? '-Infinity' : 'Infinity';
  if (value == 0) return value.isNegative ? '-0.0' : '0.0';

  final negative = value.isNegative;
  final (digits, pointPosition) = _shortestDigits(negative ? -value : value);
  final buffer = StringBuffer();
  if (negative) buffer.write('-');

  // The value is 0.<digits> * 10^pointPosition.
  final exponent = pointPosition - 1;
  if (exponent >= 21 || exponent < -6) {
    buffer.write(digits[0]);
    if (digits.length > 1) {
      buffer
        ..write('.')
        ..write(digits.substring(1));
    }
    buffer
      ..write('e')
      ..write(exponent >= 0 ? '+' : '-')
      ..write(exponent.abs());
  } else if (pointPosition <= 0) {
    buffer
      ..write('0.')
      ..write('0' * -pointPosition)
      ..write(digits);
  } else if (pointPosition >= digits.length) {
    buffer
      ..write(digits)
      ..write('0' * (pointPosition - digits.length))
      ..write('.0');
  } else {
    buffer
      ..write(digits.substring(0, pointPosition))
      ..write('.')
      ..write(digits.substring(pointPosition));
  }
  return buffer.toString();
}

/// `Number.prototype.toFixed`: [fractionDigits] digits after the decimal point.
String doubleToFixed(double value, int fractionDigits) {
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value.isNegative ? '-Infinity' : 'Infinity';
  if (value.abs() >= 1e21) return doubleToString(value);

  final negative = value < 0;
  final (f, e) = _decompose(negative ? -value : value);
  final scale = BigInt.from(10).pow(fractionDigits);
  final n = _roundHalfUp(f * scale, e);

  var digits = n.toString();
  if (digits.length <= fractionDigits) {
    digits = '0' * (fractionDigits + 1 - digits.length) + digits;
  }
  final whole = digits.substring(0, digits.length - fractionDigits);
  final fraction = digits.substring(digits.length - fractionDigits);
  final result = fractionDigits == 0 ? whole : '$whole.$fraction';
  // Dart keeps the sign of values that round to zero, like `-0.00`.
  return negative || (value == 0 && value.isNegative) ? '-$result' : result;
}

/// `Number.prototype.toPrecision`: [precision] significant digits.
String doubleToPrecision(double value, int precision) {
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value.isNegative ? '-Infinity' : 'Infinity';

  final negative = value.isNegative;
  final sign = negative ? '-' : '';
  if (value == 0) {
    final zeros = precision > 1 ? '.${'0' * (precision - 1)}' : '';
    return '${sign}0$zeros';
  }

  final (digits, exponent) = _roundedDigits(negative ? -value : value, precision);
  if (exponent < -6 || exponent >= precision) {
    final fraction = precision > 1 ? '.${digits.substring(1)}' : '';
    return '$sign${digits[0]}${fraction}e${exponent >= 0 ? '+' : '-'}${exponent.abs()}';
  }
  if (exponent >= 0) {
    final whole = digits.substring(0, exponent + 1);
    final fraction = digits.substring(exponent + 1);
    return fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction';
  }
  return '${sign}0.${'0' * (-exponent - 1)}$digits';
}

/// `Number.prototype.toExponential`. Without [fractionDigits], uses as many
/// digits as necessary to identify the value.
String doubleToExponential(double value, [int? fractionDigits]) {
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value.isNegative ? '-Infinity' : 'Infinity';

  final negative = value.isNegative;
  final sign = negative ? '-' : '';
  final String digits;
  final int exponent;
  if (value == 0) {
    digits = '0' * ((fractionDigits ?? 0) + 1);
    exponent = 0;
  } else if (fractionDigits == null) {
    final (shortest, point) = _shortestDigits(negative ? -value : value);
    digits = shortest;
    exponent = point - 1;
  } else {
    (digits, exponent) = _roundedDigits(
      negative ? -value : value,
      fractionDigits + 1,
    );
  }

  final fraction = digits.length > 1 ? '.${digits.substring(1)}' : '';
  return '$sign${digits[0]}${fraction}e${exponent >= 0 ? '+' : '-'}${exponent.abs()}';
}

/// Parses like `double.tryParse`, or returns null if [codeUnits] isn't a valid
/// number.
double? parseDouble(List<int> codeUnits) {
  var start = 0;
  var end = codeUnits.length;
  while (start < end && _isWhitespace(codeUnits[start])) {
    start++;
  }
  while (end > start && _isWhitespace(codeUnits[end - 1])) {
    end--;
  }
  if (start == end) return null;

  var negative = false;
  var i = start;
  if (codeUnits[i] == 0x2b || codeUnits[i] == 0x2d) {
    negative = codeUnits[i] == 0x2d;
    i++;
  }
  if (i == end) return null;

  double? finish(double value) => negative ? -value : value;

  // Infinity and NaN.
  if (_matches(codeUnits, i, end, 'Infinity')) return finish(double.infinity);
  if (_matches(codeUnits, i, end, 'NaN')) return double.nan;

  // Decimal: digits [. digits] [e [+-] digits].
  var mantissa = BigInt.zero;
  var digitCount = 0;
  var fractionDigits = 0;
  var sawDot = false;
  var sawDigit = false;
  final significant = StringBuffer();
  for (; i < end; i++) {
    final c = codeUnits[i];
    if (c >= 0x30 && c <= 0x39) {
      sawDigit = true;
      if (significant.isNotEmpty || c != 0x30) {
        significant.writeCharCode(c);
        digitCount++;
      }
      if (sawDot) fractionDigits++;
    } else if (c == 0x2e && !sawDot) {
      sawDot = true;
    } else {
      break;
    }
  }
  if (!sawDigit) return null;
  if (significant.isNotEmpty) mantissa = BigInt.parse(significant.toString());

  var exponent = 0;
  if (i < end) {
    if (codeUnits[i] != 0x65 && codeUnits[i] != 0x45) return null;
    i++;
    var exponentNegative = false;
    if (i < end && (codeUnits[i] == 0x2b || codeUnits[i] == 0x2d)) {
      exponentNegative = codeUnits[i] == 0x2d;
      i++;
    }
    if (i == end) return null;
    var value = 0;
    for (; i < end; i++) {
      final c = codeUnits[i];
      if (c < 0x30 || c > 0x39) return null;
      if (value < 100000) value = value * 10 + (c - 0x30);
    }
    exponent = exponentNegative ? -value : value;
  }

  if (mantissa == BigInt.zero) return finish(0.0);

  final scale = exponent - fractionDigits;
  // Anything beyond these bounds overflows to infinity or underflows to zero.
  if (digitCount + scale > 310) return finish(double.infinity);
  if (digitCount + scale < -330) return finish(0.0);

  final ten = BigInt.from(10);
  final result = scale >= 0
      ? _ratioToDouble(mantissa * ten.pow(scale), BigInt.one)
      : _ratioToDouble(mantissa, ten.pow(-scale));
  return finish(result);
}

bool _isWhitespace(int c) =>
    (c >= 0x09 && c <= 0x0d) ||
    c == 0x20 ||
    c == 0xa0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200a) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202f ||
    c == 0x205f ||
    c == 0x3000 ||
    c == 0xfeff;

bool _matches(List<int> codeUnits, int start, int end, String word) {
  if (end - start != word.length) return false;
  for (var i = 0; i < word.length; i++) {
    if (codeUnits[start + i] != word.codeUnitAt(i)) return false;
  }
  return true;
}

final _two52 = BigInt.one << 52;

/// Splits a finite, positive [value] into `f * 2^e` with an integer `f`.
(BigInt, int) _decompose(double value) {
  final data = ByteData(8)..setFloat64(0, value);
  final bits = BigInt.from(data.getInt64(0)).toUnsigned(64);
  final exponentField = (bits >> 52).toInt() & 0x7ff;
  final mantissa = bits & (_two52 - BigInt.one);
  if (exponentField == 0) return (mantissa, -1074);
  return (mantissa | _two52, exponentField - 1075);
}

/// `round(f * 2^e)`, rounding halves up.
BigInt _roundHalfUp(BigInt f, int e) {
  if (e >= 0) return f << e;
  final denominator = BigInt.one << -e;
  return ((f << 1) + denominator) ~/ (denominator << 1);
}

/// The shortest digits that uniquely identify the positive [value], and the
/// position of the decimal point: the value is `0.<digits> * 10^position`.
///
/// Burger and Dybvig, "Printing Floating-Point Numbers Quickly and Accurately".
(String, int) _shortestDigits(double value) {
  final (f, e) = _decompose(value);
  final even = f.isEven;
  final ten = BigInt.from(10);

  BigInt r, s, mPlus, mMinus;
  if (e >= 0) {
    final be = BigInt.one << e;
    if (f != _two52) {
      r = f * be * BigInt.two;
      s = BigInt.two;
      mPlus = be;
      mMinus = be;
    } else {
      final be1 = be << 1;
      r = f * be1 * BigInt.two;
      s = BigInt.from(4);
      mPlus = be1;
      mMinus = be;
    }
  } else if (e == -1074 || f != _two52) {
    r = f * BigInt.two;
    s = (BigInt.one << -e) * BigInt.two;
    mPlus = BigInt.one;
    mMinus = BigInt.one;
  } else {
    r = f * BigInt.from(4);
    s = (BigInt.one << (1 - e)) * BigInt.two;
    mPlus = BigInt.two;
    mMinus = BigInt.one;
  }

  // An estimate of ceil(log10(value)) that is never too high.
  var k = ((e + f.bitLength - 1) * 0.30102999566398114 - 1e-10).ceil();
  if (k >= 0) {
    s *= ten.pow(k);
  } else {
    final scale = ten.pow(-k);
    r *= scale;
    mPlus *= scale;
    mMinus *= scale;
  }

  // Fix up the estimate if it was one too low.
  if (even ? r + mPlus >= s : r + mPlus > s) {
    k++;
  } else {
    r *= ten;
    mPlus *= ten;
    mMinus *= ten;
  }

  final digits = StringBuffer();
  while (true) {
    final d = (r ~/ s).toInt();
    r = r % s;
    final low = even ? r <= mMinus : r < mMinus;
    final high = even ? r + mPlus >= s : r + mPlus > s;
    if (!low && !high) {
      digits.write(d);
      r *= ten;
      mPlus *= ten;
      mMinus *= ten;
      continue;
    }
    if (low && !high) {
      digits.write(d);
    } else if (!low && high) {
      digits.write(d + 1);
    } else {
      final twice = r * BigInt.two;
      // Both candidates are equally good for an exact tie: pick the even one.
      digits.write(
        twice < s ? d : (twice > s ? d + 1 : (d.isEven ? d : d + 1)),
      );
    }
    break;
  }
  return (digits.toString(), k);
}

/// [precision] significant digits of the positive [value], rounding halves up,
/// and the decimal exponent of the first digit.
(String, int) _roundedDigits(double value, int precision) {
  final (f, e) = _decompose(value);
  final (_, shortestPoint) = _shortestDigits(value);
  var exponent = shortestPoint - 1;

  final ten = BigInt.from(10);
  final low = ten.pow(precision - 1);
  final high = ten.pow(precision);
  while (true) {
    // n = round(value * 10^(precision - 1 - exponent)).
    final scale = precision - 1 - exponent;
    BigInt n;
    if (scale >= 0) {
      n = _roundHalfUp(f * ten.pow(scale), e);
    } else {
      // Divide by 10^-scale instead.
      final numerator = e >= 0 ? f << e : f;
      var denominator = ten.pow(-scale);
      if (e < 0) denominator = denominator << -e;
      n = ((numerator << 1) + denominator) ~/ (denominator << 1);
    }
    if (n >= high) {
      exponent++;
    } else if (n < low) {
      exponent--;
    } else {
      return (n.toString(), exponent);
    }
  }
}

/// The double nearest to `a / b` for positive integers, rounding to even.
double _ratioToDouble(BigInt a, BigInt b) {
  if (a == BigInt.zero) return 0.0;

  // Scale so the quotient has 54 or 55 significant bits.
  final shift = 54 - (a.bitLength - b.bitLength);
  final numerator = shift >= 0 ? a << shift : a;
  final denominator = shift >= 0 ? b : b << -shift;
  var q = numerator ~/ denominator;
  var sticky = numerator % denominator != BigInt.zero;

  // value = q * 2^-shift. Keep 53 bits, or fewer for subnormals.
  var lsbExponent = -shift;
  var drop = q.bitLength - 53;
  if (lsbExponent + drop < -1074) drop = -1074 - lsbExponent;
  lsbExponent += drop;

  BigInt mantissa;
  if (drop > 0) {
    final mask = (BigInt.one << drop) - BigInt.one;
    final dropped = q & mask;
    mantissa = q >> drop;
    final half = BigInt.one << (drop - 1);
    if (dropped > half || (dropped == half && (sticky || mantissa.isOdd))) {
      mantissa += BigInt.one;
    }
  } else {
    mantissa = q << -drop;
    lsbExponent += drop;
  }

  if (mantissa == BigInt.one << 53) {
    mantissa = mantissa >> 1;
    lsbExponent++;
  }

  final biased = lsbExponent + 1075;
  if (mantissa >= _two52) {
    if (biased >= 2047) return double.infinity;
    final bits = (BigInt.from(biased) << 52) | (mantissa - _two52);
    return _fromBits(bits);
  }
  // Subnormal.
  return _fromBits(mantissa);
}

double _fromBits(BigInt bits) {
  final data = ByteData(8)..setInt64(0, bits.toSigned(64).toInt());
  return data.getFloat64(0);
}
