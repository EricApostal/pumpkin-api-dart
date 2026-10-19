// Catnip's `Glob.toRegexPattern` (pure): the glob language of package addresses (`*`, `?`,
// `[a-z]`, `{a,b}`, `{!a}`, `\x`), translated to a regular expression.

const String _regexMetaChars = '.^\$+{[]|()';
const String _globMetaChars = '\\*?[{';

bool _isRegexMeta(String c) => _regexMetaChars.contains(c);
bool _isGlobMeta(String c) => _globMetaChars.contains(c);

class GlobSyntaxException implements Exception {
  final String message;
  const GlobSyntaxException(this.message);

  @override
  String toString() => 'GlobSyntaxException: $message';
}

/// `Glob.toRegexPattern(glob)`; throws a [GlobSyntaxException] for a malformed pattern.
String globToRegexPattern(String glob) {
  var inGroup = false;
  final regex = StringBuffer('^');
  var i = 0;
  var isNegativeLookaround = false;
  var isAnchored = true;

  String next(int at) => at < glob.length ? glob[at] : '\u0000';

  while (i < glob.length) {
    var c = glob[i++];
    switch (c) {
      case '*':
        regex.write('.*');
        if (!inGroup) isAnchored = false;
      case '?':
        regex.write('.');
        if (!inGroup) isAnchored = true;
      case ',':
        if (inGroup) {
          regex.write('|');
        } else {
          regex.write(',');
          isAnchored = true;
        }
      case '[':
        if (next(i) == ']' || (next(i) == '!' && next(i + 1) == ']')) {
          throw const GlobSyntaxException('Cannot have set with no entries');
        }
        regex.write('[');
        if (next(i) == '^') {
          regex.write('\\^');
          i++;
        } else {
          if (next(i) == '!') {
            regex.write('^');
            i++;
          }
          if (next(i) == '-') {
            regex.write('-');
            i++;
          }
        }
        var hasRangeStart = false;
        var last = '\u0000';
        while (i < glob.length) {
          c = glob[i++];
          if (c == ']') break;
          if (c == '\\') {
            if (i == glob.length) throw const GlobSyntaxException('No character to escape');
            if (next(i) == ']' || next(i) == '-' || next(i) == '\\') regex.write('\\');
            regex.write(next(i++));
            continue;
          }
          regex.write(c);
          if (c == '-') {
            if (!hasRangeStart) throw const GlobSyntaxException('Invalid range');
            c = next(i++);
            if (c == '\u0000' || c == ']') break;
            if (c.codeUnitAt(0) < last.codeUnitAt(0)) throw const GlobSyntaxException('Invalid range');
            regex.write(c);
            hasRangeStart = false;
          } else {
            hasRangeStart = true;
            last = c;
          }
        }
        if (c != ']') throw const GlobSyntaxException("Missing ']'");
        regex.write(']');
        if (!inGroup) isAnchored = true;
      case '\\':
        if (i == glob.length) throw const GlobSyntaxException('No character to escape');
        final n = glob[i++];
        if (_isGlobMeta(n) || _isRegexMeta(n)) regex.write('\\');
        regex.write(n);
        if (!inGroup) isAnchored = true;
      case '{':
        if (inGroup) throw const GlobSyntaxException('Cannot nest groups');
        regex.write('(?');
        if (next(i) == '!') {
          isNegativeLookaround = true;
          if (!isAnchored) regex.write('<');
          regex.write('!');
          i++;
        } else {
          isNegativeLookaround = false;
          regex.write(':');
        }
        inGroup = true;
      case '}':
        if (inGroup) {
          regex.write(')');
          if (isAnchored && isNegativeLookaround) {
            regex.write('.*');
            isAnchored = false;
          }
          inGroup = false;
        } else {
          regex.write('}');
          isAnchored = true;
        }
      default:
        if (_isRegexMeta(c)) regex.write('\\');
        regex.write(c);
        if (!inGroup) isAnchored = true;
    }
  }
  if (inGroup) throw const GlobSyntaxException("Missing '}'");
  return (regex..write('\$')).toString();
}

/// `Glob.toRegexPattern(glob, "")`: the empty pattern when the glob is malformed.
String globToRegexPatternOrEmpty(String glob) {
  try {
    return globToRegexPattern(glob);
  } on GlobSyntaxException {
    return '';
  }
}

/// `String.matches(Glob.toRegexPattern(glob, ""))`: the whole of [text] must match.
bool globMatches(String glob, String text) {
  final pattern = globToRegexPatternOrEmpty(glob);
  try {
    final m = RegExp(pattern).matchAsPrefix(text);
    return m != null && m.end == text.length;
  } on FormatException {
    return false;
  }
}
