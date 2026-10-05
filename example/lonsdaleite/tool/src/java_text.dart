/// Helpers for reading the small subset of Java the mod's registrations use:
/// balanced-bracket scanning, top-level argument splitting, call chains and
/// numeric literals. Anything outside that subset throws a [JavaParseError]
/// instead of being guessed at.
library;

import 'dart:typed_data';

/// The source uses Java that the generator does not model.
final class JavaParseError implements Exception {
  final String message;

  JavaParseError(this.message);

  @override
  String toString() => 'JavaParseError: $message';
}

/// Removes `//` and `/* */` comments, leaving string literals untouched.
String stripJavaComments(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == '"') {
      final end = _endOfString(source, i);
      out.write(source.substring(i, end + 1));
      i = end + 1;
    } else if (source.startsWith('//', i)) {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
    } else if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      if (end < 0) throw JavaParseError('Unterminated block comment');
      i = end + 2;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

int _endOfString(String s, int open) {
  var i = open + 1;
  while (i < s.length) {
    if (s[i] == r'\') {
      i += 2;
    } else if (s[i] == '"') {
      return i;
    } else {
      i++;
    }
  }
  throw JavaParseError('Unterminated string literal');
}

const _openers = '([{';
const _closers = ')]}';

/// The index of the bracket that closes the one at [open].
int indexOfClosing(String s, int open) {
  var depth = 0;
  var i = open;
  while (i < s.length) {
    final c = s[i];
    if (c == '"') {
      i = _endOfString(s, i) + 1;
      continue;
    }
    if (_openers.contains(c)) depth++;
    if (_closers.contains(c)) {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  throw JavaParseError('Unbalanced brackets at $open');
}

/// Splits [s] at every top-level [separator], trimming the pieces. An empty
/// string gives an empty list.
List<String> splitTopLevel(String s, [String separator = ',']) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == '"') {
      i = _endOfString(s, i) + 1;
      continue;
    }
    if (_openers.contains(c)) depth++;
    if (_closers.contains(c)) depth--;
    if (depth == 0 && s.startsWith(separator, i)) {
      parts.add(s.substring(start, i).trim());
      start = i + separator.length;
      i = start;
      continue;
    }
    i++;
  }
  final last = s.substring(start).trim();
  if (last.isNotEmpty || parts.isNotEmpty) parts.add(last);
  return parts;
}

/// One `.name(args)` link of a call chain.
final class JavaCall {
  final String name;
  final List<String> args;

  const JavaCall(this.name, this.args);

  @override
  String toString() => '$name(${args.join(', ')})';
}

/// A chain such as `p.pickaxe(M, 5, -2.8F).enchantable(15)`: the [root]
/// identifier followed by [calls].
final class JavaChain {
  final String root;
  final List<JavaCall> calls;

  const JavaChain(this.root, this.calls);
}

final _identifier = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');

/// Parses a chain of method calls. Every link after the root must be a call.
JavaChain parseCallChain(String expression) {
  final s = expression.trim();
  final rootMatch = _identifier.matchAsPrefix(s);
  if (rootMatch == null) {
    throw JavaParseError('Expected an identifier in `$expression`');
  }
  final calls = <JavaCall>[];
  var i = rootMatch.end;
  int skipSpace(int at) {
    while (at < s.length && s[at].trim().isEmpty) {
      at++;
    }
    return at;
  }

  while ((i = skipSpace(i)) < s.length) {
    if (s[i] != '.') {
      throw JavaParseError('Expected `.` at $i in `$expression`');
    }
    final name = _identifier.matchAsPrefix(s, skipSpace(i + 1));
    if (name == null || name.end >= s.length || s[name.end] != '(') {
      throw JavaParseError('Expected a method call at $i in `$expression`');
    }
    final close = indexOfClosing(s, name.end);
    calls.add(JavaCall(
      name.group(0)!,
      splitTopLevel(s.substring(name.end + 1, close)),
    ));
    i = close + 1;
  }
  return JavaChain(rootMatch.group(0)!, calls);
}

/// A numeric literal. Java `float`s (suffix `F`) are rounded to 32 bits when
/// they are widened to `double`, which is what the game does.
final class JavaNumber {
  /// The value as a Java `double` (a `float` is already widened).
  final double value;

  /// Whether the literal was a `float` or an `int`-valued literal.
  final bool isFloat;

  /// Whether the literal had no decimal point or suffix.
  final bool isInteger;

  const JavaNumber(this.value, {required this.isFloat, required this.isInteger});

  int get asInt {
    if (!isInteger) throw JavaParseError('Expected an int, got $value');
    return value.toInt();
  }
}

final _numberPattern = RegExp(r'^-?\d+(\.\d+)?([fFdD])?$');

/// Parses `5`, `-2.8F`, `7.0`, `0.4F`; returns `null` if [text] is not a
/// numeric literal.
JavaNumber? tryParseJavaNumber(String text) {
  final t = text.trim();
  final m = _numberPattern.firstMatch(t);
  if (m == null) return null;
  final suffix = m.group(2)?.toLowerCase();
  final raw = suffix == null ? t : t.substring(0, t.length - 1);
  final parsed = double.parse(raw);
  final isFloat = suffix == 'f';
  return JavaNumber(
    isFloat ? toFloat32(parsed) : parsed,
    isFloat: isFloat,
    isInteger: suffix == null && m.group(1) == null,
  );
}

/// Like [tryParseJavaNumber], but throws.
JavaNumber parseJavaNumber(String text) =>
    tryParseJavaNumber(text) ?? (throw JavaParseError('Not a number: `$text`'));

/// Rounds [value] to the nearest 32-bit float, as Java does for `float`.
double toFloat32(double value) => (Float32List(1)..[0] = value)[0];

/// `"text"` to `text`.
String parseJavaString(String text) {
  final t = text.trim();
  if (t.length < 2 || !t.startsWith('"') || !t.endsWith('"')) {
    throw JavaParseError('Not a string literal: `$text`');
  }
  return t.substring(1, t.length - 1);
}
