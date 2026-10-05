// The tokenizer for Lua 5.1 with the 5.2 additions CC: Tweaked supports
// (`goto`, `::label::`, `\z`, `\xNN`, `\u{...}`, hexadecimal floats).
import 'value.dart';

/// A syntax error, with the message already formatted like Lua's
/// (`chunk:line: message near 'token'`).
final class LuaSyntaxError implements Exception {
  final String message;

  const LuaSyntaxError(this.message);

  @override
  String toString() => message;
}

enum Tok {
  eof,
  name,
  string,
  number,
  kAnd,
  kBreak,
  kDo,
  kElse,
  kElseif,
  kEnd,
  kFalse,
  kFor,
  kFunction,
  kGoto,
  kIf,
  kIn,
  kLocal,
  kNil,
  kNot,
  kOr,
  kRepeat,
  kReturn,
  kThen,
  kTrue,
  kUntil,
  kWhile,
  plus,
  minus,
  star,
  slash,
  percent,
  caret,
  hash,
  eq,
  ne,
  le,
  ge,
  lt,
  gt,
  assign,
  lparen,
  rparen,
  lbrace,
  rbrace,
  lbracket,
  rbracket,
  semicolon,
  colon,
  dbcolon,
  comma,
  dot,
  concat,
  ellipsis,
}

const Map<String, Tok> _keywords = {
  'and': Tok.kAnd,
  'break': Tok.kBreak,
  'do': Tok.kDo,
  'else': Tok.kElse,
  'elseif': Tok.kElseif,
  'end': Tok.kEnd,
  'false': Tok.kFalse,
  'for': Tok.kFor,
  'function': Tok.kFunction,
  'goto': Tok.kGoto,
  'if': Tok.kIf,
  'in': Tok.kIn,
  'local': Tok.kLocal,
  'nil': Tok.kNil,
  'not': Tok.kNot,
  'or': Tok.kOr,
  'repeat': Tok.kRepeat,
  'return': Tok.kReturn,
  'then': Tok.kThen,
  'true': Tok.kTrue,
  'until': Tok.kUntil,
  'while': Tok.kWhile,
};

/// One token. [text] is the name, the string value or the source text.
final class Token {
  final Tok type;
  final String text;
  final double number;
  final int line;

  const Token(this.type, this.text, this.line, [this.number = 0]);
}

/// The display form of a chunk name: `@file` and `=name` show the name, any
/// other chunk shows the first line of its source.
String chunkDisplayName(String chunkName) {
  if (chunkName.startsWith('@') || chunkName.startsWith('=')) {
    return chunkName.substring(1);
  }
  var firstLine = chunkName;
  final newline = firstLine.indexOf('\n');
  var truncated = false;
  if (newline >= 0) {
    firstLine = firstLine.substring(0, newline);
    truncated = true;
  }
  if (firstLine.length > 40) {
    firstLine = firstLine.substring(0, 37);
    truncated = true;
  }
  return '[string "$firstLine${truncated ? '...' : ''}"]';
}

/// Splits [source] into tokens, one at a time.
final class Lexer {
  final String source;
  final String chunk;
  int _pos = 0;
  int line = 1;

  Lexer(this.source, String chunkName) : chunk = chunkDisplayName(chunkName) {
    if (source.startsWith('#')) {
      while (_pos < source.length && !_isNewline(source.codeUnitAt(_pos))) {
        _pos++;
      }
    }
  }

  Never error(String message, {String? near, int? atLine}) {
    final where = near == null ? '' : " near '$near'";
    throw LuaSyntaxError('$chunk:${atLine ?? line}: $message$where');
  }

  int _peekUnit([int offset = 0]) {
    final i = _pos + offset;
    return i < source.length ? source.codeUnitAt(i) : -1;
  }

  static bool _isNewline(int c) => c == 10 || c == 13;
  static bool _isDigit(int c) => c >= 48 && c <= 57;
  static bool _isAlpha(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
  static bool _isAlnum(int c) => _isAlpha(c) || _isDigit(c);

  void _newline() {
    final c = source.codeUnitAt(_pos++);
    final d = _peekUnit();
    if (_isNewline(d) && d != c) _pos++;
    line++;
  }

  /// The next token.
  Token next() {
    while (true) {
      final c = _peekUnit();
      if (c < 0) return Token(Tok.eof, '<eof>', line);
      if (_isNewline(c)) {
        _newline();
      } else if (c == 32 || c == 9 || c == 11 || c == 12) {
        _pos++;
      } else if (c == 45 && _peekUnit(1) == 45) {
        _comment();
      } else {
        break;
      }
    }
    final c = _peekUnit();
    final startLine = line;
    if (_isAlpha(c)) {
      final start = _pos;
      while (_isAlnum(_peekUnit())) {
        _pos++;
      }
      final text = source.substring(start, _pos);
      return Token(_keywords[text] ?? Tok.name, text, startLine);
    }
    if (_isDigit(c) || (c == 46 && _isDigit(_peekUnit(1)))) return _number();
    switch (c) {
      case 34:
      case 39:
        return _string(c);
      case 91: // [
        final level = _longBracketLevel();
        if (level >= 0) {
          final text = _longString(level, 'string');
          return Token(Tok.string, text, startLine);
        }
        _pos++;
        return Token(Tok.lbracket, '[', startLine);
      case 61: // =
        _pos++;
        return _peekUnit() == 61
            ? _two(Tok.eq, '==', startLine)
            : Token(Tok.assign, '=', startLine);
      case 126: // ~
        if (_peekUnit(1) == 61) {
          _pos++;
          return _two(Tok.ne, '~=', startLine);
        }
        break;
      case 60: // <
        _pos++;
        return _peekUnit() == 61
            ? _two(Tok.le, '<=', startLine)
            : Token(Tok.lt, '<', startLine);
      case 62: // >
        _pos++;
        return _peekUnit() == 61
            ? _two(Tok.ge, '>=', startLine)
            : Token(Tok.gt, '>', startLine);
      case 58: // :
        _pos++;
        return _peekUnit() == 58
            ? _two(Tok.dbcolon, '::', startLine)
            : Token(Tok.colon, ':', startLine);
      case 46: // .
        _pos++;
        if (_peekUnit() == 46) {
          _pos++;
          if (_peekUnit() == 46) {
            _pos++;
            return Token(Tok.ellipsis, '...', startLine);
          }
          return Token(Tok.concat, '..', startLine);
        }
        return Token(Tok.dot, '.', startLine);
      case 43:
        return _single(Tok.plus, '+', startLine);
      case 45:
        return _single(Tok.minus, '-', startLine);
      case 42:
        return _single(Tok.star, '*', startLine);
      case 47:
        return _single(Tok.slash, '/', startLine);
      case 37:
        return _single(Tok.percent, '%', startLine);
      case 94:
        return _single(Tok.caret, '^', startLine);
      case 35:
        return _single(Tok.hash, '#', startLine);
      case 40:
        return _single(Tok.lparen, '(', startLine);
      case 41:
        return _single(Tok.rparen, ')', startLine);
      case 123:
        return _single(Tok.lbrace, '{', startLine);
      case 125:
        return _single(Tok.rbrace, '}', startLine);
      case 93:
        return _single(Tok.rbracket, ']', startLine);
      case 59:
        return _single(Tok.semicolon, ';', startLine);
      case 44:
        return _single(Tok.comma, ',', startLine);
    }
    error('unexpected symbol', near: String.fromCharCode(c));
  }

  Token _single(Tok type, String text, int startLine) {
    _pos++;
    return Token(type, text, startLine);
  }

  Token _two(Tok type, String text, int startLine) {
    _pos++;
    return Token(type, text, startLine);
  }

  void _comment() {
    _pos += 2;
    if (_peekUnit() == 91) {
      final level = _longBracketLevel();
      if (level >= 0) {
        _longString(level, 'comment');
        return;
      }
    }
    while (_pos < source.length && !_isNewline(source.codeUnitAt(_pos))) {
      _pos++;
    }
  }

  /// At a `[`: the number of `=` of a long bracket opening (`[==[` is 2), or
  /// -1 if this is not one. Does not consume anything.
  int _longBracketLevel() {
    var i = 1;
    while (_peekUnit(i) == 61) {
      i++;
    }
    return _peekUnit(i) == 91 ? i - 1 : -1;
  }

  String _longString(int level, String what) {
    final startLine = line;
    _pos += level + 2;
    if (_isNewline(_peekUnit())) _newline();
    final out = StringBuffer();
    while (true) {
      final c = _peekUnit();
      if (c < 0) {
        error('unfinished long $what', near: '<eof>', atLine: startLine);
      }
      if (c == 93) {
        var i = 1;
        while (_peekUnit(i) == 61) {
          i++;
        }
        if (i - 1 == level && _peekUnit(i) == 93) {
          _pos += level + 2;
          return out.toString();
        }
        out.writeCharCode(c);
        _pos++;
      } else if (_isNewline(c)) {
        _newline();
        out.write('\n');
      } else {
        out.writeCharCode(c);
        _pos++;
      }
    }
  }

  Token _number() {
    final start = _pos;
    final startLine = line;
    var hex = false;
    if (_peekUnit() == 48 && (_peekUnit(1) == 120 || _peekUnit(1) == 88)) {
      hex = true;
      _pos += 2;
    }
    while (true) {
      final c = _peekUnit();
      final exponent = hex ? (c == 112 || c == 80) : (c == 101 || c == 69);
      if (exponent && (_peekUnit(1) == 43 || _peekUnit(1) == 45)) {
        _pos += 2;
      } else if (_isAlnum(c) || c == 46) {
        _pos++;
      } else {
        break;
      }
    }
    final text = source.substring(start, _pos);
    final value = parseLuaNumber(text);
    if (value == null) error('malformed number', near: text);
    return Token(Tok.number, text, startLine, value);
  }

  Token _string(int quote) {
    _pos++;
    final out = StringBuffer();
    while (true) {
      final c = _peekUnit();
      if (c < 0) error('unfinished string', near: '<eof>');
      if (c == quote) {
        _pos++;
        break;
      }
      if (_isNewline(c)) {
        error('unfinished string', near: String.fromCharCode(quote) + out.toString());
      }
      if (c != 92) {
        out.writeCharCode(c);
        _pos++;
        continue;
      }
      _pos++;
      final e = _peekUnit();
      switch (e) {
        case 97:
          out.writeCharCode(7);
          _pos++;
        case 98:
          out.writeCharCode(8);
          _pos++;
        case 102:
          out.writeCharCode(12);
          _pos++;
        case 110:
          out.writeCharCode(10);
          _pos++;
        case 114:
          out.writeCharCode(13);
          _pos++;
        case 116:
          out.writeCharCode(9);
          _pos++;
        case 118:
          out.writeCharCode(11);
          _pos++;
        case 92:
        case 34:
        case 39:
          out.writeCharCode(e);
          _pos++;
        case 10:
        case 13:
          _newline();
          out.write('\n');
        case 120: // \xNN
          _pos++;
          var value = 0;
          for (var i = 0; i < 2; i++) {
            final d = _hexValue(_peekUnit());
            if (d < 0) error('hexadecimal digit expected', near: '\\x');
            value = value * 16 + d;
            _pos++;
          }
          out.writeCharCode(value);
        case 122: // \z
          _pos++;
          while (true) {
            final w = _peekUnit();
            if (_isNewline(w)) {
              _newline();
            } else if (w == 32 || w == 9 || w == 11 || w == 12) {
              _pos++;
            } else {
              break;
            }
          }
        case 117: // \u{XXX}
          _pos++;
          if (_peekUnit() != 123) error("missing '{' in \\u{xxxx}", near: '\\u');
          _pos++;
          var code = 0;
          var digits = 0;
          while (_hexValue(_peekUnit()) >= 0) {
            code = code * 16 + _hexValue(_peekUnit());
            if (code > 0x7FFFFFFF) error('UTF-8 value too large', near: '\\u');
            digits++;
            _pos++;
          }
          if (digits == 0) error('hexadecimal digit expected', near: '\\u{');
          if (_peekUnit() != 125) error("missing '}' in \\u{xxxx}", near: '\\u');
          _pos++;
          _writeUtf8(out, code);
        default:
          if (_isDigit(e)) {
            var value = 0;
            var digits = 0;
            while (digits < 3 && _isDigit(_peekUnit())) {
              value = value * 10 + (_peekUnit() - 48);
              digits++;
              _pos++;
            }
            if (value > 255) error('decimal escape too large', near: '\\$value');
            out.writeCharCode(value);
          } else {
            error('invalid escape sequence', near: '\\${e < 0 ? '' : String.fromCharCode(e)}');
          }
      }
    }
    return Token(Tok.string, out.toString(), line);
  }

  static int _hexValue(int c) {
    if (c >= 48 && c <= 57) return c - 48;
    if (c >= 97 && c <= 102) return c - 87;
    if (c >= 65 && c <= 70) return c - 55;
    return -1;
  }
}

/// Writes the UTF-8 encoding of [code] into [out], one byte per code unit.
void _writeUtf8(StringBuffer out, int code) {
  if (code < 0x80) {
    out.writeCharCode(code);
  } else if (code < 0x800) {
    out
      ..writeCharCode(0xC0 | (code >> 6))
      ..writeCharCode(0x80 | (code & 0x3F));
  } else if (code < 0x10000) {
    out
      ..writeCharCode(0xE0 | (code >> 12))
      ..writeCharCode(0x80 | ((code >> 6) & 0x3F))
      ..writeCharCode(0x80 | (code & 0x3F));
  } else if (code < 0x200000) {
    out
      ..writeCharCode(0xF0 | (code >> 18))
      ..writeCharCode(0x80 | ((code >> 12) & 0x3F))
      ..writeCharCode(0x80 | ((code >> 6) & 0x3F))
      ..writeCharCode(0x80 | (code & 0x3F));
  } else if (code < 0x4000000) {
    out
      ..writeCharCode(0xF8 | (code >> 24))
      ..writeCharCode(0x80 | ((code >> 18) & 0x3F))
      ..writeCharCode(0x80 | ((code >> 12) & 0x3F))
      ..writeCharCode(0x80 | ((code >> 6) & 0x3F))
      ..writeCharCode(0x80 | (code & 0x3F));
  } else {
    out
      ..writeCharCode(0xFC | (code >> 30))
      ..writeCharCode(0x80 | ((code >> 24) & 0x3F))
      ..writeCharCode(0x80 | ((code >> 18) & 0x3F))
      ..writeCharCode(0x80 | ((code >> 12) & 0x3F))
      ..writeCharCode(0x80 | ((code >> 6) & 0x3F))
      ..writeCharCode(0x80 | (code & 0x3F));
  }
}

/// The UTF-8 encoding of [code] as a byte string.
String utf8Encode(int code) {
  final out = StringBuffer();
  _writeUtf8(out, code);
  return out.toString();
}
