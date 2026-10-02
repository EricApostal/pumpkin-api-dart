/// A backtracking regular expression engine with ECMAScript semantics, which
/// is what `dart:core`'s `RegExp` is specified to follow.
///
/// Standalone dart2wasm delegates regular expressions to the embedder, and the
/// embedder has none. This implementation is pure Dart (no `dart:_wasm`), so
/// it can be tested against the VM's own `RegExp`.
library;

/// Read access to the UTF-16 code units of the string being matched.
abstract interface class CodeUnits {
  int get length;
  int operator [](int index);
}

/// A [CodeUnits] view of a Dart string.
final class StringCodeUnits implements CodeUnits {
  final String _string;

  StringCodeUnits(this._string);

  @override
  int get length => _string.length;

  @override
  int operator [](int index) => _string.codeUnitAt(index);
}

/// Thrown by [CompiledRegExp] for patterns that are not valid.
final class RegExpSyntaxError implements Exception {
  final String message;

  RegExpSyntaxError(this.message);

  @override
  String toString() => message;
}

/// The result of a successful match.
final class RegExpMatchData {
  /// The start offsets of the whole match (index 0) and of every group, or -1
  /// for groups that didn't participate.
  final List<int> starts;

  /// The end offsets, like [starts].
  final List<int> ends;

  RegExpMatchData(this.starts, this.ends);

  int get start => starts[0];
  int get end => ends[0];
  int get groupCount => starts.length - 1;
}

/// A compiled regular expression.
final class CompiledRegExp {
  final bool multiLine;
  final bool caseSensitive;
  final bool unicode;
  final bool dotAll;

  late final _Node _root;
  late final int groupCount;

  /// Names of the named groups in order of appearance, and their group index.
  final List<String> groupNames = [];
  final List<int> groupNameIndices = [];

  CompiledRegExp(
    String pattern, {
    this.multiLine = false,
    this.caseSensitive = true,
    this.unicode = false,
    this.dotAll = false,
  }) {
    final parser = _Parser(pattern, unicode);
    _root = parser.parse();
    groupCount = parser.groupCount;
    groupNames.addAll(parser.groupNames);
    groupNameIndices.addAll(parser.groupNameIndices);
  }

  /// Finds the first match at or after [start]. With [asPrefix], only a match
  /// starting exactly at [start] counts.
  RegExpMatchData? match(CodeUnits input, int start, bool asPrefix) {
    final matcher = _Matcher(this, input);
    for (var position = start; position <= input.length;) {
      final result = matcher.matchAt(position);
      if (result != null || asPrefix) return result;

      if (unicode &&
          position + 1 < input.length &&
          _isHighSurrogate(input[position]) &&
          _isLowSurrogate(input[position + 1])) {
        position += 2;
      } else {
        position++;
      }
    }
    return null;
  }

  /// Escapes characters that are special in regular expressions.
  static String escape(String text) {
    const special = r'\^$.*+?()[]{}|/';
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (special.contains(c)) buffer.write(r'\');
      buffer.write(c);
    }
    return buffer.toString();
  }
}

bool _isHighSurrogate(int c) => c >= 0xd800 && c <= 0xdbff;
bool _isLowSurrogate(int c) => c >= 0xdc00 && c <= 0xdfff;

bool _isLineTerminator(int c) =>
    c == 0x0a || c == 0x0d || c == 0x2028 || c == 0x2029;

bool _isWordChar(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5a) ||
    (c >= 0x61 && c <= 0x7a) ||
    c == 0x5f;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isSpace(int c) =>
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

/// Simple upper-case folding for case-insensitive matching.
int _fold(int c) {
  if (c < 0x80) {
    return c >= 0x61 && c <= 0x7a ? c - 0x20 : c;
  }
  if (c >= 0xe0 && c <= 0xfe && c != 0xf7) return c - 0x20;
  if (c == 0xff) return 0x178;
  if (c >= 0x3b1 && c <= 0x3c9 && c != 0x3c2) return c - 0x20;
  if (c == 0x3c2) return 0x3a3;
  if (c >= 0x430 && c <= 0x44f) return c - 0x20;
  if (c >= 0x450 && c <= 0x45f) return c - 0x50;
  if (c >= 0x100 && c <= 0x17f && c.isOdd && c != 0x131 && c != 0x138) {
    // Latin Extended-A pairs are (upper, lower) = (even, odd) in most blocks.
    if (c < 0x138 || c > 0x148) return c - 1;
  }
  return c;
}

/// The code point at [index] (joining surrogate pairs in unicode mode).
int _codePointAt(CodeUnits input, int index, bool unicode) {
  final c = input[index];
  if (unicode &&
      _isHighSurrogate(c) &&
      index + 1 < input.length &&
      _isLowSurrogate(input[index + 1])) {
    return 0x10000 + ((c - 0xd800) << 10) + (input[index + 1] - 0xdc00);
  }
  return c;
}

int _width(int codePoint) => codePoint > 0xffff ? 2 : 1;

// ---------------------------------------------------------------------------
// Syntax tree
// ---------------------------------------------------------------------------

sealed class _Node {}

final class _Empty extends _Node {}

final class _Char extends _Node {
  final int codePoint;

  _Char(this.codePoint);
}

final class _Any extends _Node {}

enum _ClassKind { digit, notDigit, word, notWord, space, notSpace }

final class _ClassItem {
  final int low;
  final int high;
  final _ClassKind? kind;

  _ClassItem.range(this.low, this.high) : kind = null;
  _ClassItem.kind(this.kind) : low = 0, high = 0;

  bool matches(int c) {
    return switch (kind) {
      null => c >= low && c <= high,
      _ClassKind.digit => _isDigit(c),
      _ClassKind.notDigit => !_isDigit(c),
      _ClassKind.word => _isWordChar(c),
      _ClassKind.notWord => !_isWordChar(c),
      _ClassKind.space => _isSpace(c),
      _ClassKind.notSpace => !_isSpace(c),
    };
  }
}

final class _Class extends _Node {
  final List<_ClassItem> items;
  final bool negated;

  _Class(this.items, this.negated);
}

final class _Sequence extends _Node {
  final List<_Node> nodes;

  _Sequence(this.nodes);
}

final class _Alternation extends _Node {
  final List<_Node> alternatives;

  _Alternation(this.alternatives);
}

final class _Group extends _Node {
  final _Node body;

  /// The capture index, or null for a non-capturing group.
  final int? index;

  /// The range of capture indices contained in [body] (inclusive start,
  /// exclusive end), reset on every loop iteration.
  final int firstInner;
  final int endInner;

  _Group(this.body, this.index, this.firstInner, this.endInner);
}

final class _Repeat extends _Node {
  final _Node body;
  final int min;
  final int max; // -1 for unbounded
  final bool greedy;
  final int firstInner;
  final int endInner;

  _Repeat(
    this.body,
    this.min,
    this.max,
    this.greedy,
    this.firstInner,
    this.endInner,
  );
}

enum _AssertionKind { start, end, wordBoundary, notWordBoundary }

final class _Assertion extends _Node {
  final _AssertionKind kind;

  _Assertion(this.kind);
}

final class _Look extends _Node {
  final _Node body;
  final bool ahead;
  final bool negated;

  _Look(this.body, this.ahead, this.negated);
}

final class _BackReference extends _Node {
  final int? index;
  final String? name;

  _BackReference(this.index, this.name);
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

/// `^$\.*+?()[]{}|/-`
const _syntaxCharacters = [
  0x5e, 0x24, 0x5c, 0x2e, 0x2a, 0x2b, 0x3f, 0x28, 0x29, 0x5b, 0x5d, 0x7b, //
  0x7d, 0x7c, 0x2f, 0x2d,
];

final class _Parser {
  final String _source;
  final bool _unicode;
  var _position = 0;

  int groupCount = 0;
  final List<String> groupNames = [];
  final List<int> groupNameIndices = [];
  final List<_BackReference> _pendingNamedReferences = [];
  int _maxNumericReference = 0;
  bool _hasNamedGroups = false;

  _Parser(this._source, this._unicode) {
    // Named groups change how `\k` is parsed, so look ahead for them.
    for (var i = _source.indexOf('(?<'); i >= 0; i = _source.indexOf('(?<', i + 1)) {
      final after = i + 3 < _source.length ? _source.codeUnitAt(i + 3) : -1;
      if (after != 0x3d && after != 0x21) {
        _hasNamedGroups = true;
        break;
      }
    }
  }

  _Node parse() {
    final node = _parseDisjunction();
    if (_position < _source.length) {
      if (_peek() == 0x29) throw RegExpSyntaxError('Unmatched )');
      throw RegExpSyntaxError('Unexpected character');
    }
    for (final reference in _pendingNamedReferences) {
      if (!groupNames.contains(reference.name)) {
        throw RegExpSyntaxError('Invalid named capture referenced');
      }
    }
    if (_unicode && _maxNumericReference > groupCount) {
      throw RegExpSyntaxError('Invalid escape');
    }
    return node;
  }

  bool get _atEnd => _position >= _source.length;

  int _peek([int offset = 0]) {
    final index = _position + offset;
    return index < _source.length ? _source.codeUnitAt(index) : -1;
  }

  bool _eat(int c) {
    if (_peek() == c) {
      _position++;
      return true;
    }
    return false;
  }

  bool _eatString(String s) {
    if (_source.startsWith(s, _position)) {
      _position += s.length;
      return true;
    }
    return false;
  }

  _Node _parseDisjunction() {
    final alternatives = [_parseAlternative()];
    while (_eat(0x7c)) {
      alternatives.add(_parseAlternative());
    }
    return alternatives.length == 1
        ? alternatives.single
        : _Alternation(alternatives);
  }

  _Node _parseAlternative() {
    final nodes = <_Node>[];
    while (!_atEnd && _peek() != 0x7c && _peek() != 0x29) {
      nodes.add(_parseTerm());
    }
    if (nodes.isEmpty) return _Empty();
    return nodes.length == 1 ? nodes.single : _Sequence(nodes);
  }

  _Node _parseTerm() {
    final groupsBefore = groupCount;
    final c = _peek();

    // Assertions.
    if (c == 0x5e) {
      _position++;
      return _Assertion(_AssertionKind.start);
    }
    if (c == 0x24) {
      _position++;
      return _Assertion(_AssertionKind.end);
    }
    if (c == 0x5c && _peek(1) == 0x62) {
      _position += 2;
      return _Assertion(_AssertionKind.wordBoundary);
    }
    if (c == 0x5c && _peek(1) == 0x42) {
      _position += 2;
      return _Assertion(_AssertionKind.notWordBoundary);
    }
    for (final (prefix, ahead, negated) in const [
      ('(?=', true, false),
      ('(?!', true, true),
      ('(?<=', false, false),
      ('(?<!', false, true),
    ]) {
      if (_eatString(prefix)) {
        final body = _parseDisjunction();
        if (!_eat(0x29)) throw RegExpSyntaxError('Unterminated group');
        final look = _Look(body, ahead, negated);
        // Lookaheads can be quantified in legacy mode, but it is meaningless.
        return look;
      }
    }

    final atom = _parseAtom();
    return _parseQuantifier(atom, groupsBefore);
  }

  _Node _parseQuantifier(_Node atom, int groupsBefore) {
    int min, max;
    final c = _peek();
    if (c == 0x2a) {
      _position++;
      min = 0;
      max = -1;
    } else if (c == 0x2b) {
      _position++;
      min = 1;
      max = -1;
    } else if (c == 0x3f) {
      _position++;
      min = 0;
      max = 1;
    } else if (c == 0x7b) {
      final saved = _position;
      final bounds = _tryParseBraces();
      if (bounds == null) {
        _position = saved;
        return atom;
      }
      (min, max) = bounds;
    } else {
      return atom;
    }

    if (max != -1 && min > max) {
      throw RegExpSyntaxError('numbers out of order in {} quantifier');
    }
    final greedy = !_eat(0x3f);
    return _Repeat(atom, min, max, greedy, groupsBefore + 1, groupCount + 1);
  }

  (int, int)? _tryParseBraces() {
    _position++; // {
    final min = _parseInteger();
    if (min == null) return null;
    int max;
    if (_eat(0x2c)) {
      if (_peek() == 0x7d) {
        max = -1;
      } else {
        final parsed = _parseInteger();
        if (parsed == null) return null;
        max = parsed;
      }
    } else {
      max = min;
    }
    if (!_eat(0x7d)) return null;
    return (min, max);
  }

  int? _parseInteger() {
    var value = 0;
    var any = false;
    while (_peek() >= 0x30 && _peek() <= 0x39) {
      value = value * 10 + (_peek() - 0x30);
      if (value > 0x7fffffff) value = 0x7fffffff;
      _position++;
      any = true;
    }
    return any ? value : null;
  }

  _Node _parseAtom() {
    final c = _peek();
    switch (c) {
      case 0x28: // (
        return _parseGroup();
      case 0x2e: // .
        _position++;
        return _Any();
      case 0x5b: // [
        return _parseClass();
      case 0x5c: // \
        return _parseEscape();
      case 0x2a || 0x2b || 0x3f:
        throw RegExpSyntaxError('Nothing to repeat');
      case 0x7b:
        // A lone { is literal unless it forms a valid quantifier.
        final saved = _position;
        if (_tryParseBraces() != null) {
          throw RegExpSyntaxError('Nothing to repeat');
        }
        _position = saved + 1;
        return _Char(0x7b);
      case 0x29:
        throw RegExpSyntaxError('Unmatched )');
    }
    return _Char(_readSourceCodePoint());
  }

  int _readSourceCodePoint() {
    final c = _source.codeUnitAt(_position++);
    if (_unicode &&
        _isHighSurrogate(c) &&
        _position < _source.length &&
        _isLowSurrogate(_source.codeUnitAt(_position))) {
      final low = _source.codeUnitAt(_position++);
      return 0x10000 + ((c - 0xd800) << 10) + (low - 0xdc00);
    }
    return c;
  }

  _Node _parseGroup() {
    _position++; // (
    final firstInner = groupCount + 1;
    if (_eatString('?:')) {
      final body = _parseDisjunction();
      if (!_eat(0x29)) throw RegExpSyntaxError('Unterminated group');
      return _Group(body, null, firstInner, groupCount + 1);
    }
    if (_peek() == 0x3f && _peek(1) == 0x3c) {
      _position += 2;
      final name = _parseGroupName();
      if (groupNames.contains(name)) {
        throw RegExpSyntaxError('Duplicate capture group name');
      }
      final index = ++groupCount;
      groupNames.add(name);
      groupNameIndices.add(index);
      final body = _parseDisjunction();
      if (!_eat(0x29)) throw RegExpSyntaxError('Unterminated group');
      return _Group(body, index, index, groupCount + 1);
    }
    if (_peek() == 0x3f) {
      throw RegExpSyntaxError('Invalid group');
    }
    final index = ++groupCount;
    final body = _parseDisjunction();
    if (!_eat(0x29)) throw RegExpSyntaxError('Unterminated group');
    return _Group(body, index, index, groupCount + 1);
  }

  String _parseGroupName() {
    final start = _position;
    while (!_atEnd && _peek() != 0x3e) {
      final c = _peek();
      final valid =
          _isWordChar(c) || c == 0x24 || c > 0x7f; // Identifier-ish.
      if (!valid) throw RegExpSyntaxError('Invalid capture group name');
      _position++;
    }
    if (_atEnd || _position == start) {
      throw RegExpSyntaxError('Invalid capture group name');
    }
    final name = _source.substring(start, _position);
    _position++; // >
    if (_isDigit(name.codeUnitAt(0))) {
      throw RegExpSyntaxError('Invalid capture group name');
    }
    return name;
  }

  _Node _parseEscape() {
    _position++; // \
    if (_atEnd) throw RegExpSyntaxError(r'\ at end of pattern');
    final c = _peek();

    final kind = _classEscapeKind(c);
    if (kind != null) {
      _position++;
      return _Class([_ClassItem.kind(kind)], false);
    }

    // Back references.
    if (c >= 0x31 && c <= 0x39) {
      final saved = _position;
      final number = _parseInteger()!;
      _maxNumericReference = number > _maxNumericReference
          ? number
          : _maxNumericReference;
      // In legacy mode, a reference to a group that doesn't exist is an octal
      // escape. Groups defined later still count, so this is resolved when
      // matching: here we accept anything up to the final group count.
      if (_unicode || _countGroupsInSource() >= number) {
        return _BackReference(number, null);
      }
      _position = saved;
      return _parseLegacyOctalOrIdentity();
    }
    if (c == 0x6b && (_unicode || _hasNamedGroups)) {
      _position++;
      if (!_eat(0x3c)) throw RegExpSyntaxError('Invalid named reference');
      final name = _parseGroupName();
      final reference = _BackReference(null, name);
      _pendingNamedReferences.add(reference);
      return reference;
    }

    return _Char(_parseCharacterEscape(inClass: false));
  }

  int _countGroupsInSource() {
    // Counts capturing groups in the whole source, ignoring escapes and
    // classes, to decide if `\N` is a back reference.
    var count = 0;
    var inClass = false;
    for (var i = 0; i < _source.length; i++) {
      final c = _source.codeUnitAt(i);
      if (c == 0x5c) {
        i++;
      } else if (inClass) {
        if (c == 0x5d) inClass = false;
      } else if (c == 0x5b) {
        inClass = true;
      } else if (c == 0x28) {
        final next = i + 1 < _source.length ? _source.codeUnitAt(i + 1) : -1;
        if (next != 0x3f) {
          count++;
        } else if (i + 2 < _source.length &&
            _source.codeUnitAt(i + 2) == 0x3c &&
            i + 3 < _source.length &&
            _source.codeUnitAt(i + 3) != 0x3d &&
            _source.codeUnitAt(i + 3) != 0x21) {
          count++;
        }
      }
    }
    return count;
  }

  _Node _parseLegacyOctalOrIdentity() {
    final c = _peek();
    if (c >= 0x30 && c <= 0x37) {
      var value = 0;
      var digits = 0;
      while (digits < 3 && _peek() >= 0x30 && _peek() <= 0x37) {
        final next = value * 8 + (_peek() - 0x30);
        if (next > 0xff) break;
        value = next;
        _position++;
        digits++;
      }
      return _Char(value);
    }
    _position++;
    return _Char(c);
  }

  _ClassKind? _classEscapeKind(int c) {
    return switch (c) {
      0x64 => _ClassKind.digit, // d
      0x44 => _ClassKind.notDigit, // D
      0x77 => _ClassKind.word, // w
      0x57 => _ClassKind.notWord, // W
      0x73 => _ClassKind.space, // s
      0x53 => _ClassKind.notSpace, // S
      _ => null,
    };
  }

  /// Parses the escape after a `\` that stands for a single character.
  int _parseCharacterEscape({required bool inClass}) {
    final c = _peek();
    _position++;
    switch (c) {
      case 0x74:
        return 0x09; // t
      case 0x6e:
        return 0x0a; // n
      case 0x76:
        return 0x0b; // v
      case 0x66:
        return 0x0c; // f
      case 0x72:
        return 0x0d; // r
      case 0x62 when inClass:
        return 0x08;
      case 0x30:
        if (!(_peek() >= 0x30 && _peek() <= 0x39)) return 0;
        _position--;
        return _parseLegacyOctalOrIdentityValue();
      case 0x63: // \cX
        final letter = _peek();
        if ((letter >= 0x41 && letter <= 0x5a) ||
            (letter >= 0x61 && letter <= 0x7a)) {
          _position++;
          return letter % 32;
        }
        _position--; // Treat the backslash as a literal.
        return 0x5c;
      case 0x78: // \xHH
        final value = _tryHex(2);
        if (value != null) return value;
        return 0x78;
      case 0x75: // \uHHHH or \u{...}
        if (_unicode && _peek() == 0x7b) {
          final saved = _position;
          _position++;
          var value = 0;
          var any = false;
          while (_peek() != 0x7d) {
            final digit = _hexValue(_peek());
            if (digit < 0) {
              _position = saved;
              throw RegExpSyntaxError('Invalid Unicode escape');
            }
            value = value * 16 + digit;
            if (value > 0x10ffff) {
              throw RegExpSyntaxError('Invalid Unicode escape');
            }
            _position++;
            any = true;
          }
          if (!any) throw RegExpSyntaxError('Invalid Unicode escape');
          _position++;
          return value;
        }
        final value = _tryHex(4);
        if (value != null) {
          // Join surrogate pairs written as two escapes in unicode mode.
          if (_unicode &&
              _isHighSurrogate(value) &&
              _peek() == 0x5c &&
              _peek(1) == 0x75) {
            final saved = _position;
            _position += 2;
            final low = _tryHex(4);
            if (low != null && _isLowSurrogate(low)) {
              return 0x10000 + ((value - 0xd800) << 10) + (low - 0xdc00);
            }
            _position = saved;
          }
          return value;
        }
        if (_unicode) throw RegExpSyntaxError('Invalid Unicode escape');
        return 0x75;
    }
    if (_unicode) {
      // Only syntax characters and `/` can be identity escaped.
      if (_syntaxCharacters.contains(c)) return c;
      throw RegExpSyntaxError('Invalid escape');
    }
    if (c >= 0x31 && c <= 0x37) {
      _position--;
      return _parseLegacyOctalOrIdentityValue();
    }
    _position--;
    return _readSourceCodePoint();
  }

  int _parseLegacyOctalOrIdentityValue() {
    var value = 0;
    var digits = 0;
    while (digits < 3 && _peek() >= 0x30 && _peek() <= 0x37) {
      final next = value * 8 + (_peek() - 0x30);
      if (next > 0xff) break;
      value = next;
      _position++;
      digits++;
    }
    if (digits == 0) {
      final c = _peek();
      _position++;
      return c;
    }
    return value;
  }

  int? _tryHex(int digits) {
    var value = 0;
    for (var i = 0; i < digits; i++) {
      final digit = _hexValue(_peek(i));
      if (digit < 0) return null;
      value = value * 16 + digit;
    }
    _position += digits;
    return value;
  }

  int _hexValue(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    return -1;
  }

  _Node _parseClass() {
    _position++; // [
    final negated = _eat(0x5e);
    final items = <_ClassItem>[];

    while (true) {
      if (_atEnd) throw RegExpSyntaxError('Unterminated character class');
      if (_eat(0x5d)) break;

      final first = _parseClassAtom();
      if (_peek() == 0x2d && _peek(1) != 0x5d && _peek(1) != -1) {
        final saved = _position;
        _position++; // -
        final second = _parseClassAtom();
        if (first is _ClassItem || second is _ClassItem) {
          // A range with a class escape: `-` is literal (legacy), or an
          // error in unicode mode.
          if (_unicode) {
            throw RegExpSyntaxError('Invalid character class');
          }
          _addClassAtom(items, first);
          items.add(_ClassItem.range(0x2d, 0x2d));
          _addClassAtom(items, second);
          continue;
        }
        if ((first as int) > (second as int)) {
          _position = saved;
          throw RegExpSyntaxError('Range out of order in character class');
        }
        items.add(_ClassItem.range(first, second));
      } else {
        _addClassAtom(items, first);
      }
    }
    return _Class(items, negated);
  }

  void _addClassAtom(List<_ClassItem> items, Object atom) {
    if (atom is _ClassItem) {
      items.add(atom);
    } else {
      items.add(_ClassItem.range(atom as int, atom));
    }
  }

  /// Parses one class member: an `int` code point or a [_ClassItem] for escapes
  /// like `\d`.
  Object _parseClassAtom() {
    final c = _peek();
    if (c == 0x5c) {
      _position++;
      if (_atEnd) throw RegExpSyntaxError(r'\ at end of pattern');
      final kind = _classEscapeKind(_peek());
      if (kind != null) {
        _position++;
        return _ClassItem.kind(kind);
      }
      if (_peek() == 0x2d && _unicode) {
        _position++;
        return 0x2d;
      }
      return _parseCharacterEscape(inClass: true);
    }
    return _readSourceCodePoint();
  }
}

// ---------------------------------------------------------------------------
// Matcher
// ---------------------------------------------------------------------------

typedef _Continuation = bool Function(int position);

final class _Matcher {
  final CompiledRegExp _regExp;
  final CodeUnits _input;
  final List<int> _starts;
  final List<int> _ends;

  _Matcher(this._regExp, this._input)
    : _starts = List.filled(_regExp.groupCount + 1, -1),
      _ends = List.filled(_regExp.groupCount + 1, -1);

  RegExpMatchData? matchAt(int start) {
    for (var i = 0; i < _starts.length; i++) {
      _starts[i] = -1;
      _ends[i] = -1;
    }
    var matchedEnd = -1;
    final matched = _match(_regExp._root, start, (end) {
      matchedEnd = end;
      return true;
    });
    if (!matched) return null;
    _starts[0] = start;
    _ends[0] = matchedEnd;
    return RegExpMatchData(List.of(_starts), List.of(_ends));
  }

  bool get _unicode => _regExp.unicode;

  bool _match(_Node node, int position, _Continuation next) {
    switch (node) {
      case _Empty():
        return next(position);
      case _Char() || _Any() || _Class():
        final width = _matchSingle(node, position);
        return width >= 0 && next(position + width);
      case _Sequence():
        return _matchSequence(node.nodes, 0, position, next);
      case _Alternation():
        for (final alternative in node.alternatives) {
          if (_match(alternative, position, next)) return true;
        }
        return false;
      case _Group():
        return _matchGroup(node, position, next);
      case _Repeat():
        return _matchRepeat(node, position, next);
      case _Assertion():
        return _checkAssertion(node.kind, position) && next(position);
      case _Look():
        return _matchLook(node, position, next);
      case _BackReference():
        return _matchBackReference(node, position, next);
    }
  }

  /// The number of code units matched by a single-character [node] at
  /// [position], or -1.
  int _matchSingle(_Node node, int position) {
    if (position >= _input.length) return -1;
    final c = _codePointAt(_input, position, _unicode);
    final width = _width(c);
    switch (node) {
      case _Char():
        final expected = node.codePoint;
        if (c == expected) return width;
        if (!_regExp.caseSensitive && _fold(c) == _fold(expected)) return width;
        return -1;
      case _Any():
        if (!_regExp.dotAll && _isLineTerminator(c)) return -1;
        return width;
      case _Class():
        return _classMatches(node, c) ? width : -1;
      default:
        return -1;
    }
  }

  bool _classMatches(_Class node, int c) {
    var found = _anyItemMatches(node.items, c);
    if (!found && !_regExp.caseSensitive) {
      found = _anyItemMatches(node.items, _fold(c)) ||
          _anyItemMatches(node.items, _lower(_fold(c)));
    }
    return found != node.negated;
  }

  bool _anyItemMatches(List<_ClassItem> items, int c) {
    for (final item in items) {
      if (item.matches(c)) return true;
    }
    return false;
  }

  int _lower(int c) {
    if (c >= 0x41 && c <= 0x5a) return c + 0x20;
    if (c >= 0xc0 && c <= 0xde && c != 0xd7) return c + 0x20;
    if (c >= 0x391 && c <= 0x3a9) return c + 0x20;
    if (c >= 0x410 && c <= 0x42f) return c + 0x20;
    if (c >= 0x400 && c <= 0x40f) return c + 0x50;
    return c;
  }

  bool _matchSequence(
    List<_Node> nodes,
    int index,
    int position,
    _Continuation next,
  ) {
    if (index == nodes.length) return next(position);
    return _match(
      nodes[index],
      position,
      (end) => _matchSequence(nodes, index + 1, end, next),
    );
  }

  bool _matchGroup(_Group node, int position, _Continuation next) {
    final index = node.index;
    if (index == null) return _match(node.body, position, next);

    final oldStart = _starts[index];
    final oldEnd = _ends[index];
    final matched = _match(node.body, position, (end) {
      final previousStart = _starts[index];
      final previousEnd = _ends[index];
      _starts[index] = position;
      _ends[index] = end;
      if (next(end)) return true;
      _starts[index] = previousStart;
      _ends[index] = previousEnd;
      return false;
    });
    if (!matched) {
      _starts[index] = oldStart;
      _ends[index] = oldEnd;
    }
    return matched;
  }

  bool _matchRepeat(_Repeat node, int position, _Continuation next) {
    final body = node.body;
    if (body is _Char || body is _Any || body is _Class) {
      return _matchSimpleRepeat(node, body, position, next);
    }
    return _repeatStep(node, position, 0, next);
  }

  /// Repeats a single-character matcher without recursing per character.
  bool _matchSimpleRepeat(
    _Repeat node,
    _Node body,
    int position,
    _Continuation next,
  ) {
    final positions = <int>[position];
    var count = 0;
    var current = position;
    final limit = node.max;

    if (node.greedy) {
      while (limit < 0 || count < limit) {
        final width = _matchSingle(body, current);
        if (width < 0) break;
        current += width;
        count++;
        positions.add(current);
      }
      for (var i = count; i >= node.min; i--) {
        if (next(positions[i])) return true;
      }
      return false;
    }

    // Lazy: try the continuation before consuming more.
    while (true) {
      if (count >= node.min && next(current)) return true;
      if (limit >= 0 && count >= limit) return false;
      final width = _matchSingle(body, current);
      if (width < 0) return false;
      current += width;
      count++;
    }
  }

  void _clearCaptures(_Repeat node) {
    for (var i = node.firstInner; i < node.endInner; i++) {
      _starts[i] = -1;
      _ends[i] = -1;
    }
  }

  bool _repeatStep(_Repeat node, int position, int count, _Continuation next) {
    final canStop = count >= node.min;
    final canContinue = node.max < 0 || count < node.max;

    bool iterate() {
      // Save captures that this iteration would reset, to restore on failure.
      final savedStarts = _starts.sublist(node.firstInner, node.endInner);
      final savedEnds = _ends.sublist(node.firstInner, node.endInner);
      _clearCaptures(node);
      final matched = _match(node.body, position, (end) {
        // An iteration that consumes nothing can't make progress.
        if (end == position && count >= node.min) return false;
        return _repeatStep(node, end, count + 1, next);
      });
      if (!matched) {
        for (var i = 0; i < savedStarts.length; i++) {
          _starts[node.firstInner + i] = savedStarts[i];
          _ends[node.firstInner + i] = savedEnds[i];
        }
      }
      return matched;
    }

    if (node.greedy) {
      if (canContinue && iterate()) return true;
      return canStop && next(position);
    }
    if (canStop && next(position)) return true;
    return canContinue && iterate();
  }

  bool _checkAssertion(_AssertionKind kind, int position) {
    switch (kind) {
      case _AssertionKind.start:
        if (position == 0) return true;
        return _regExp.multiLine && _isLineTerminator(_input[position - 1]);
      case _AssertionKind.end:
        if (position == _input.length) return true;
        return _regExp.multiLine && _isLineTerminator(_input[position]);
      case _AssertionKind.wordBoundary:
      case _AssertionKind.notWordBoundary:
        final before = position > 0 && _isWordChar(_input[position - 1]);
        final after =
            position < _input.length && _isWordChar(_input[position]);
        final boundary = before != after;
        return kind == _AssertionKind.wordBoundary ? boundary : !boundary;
    }
  }

  bool _matchLook(_Look node, int position, _Continuation next) {
    bool found;
    final savedStarts = List.of(_starts);
    final savedEnds = List.of(_ends);

    if (node.ahead) {
      found = _match(node.body, position, (_) => true);
    } else {
      found = false;
      for (var start = position; start >= 0 && !found; start--) {
        found = _match(node.body, start, (end) => end == position);
      }
    }

    if (node.negated) {
      // Captures made inside a negative look never survive.
      _restore(savedStarts, savedEnds);
      return !found && next(position);
    }
    if (!found) {
      _restore(savedStarts, savedEnds);
      return false;
    }
    if (next(position)) return true;
    _restore(savedStarts, savedEnds);
    return false;
  }

  void _restore(List<int> starts, List<int> ends) {
    for (var i = 0; i < starts.length; i++) {
      _starts[i] = starts[i];
      _ends[i] = ends[i];
    }
  }

  bool _matchBackReference(
    _BackReference node,
    int position,
    _Continuation next,
  ) {
    var index = node.index;
    if (index == null) {
      final nameIndex = _regExp.groupNames.indexOf(node.name!);
      index = nameIndex < 0 ? null : _regExp.groupNameIndices[nameIndex];
    }
    if (index == null || index >= _starts.length) return next(position);
    final start = _starts[index];
    final end = _ends[index];
    if (start < 0 || end < 0) return next(position);

    final length = end - start;
    if (position + length > _input.length) return false;
    for (var i = 0; i < length; i++) {
      final a = _input[start + i];
      final b = _input[position + i];
      if (a != b && (_regExp.caseSensitive || _fold(a) != _fold(b))) {
        return false;
      }
    }
    return next(position + length);
  }
}
