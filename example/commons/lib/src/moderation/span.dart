/// Lengths of punishments: a duration like `7d`, or `perm` for forever.
///
/// Plain Dart (no server bindings), so it is unit tested.
library;

// Binding-free parts of pumpkin_api, so this file runs in `dart test`.
// ignore: implementation_imports
import 'package:pumpkin_api/src/command_help.dart'
    show formatDuration, parseDuration;

/// A length of time that may be forever: a `null` [length] is permanent.
typedef Span = ({Duration? length});

/// The permanent span.
const Span permanent = (length: null);

/// Words that mean "forever" where a duration is expected.
const permanentWords = ['perm', 'permanent', 'forever'];

/// The longest finite span accepted. Longer ones are almost certainly typos
/// and would overflow dates, `perm` is the way to say "forever".
const maxSpan = Duration(days: 36500);

/// Parses `perm` (or `permanent`, `forever`) or a duration with units such as
/// `30m`, `12h`, `7d`, `2w` or `1h30m`. Returns `null` for anything else.
///
/// A bare number is refused on purpose: `/mute Steve 5 minutes` should not
/// become a five second mute. Zero and too long spans are refused as well.
Span? parseSpan(String text) {
  final input = text.trim().toLowerCase();
  if (permanentWords.contains(input)) return permanent;
  if (input.isEmpty || int.tryParse(input) != null) return null;
  final Duration? length;
  try {
    length = parseDuration(input);
  } on FormatException {
    return null; // A number too big to read.
  }
  if (length == null || length <= Duration.zero || length > maxSpan) {
    return null;
  }
  return (length: length);
}

/// Splits `[duration] [reason...]` as typed after `/mute`: the first word is
/// the span when it is one, everything else is the reason.
({Span? span, String reason}) splitSpanAndReason(String? text) {
  final trimmed = (text ?? '').trim();
  if (trimmed.isEmpty) return (span: null, reason: '');
  final space = trimmed.indexOf(RegExp(r'\s'));
  final first = space == -1 ? trimmed : trimmed.substring(0, space);
  final span = parseSpan(first);
  if (span == null) return (span: null, reason: trimmed);
  return (
    span: span,
    reason: space == -1 ? '' : trimmed.substring(space).trim(),
  );
}

/// `permanent`, or the length written out like `1d 2h`.
String formatSpan(Duration? length) =>
    length == null ? 'permanent' : formatDuration(length);
