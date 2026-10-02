import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wasm_components/src/text/double_format.dart';

double _randomDouble(Random random) {
  switch (random.nextInt(4)) {
    case 0:
      // Uniformly random bit patterns, covering every exponent.
      final data = ByteData(8)
        ..setUint32(0, random.nextInt(1 << 32))
        ..setUint32(4, random.nextInt(1 << 32));
      return data.getFloat64(0);
    case 1:
      return (random.nextDouble() - 0.5) * pow(10, random.nextInt(40) - 20);
    case 2:
      return random.nextInt(100000) / pow(10, random.nextInt(8));
    default:
      return random.nextInt(1 << 30) * 1.0;
  }
}

List<int> _units(String s) => s.codeUnits;

void main() {
  final random = Random(42);

  test('toString matches the VM', () {
    final specials = [
      0.0, -0.0, 1.0, -1.0, 0.1, 0.5, 100.0, 1e21, 1e20, 1e-5, 1e-6, 1e-7,
      0.0001, 123456789.123456789, 5e-324, double.maxFinite,
      double.minPositive, 1.7976931348623157e308, 4.9e-324, 2.5, 1 / 3,
      double.infinity, double.negativeInfinity, double.nan, 9007199254740993.0,
      123456789012345680000.0, 1.5e300, 0.000123,
    ];
    for (final v in [...specials, for (var i = 0; i < 3000; i++) _randomDouble(random)]) {
      expect(doubleToString(v), v.toString(), reason: 'for $v');
    }
  });

  test('toStringAsFixed matches the VM', () {
    for (var i = 0; i < 1500; i++) {
      final v = _randomDouble(random);
      if (v.isNaN || v.isInfinite) continue;
      final digits = random.nextInt(21);
      expect(
        doubleToFixed(v, digits),
        v.toStringAsFixed(digits),
        reason: 'for $v with $digits',
      );
    }
    expect(doubleToFixed(2.5, 0), '3');
    expect(doubleToFixed(1.005, 2), '1.00');
    expect(doubleToFixed(0.000001, 2), '0.00');
    expect(doubleToFixed(1e21, 2), '1e+21');
  });

  test('toStringAsPrecision matches the VM', () {
    for (var i = 0; i < 1500; i++) {
      final v = _randomDouble(random);
      if (v.isNaN || v.isInfinite) continue;
      final precision = 1 + random.nextInt(21);
      expect(
        doubleToPrecision(v, precision),
        v.toStringAsPrecision(precision),
        reason: 'for $v with $precision',
      );
    }
  });

  test('toStringAsExponential matches the VM', () {
    for (var i = 0; i < 1500; i++) {
      final v = _randomDouble(random);
      if (v.isNaN || v.isInfinite) continue;
      final digits = random.nextInt(21);
      expect(
        doubleToExponential(v, digits),
        v.toStringAsExponential(digits),
        reason: 'for $v with $digits',
      );
      expect(
        doubleToExponential(v),
        v.toStringAsExponential(),
        reason: 'for $v',
      );
    }
  });

  test('parse matches the VM on printed doubles', () {
    for (var i = 0; i < 4000; i++) {
      final v = _randomDouble(random);
      if (v.isNaN) continue;
      final text = v.toString();
      expect(parseDouble(_units(text)), double.parse(text), reason: text);
    }
  });

  test('parse matches the VM on random decimal strings', () {
    for (var i = 0; i < 4000; i++) {
      final digits = List.generate(1 + random.nextInt(25), (_) => random.nextInt(10)).join();
      final dot = random.nextInt(digits.length + 1);
      var text = '${digits.substring(0, dot)}.${digits.substring(dot)}';
      if (random.nextBool()) text += 'e${random.nextInt(660) - 330}';
      if (random.nextBool()) text = '-$text';
      final expected = double.tryParse(text);
      final actual = parseDouble(_units(text));
      expect(actual, expected, reason: text);
    }
  });

  test('parse handles special forms like the VM', () {
    for (final text in [
      '1', '-1', '+1', '1.', '.5', '-.5', '0', '-0', '0.0', '1e5', '1E5',
      '1e+5', '1e-5', '  2.5  ', '\t3\n', 'Infinity', '-Infinity', 'NaN',
      '0x1A', '0XFF', '1e', 'e5', '.', '', ' ', '1.2.3', 'abc', '1_000',
      '--1', '1e1e1', '0x', '1e400', '1e-400', '4.9e-324', '2.4e-324',
      '2.5e-324', '1.7976931348623157e308', '1.7976931348623159e308',
      '0.1', '0.30000000000000004', '123456789012345678901234567890',
    ]) {
      final expected = double.tryParse(text);
      final actual = parseDouble(_units(text));
      if (expected != null && expected.isNaN) {
        expect(actual, isNotNull, reason: text);
        expect(actual!.isNaN, isTrue, reason: text);
      } else {
        expect(actual, expected, reason: text);
      }
    }
  });
}
