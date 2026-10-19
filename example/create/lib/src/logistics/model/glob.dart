// `net.createmod.catnip.api.data.Glob.toRegexPattern` (pure): the glob dialect Create uses for
// package addresses and train station names (`*`, `?`, `[a-z]`, `{a,b}`, `{!a}`).

const String _regexMeta = '.^\$+{[]|()';
const String _globMeta = r'\*?[{';

/// Thrown for a malformed glob (Java: `PatternSyntaxException`).
final class GlobSyntaxException implements Exception {
  final String message;
  final String glob;
  final int index;

  const GlobSyntaxException(this.message, this.glob, this.index);

  @override
  String toString() => 'GlobSyntaxException: $message near index $index in `$glob`';
}

/// The Java regex source of [glob]. Throws [GlobSyntaxException].
String globToRegexPattern(String glob) {
  var inGroup = false;
  final regex = StringBuffer('^');
  var i = 0;
  var negativeLookaround = false;
  var anchored = true;

  String? at(int index) => index < glob.length ? glob[index] : null;

  while (i < glob.length) {
    var c = glob[i++];
    switch (c) {
      case '*':
        regex.write('.*');
        if (!inGroup) anchored = false;
      case '?':
        regex.write('.');
        if (!inGroup) anchored = true;
      case ',':
        if (inGroup) {
          regex.write('|');
        } else {
          regex.write(',');
          anchored = true;
        }
      case '[':
        if (at(i) == ']' || (at(i) == '!' && at(i + 1) == ']')) {
          throw GlobSyntaxException('Cannot have set with no entries', glob, i);
        }
        regex.write('[');
        if (at(i) == '^') {
          regex.write(r'\^');
          i++;
        } else {
          if (at(i) == '!') {
            regex.write('^');
            i++;
          }
          if (at(i) == '-') {
            regex.write('-');
            i++;
          }
        }
        var hasRangeStart = false;
        var last = '';
        var closed = false;
        while (i < glob.length) {
          c = glob[i++];
          if (c == ']') {
            closed = true;
            break;
          }
          if (c == r'\') {
            if (i == glob.length) throw GlobSyntaxException('No character to escape', glob, i - 1);
            final n = at(i);
            if (n == ']' || n == '-' || n == r'\') regex.write(r'\');
            regex.write(glob[i++]);
            continue;
          }
          regex.write(c);
          if (c == '-') {
            if (!hasRangeStart) throw GlobSyntaxException('Invalid range', glob, i - 1);
            final n = at(i++);
            if (n == null || n == ']') {
              // Java: `c == EOL || c == ']'` -> break, then `c != ']'` decides.
              c = n ?? '\u0000';
              closed = n == ']';
              break;
            }
            c = n;
            if (c.codeUnitAt(0) < last.codeUnitAt(0)) throw GlobSyntaxException('Invalid range', glob, i - 3);
            regex.write(c);
            hasRangeStart = false;
          } else {
            hasRangeStart = true;
            last = c;
          }
        }
        if (!closed) throw GlobSyntaxException("Missing ']'", glob, i - 1);
        regex.write(']');
        if (!inGroup) anchored = true;
      case r'\':
        if (i == glob.length) throw GlobSyntaxException('No character to escape', glob, i - 1);
        final n = glob[i++];
        if (_globMeta.contains(n) || _regexMeta.contains(n)) regex.write(r'\');
        regex.write(n);
        if (!inGroup) anchored = true;
      case '{':
        if (inGroup) throw GlobSyntaxException('Cannot nest groups', glob, i - 1);
        regex.write('(?');
        if (at(i) == '!') {
          negativeLookaround = true;
          if (!anchored) regex.write('<');
          regex.write('!');
          i++;
        } else {
          negativeLookaround = false;
          regex.write(':');
        }
        inGroup = true;
      case '}':
        if (inGroup) {
          regex.write(')');
          if (anchored && negativeLookaround) {
            regex.write('.*');
            anchored = false;
          }
          inGroup = false;
        } else {
          regex.write('}');
          anchored = true;
        }
      default:
        if (_regexMeta.contains(c)) regex.write(r'\');
        regex.write(c);
        if (!inGroup) anchored = true;
    }
  }
  if (inGroup) throw GlobSyntaxException("Missing '}'", glob, i - 1);
  return (regex..write(r'$')).toString();
}

/// `Glob.toRegexPattern(glob, "")`: a malformed glob matches only the empty string.
String globToRegexOrEmpty(String glob) {
  try {
    return globToRegexPattern(glob);
  } on GlobSyntaxException {
    return '';
  }
}

/// `string.matches(Glob.toRegexPattern(glob, ""))` (a full match).
bool globMatches(String glob, String string) {
  final pattern = globToRegexOrEmpty(glob);
  try {
    final m = RegExp(pattern).firstMatch(string);
    return m != null && m.start == 0 && m.end == string.length;
  } on FormatException {
    return false;
  }
}
