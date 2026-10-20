// `dev.ryanhcode.sable.command.Vec3ArgumentAbsolute`: an absolute `x y z`
// argument (no `~`/`^` coordinates), as the physics and joint commands use.
//
// The plugin's command builder parses one token per argument, so commands take
// three `number` arguments and this file keeps the parsing of the combined form
// for the commands that take a greedy string (`/sable joint add`).
//
// Pure: no host imports.
import 'package:pumpkin_api/pumpkin_api.dart' show CommandException;

/// Parses `"x y z"` into three doubles.
///
/// Throws a [CommandException] with the Java `ERROR_EXPECTED_DOUBLE` text when
/// a component is missing or malformed.
(double, double, double) parseAbsoluteVec3(String text) {
  final parts = text.trim().split(RegExp(r'\s+'));
  if (parts.length < 3) {
    throw CommandException('Expected a double: "$text"');
  }
  final x = double.tryParse(parts[0]);
  final y = double.tryParse(parts[1]);
  final z = double.tryParse(parts[2]);
  if (x == null || y == null || z == null) {
    throw CommandException('Expected a double: "$text"');
  }
  return (x, y, z);
}

/// Parses a list of `n` absolute vectors out of one greedy string.
List<(double, double, double)> parseAbsoluteVec3List(String text, int count) {
  final numbers = text
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map(double.parse)
      .toList();
  if (numbers.length < count * 3) {
    throw CommandException('Expected $count vectors of three numbers, got "${text.trim()}".');
  }
  return [
    for (var i = 0; i < count; i++) (numbers[i * 3], numbers[i * 3 + 1], numbers[i * 3 + 2]),
  ];
}
