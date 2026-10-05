// Lua patterns, ported from the reference implementation (`lstrlib.c`).
import '../value.dart';

const int _capUnfinished = -1;
const int _capPosition = -2;
const int _maxCaptures = 32;
const int _maxRecursion = 200;
const int _esc = 37; // %

/// Matching state for one subject string and pattern.
final class PatternMatcher {
  final String src;
  final String pat;
  int level = 0;
  final List<int> _captureStart = List<int>.filled(_maxCaptures, 0);
  final List<int> _captureLen = List<int>.filled(_maxCaptures, 0);
  int _depth = 0;

  PatternMatcher(this.src, this.pat);

  /// Clears the captures before a new match attempt.
  void reset() {
    level = 0;
    _depth = 0;
  }

  Never _error(String message) => throw LuaError.message(message);

  int _srcAt(int i) => i < src.length ? src.codeUnitAt(i) : 0;

  int _patAt(int i) => i < pat.length ? pat.codeUnitAt(i) : 0;

  int _checkCapture(int l) {
    final index = l - 49; // '1'
    if (index < 0 || index >= level || _captureLen[index] == _capUnfinished) {
      _error('invalid capture index %${index + 1}');
    }
    return index;
  }

  int _captureToClose() {
    var l = level;
    for (l--; l >= 0; l--) {
      if (_captureLen[l] == _capUnfinished) return l;
    }
    _error('invalid pattern capture');
  }

  int _classEnd(int p) {
    if (p >= pat.length) _error('malformed pattern (ends with \'%\')');
    final c = pat.codeUnitAt(p++);
    if (c == _esc) {
      if (p >= pat.length) _error("malformed pattern (ends with '%')");
      return p + 1;
    }
    if (c == 91) {
      // [
      if (_patAt(p) == 94) p++;
      do {
        if (p >= pat.length) _error("malformed pattern (missing ']')");
        final d = pat.codeUnitAt(p++);
        if (d == _esc && p < pat.length) p++;
      } while (_patAt(p) != 93 || p >= pat.length);
      return p + 1;
    }
    return p;
  }

  static bool _isAlpha(int c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
  static bool _isDigit(int c) => c >= 48 && c <= 57;
  static bool _isLower(int c) => c >= 97 && c <= 122;
  static bool _isUpper(int c) => c >= 65 && c <= 90;
  static bool _isSpace(int c) => c == 32 || (c >= 9 && c <= 13);
  static bool _isControl(int c) => c < 32 || c == 127;
  static bool _isPunct(int c) =>
      (c >= 33 && c <= 47) ||
      (c >= 58 && c <= 64) ||
      (c >= 91 && c <= 96) ||
      (c >= 123 && c <= 126);
  static bool _isHex(int c) =>
      _isDigit(c) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70);

  static bool _matchClass(int c, int cl) {
    final lower = cl | 0x20;
    bool result;
    switch (lower) {
      case 97: // a
        result = _isAlpha(c);
      case 99: // c
        result = _isControl(c);
      case 100: // d
        result = _isDigit(c);
      case 108: // l
        result = _isLower(c);
      case 112: // p
        result = _isPunct(c);
      case 115: // s
        result = _isSpace(c);
      case 117: // u
        result = _isUpper(c);
      case 119: // w
        result = _isAlpha(c) || _isDigit(c);
      case 120: // x
        result = _isHex(c);
      case 122: // z
        result = c == 0;
      default:
        return cl == c;
    }
    return _isUpper(cl) ? !result : result;
  }

  bool _matchBracketClass(int c, int p, int ec) {
    var sig = true;
    if (_patAt(p + 1) == 94) {
      sig = false;
      p++;
    }
    while (++p < ec) {
      final pc = pat.codeUnitAt(p);
      if (pc == _esc) {
        p++;
        if (_matchClass(c, pat.codeUnitAt(p))) return sig;
      } else if (_patAt(p + 1) == 45 && p + 2 < ec) {
        p += 2;
        if (pat.codeUnitAt(p - 2) <= c && c <= pat.codeUnitAt(p)) return sig;
      } else if (pc == c) {
        return sig;
      }
    }
    return !sig;
  }

  bool _singleMatch(int s, int p, int ep) {
    if (s >= src.length) return false;
    final c = src.codeUnitAt(s);
    final pc = pat.codeUnitAt(p);
    switch (pc) {
      case 46: // .
        return true;
      case _esc:
        return _matchClass(c, pat.codeUnitAt(p + 1));
      case 91: // [
        return _matchBracketClass(c, p, ep - 1);
      default:
        return pc == c;
    }
  }

  int _matchBalance(int s, int p) {
    if (p + 1 >= pat.length) _error("unbalanced pattern");
    if (s >= src.length || src.codeUnitAt(s) != pat.codeUnitAt(p)) return -1;
    final b = pat.codeUnitAt(p);
    final e = pat.codeUnitAt(p + 1);
    var count = 1;
    while (++s < src.length) {
      final c = src.codeUnitAt(s);
      if (c == e) {
        if (--count == 0) return s + 1;
      } else if (c == b) {
        count++;
      }
    }
    return -1;
  }

  int _maxExpand(int s, int p, int ep) {
    var i = 0;
    while (_singleMatch(s + i, p, ep)) {
      i++;
    }
    while (i >= 0) {
      final result = match(s + i, ep + 1);
      if (result != -1) return result;
      i--;
    }
    return -1;
  }

  int _minExpand(int s, int p, int ep) {
    while (true) {
      final result = match(s, ep + 1);
      if (result != -1) return result;
      if (_singleMatch(s, p, ep)) {
        s++;
      } else {
        return -1;
      }
    }
  }

  int _startCapture(int s, int p, int what) {
    if (level >= _maxCaptures) _error('too many captures');
    _captureStart[level] = s;
    _captureLen[level] = what;
    level++;
    final result = match(s, p);
    if (result == -1) level--;
    return result;
  }

  int _endCapture(int s, int p) {
    final l = _captureToClose();
    _captureLen[l] = s - _captureStart[l];
    final result = match(s, p);
    if (result == -1) _captureLen[l] = _capUnfinished;
    return result;
  }

  int _matchCapture(int s, int l) {
    final index = _checkCapture(l);
    final len = _captureLen[index];
    final start = _captureStart[index];
    if (src.length - s >= len &&
        src.startsWith(src.substring(start, start + len), s)) {
      return s + len;
    }
    return -1;
  }

  /// Tries to match the pattern from [p] at subject position [s]; returns
  /// the end of the match or -1.
  int match(int s, int p) {
    if (++_depth > _maxRecursion) _error('pattern too complex');
    try {
      while (true) {
        if (p >= pat.length) return s;
        final pc = pat.codeUnitAt(p);
        switch (pc) {
          case 40: // (
            if (_patAt(p + 1) == 41) return _startCapture(s, p + 2, _capPosition);
            return _startCapture(s, p + 1, _capUnfinished);
          case 41: // )
            return _endCapture(s, p + 1);
          case _esc:
            final next = _patAt(p + 1);
            if (next == 98) {
              // %b
              s = _matchBalance(s, p + 2);
              if (s == -1) return -1;
              p += 4;
              continue;
            }
            if (next == 102) {
              // %f
              p += 2;
              if (_patAt(p) != 91) _error("missing '[' after '%f' in pattern");
              final ep = _classEnd(p);
              final previous = s == 0 ? 0 : src.codeUnitAt(s - 1);
              if (_matchBracketClass(previous, p, ep - 1) ||
                  !_matchBracketClass(_srcAt(s), p, ep - 1)) {
                return -1;
              }
              p = ep;
              continue;
            }
            if (next >= 48 && next <= 57) {
              s = _matchCapture(s, next);
              if (s == -1) return -1;
              p += 2;
              continue;
            }
          case 36: // $
            if (p + 1 == pat.length) return s == src.length ? s : -1;
        }
        // Default: a single character class, possibly with a quantifier.
        final ep = _classEnd(p);
        final matches = _singleMatch(s, p, ep);
        final quantifier = _patAt(ep);
        if (ep < pat.length && quantifier == 63) {
          // ?
          if (matches) {
            final result = match(s + 1, ep + 1);
            if (result != -1) return result;
          }
          p = ep + 1;
          continue;
        }
        if (ep < pat.length && quantifier == 42) return _maxExpand(s, p, ep);
        if (ep < pat.length && quantifier == 43) {
          return matches ? _maxExpand(s + 1, p, ep) : -1;
        }
        if (ep < pat.length && quantifier == 45) return _minExpand(s, p, ep);
        if (!matches) return -1;
        s++;
        p = ep;
      }
    } finally {
      _depth--;
    }
  }

  /// The value of capture [i] for a match from [s] to [e]: a string, or the
  /// position (1-based) for `()` captures. Capture 0 is the whole match when
  /// the pattern has no captures.
  Object? capture(int i, int s, int e) {
    if (i >= level) {
      if (i == 0) return src.substring(s, e);
      _error('invalid capture index');
    }
    final len = _captureLen[i];
    if (len == _capUnfinished) _error('unfinished capture');
    final start = _captureStart[i];
    if (len == _capPosition) return (start + 1).toDouble();
    return src.substring(start, start + len);
  }

  /// All captures (or the whole match) of a match from [s] to [e].
  List<Object?> captures(int s, int e, {bool wholeIfNone = true}) {
    final n = level == 0 && wholeIfNone ? 1 : level;
    return [for (var i = 0; i < n; i++) capture(i, s, e)];
  }
}

/// Whether [pattern] has no special characters, so a plain search will do.
bool isPlainPattern(String pattern) {
  for (var i = 0; i < pattern.length; i++) {
    switch (pattern.codeUnitAt(i)) {
      case 94: // ^
      case 36: // $
      case 42: // *
      case 43: // +
      case 63: // ?
      case 46: // .
      case 40: // (
      case 41: // )
      case 91: // [
      case 93: // ]
      case 37: // %
      case 45: // -
        return false;
    }
  }
  return true;
}
