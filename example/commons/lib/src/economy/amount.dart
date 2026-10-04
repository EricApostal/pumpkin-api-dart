/// Reading and writing whole-number amounts of money.
library;

import 'model.dart';

/// Thrown by [parseAmount] with a message that is fit to show to a player.
final class AmountException implements Exception {
  final String message;

  const AmountException(this.message);

  @override
  String toString() => message;
}

final _amountPattern = RegExp(r'^(\d+)(?:\.(\d+))?([kmbt])?$');

const _suffixDigits = {'k': 3, 'm': 6, 'b': 9, 't': 12};

/// Reads what a player typed as an amount: `250`, `1,500`, `2k`, `1.5m`.
///
/// The suffixes are `k` (thousand), `m` (million), `b` (billion) and `t`
/// (trillion). The value is computed with integers only, so `1.5k` is exactly
/// 1500, and `1.0005k` is rejected because it is not a whole number. The
/// result is between 0 and [maxSupportedBalance]; whether 0 is allowed is up
/// to the caller.
///
/// Throws [AmountException].
int parseAmount(String text) {
  final trimmed = text.trim().toLowerCase().replaceAll(',', '');
  if (trimmed.startsWith('-')) {
    throw const AmountException('The amount must be positive.');
  }
  final match = _amountPattern.firstMatch(trimmed);
  if (match == null) {
    throw AmountException(
      '"$text" is not an amount. Use a whole number like 250, 1,500 or 2k.',
    );
  }
  final suffix = match.group(3);
  final fraction = match.group(2) ?? '';
  final scale = suffix == null ? 0 : _suffixDigits[suffix]!;
  if (suffix == null && fraction.isNotEmpty) {
    throw const AmountException('Amounts are whole numbers, without decimals.');
  }
  if (fraction.length > scale &&
      fraction.substring(scale).contains(RegExp('[1-9]'))) {
    throw AmountException('"$text" is not a whole number.');
  }
  final digits = fraction.padRight(scale, '0').substring(0, scale);
  final value = BigInt.parse('${match.group(1)}$digits');
  if (value > BigInt.from(maxSupportedBalance)) {
    throw const AmountException('That amount is too large.');
  }
  return value.toInt();
}

/// [value] with thousands separators: `1250` becomes `1,250`.
String groupDigits(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
