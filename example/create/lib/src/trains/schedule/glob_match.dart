// `String.matches(regex)` of Java on top of the glob port of the logistics module
// (`Glob.toRegexPattern(glob, "")`): the station and address filters are globs turned into regexes.
export '../../logistics/model/glob.dart' show globToRegexOrEmpty, globToRegexPattern, GlobSyntaxException;

/// `string.matches(regex)`: the whole string must match. A malformed [regex] throws
/// [FormatException] like Java throws `PatternSyntaxException`.
bool javaMatches(String regex, String string) {
  final m = RegExp(regex).firstMatch(string);
  if (m == null) return false;
  if (m.start == 0 && m.end == string.length) return true;
  // The first match is not the whole string: Java `matches` backtracks to find a full match.
  return RegExp('^(?:$regex)\$').hasMatch(string);
}
