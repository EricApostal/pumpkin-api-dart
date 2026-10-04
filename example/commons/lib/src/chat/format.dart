import 'model.dart';

/// Where a piece of a chat line comes from.
enum ChatSlot { prefix, name, suffix, message }

/// One piece of a rendered chat line, as legacy text (`&` color codes). Every
/// piece starts with the codes that are active at that point of the template,
/// so it can become its own text component without losing its color.
final class ChatSpan {
  /// The slot it fills, or `null` for fixed template text.
  final ChatSlot? slot;
  final String legacy;

  /// The (canonically spelled) name of the player this piece mentions.
  final String? mention;

  const ChatSpan(this.slot, this.legacy, {this.mention});

  @override
  String toString() =>
      'ChatSpan($slot, $legacy${mention == null ? '' : ', @$mention'})';
}

/// Makes player text safe inside legacy text: no section signs, and `&` is
/// escaped so it stays a literal ampersand.
String escapeLegacy(String text) =>
    text.replaceAll('§', '').replaceAll('&', '&&');

/// Removes the section sign and control characters from text a player typed
/// (the server refuses them in chat, but not in command arguments) and trims
/// it.
String cleanText(String text) => text
    .replaceAll('§', '')
    .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ')
    .trim();

/// The codes that are active after [legacy] (`&` or `§` codes, `&&` is a
/// literal `&`): the last color, then the formats since it, so that text
/// following can continue the style: `activeCodes('&a&lHi')` is `&a&l`.
String activeCodes(String legacy) {
  String? color;
  final formats = <String>{};
  for (var i = 0; i < legacy.length - 1; i++) {
    final c = legacy[i];
    if (c != '&' && c != '§') continue;
    final next = legacy[i + 1];
    if (c == '&' && next == '&') {
      i++;
      continue;
    }
    final code = next.toLowerCase();
    if ('0123456789abcdef'.contains(code)) {
      color = code;
      formats.clear();
      i++;
    } else if ('klmno'.contains(code)) {
      formats.add(code);
      i++;
    } else if (code == 'r') {
      color = null;
      formats.clear();
      i++;
    }
  }
  return [if (color != null) '&$color', for (final f in formats) '&$f'].join();
}

/// A `@name` in a message.
final class Mention {
  final int start;
  final int end;

  /// The mentioned player's name, spelled as it is.
  final String name;

  const Mention(this.start, this.end, this.name);

  @override
  String toString() => 'Mention($start-$end, $name)';
}

final _mention = RegExp(r'(?<![A-Za-z0-9_])@([A-Za-z0-9_]{1,16})');

/// The `@name` mentions of [text] that match one of [names] (ignoring case),
/// in order. `@` must not follow a letter, digit or `_` (so e-mail addresses
/// are not mentions).
List<Mention> findMentions(String text, Iterable<String> names) {
  final byLower = {for (final name in names) name.toLowerCase(): name};
  return [
    for (final match in _mention.allMatches(text))
      if (byLower[match[1]!.toLowerCase()] case final name?)
        Mention(match.start, match.end, name),
  ];
}

/// The first rank whose permission [has] says yes to, or [fallback].
RankStyle selectRank(
  List<RankStyle> ranks,
  RankStyle fallback,
  bool Function(String permission) has,
) {
  for (final rank in ranks) {
    if (rank.permission.isEmpty || has(rank.permission)) return rank;
  }
  return fallback;
}

/// A chat message as legacy text, split at its mentions of [mentionable]
/// players (which are highlighted). Without [allowColor] the text is escaped,
/// so players can't inject formatting. [base] are the codes the message
/// starts with.
List<ChatSpan> messageSpans(
  String message, {
  required bool allowColor,
  Iterable<String> mentionable = const [],
  String base = '',
}) {
  final text = message.replaceAll('§', '');
  final spans = <ChatSpan>[];
  var soFar = base;
  void addText(String segment) {
    if (segment.isEmpty) return;
    final legacy = allowColor ? segment : escapeLegacy(segment);
    spans.add(ChatSpan(ChatSlot.message, activeCodes(soFar) + legacy));
    soFar += legacy;
  }

  var cursor = 0;
  for (final mention in findMentions(text, mentionable)) {
    addText(text.substring(cursor, mention.start));
    spans.add(
      ChatSpan(ChatSlot.message, '&e&l@${mention.name}', mention: mention.name),
    );
    cursor = mention.end;
  }
  addText(text.substring(cursor));
  return spans;
}

/// A chat line layout like `{prefix}{name}{suffix}&8: &f{message}`.
final class ChatTemplate {
  static final _slot = RegExp(r'\{(prefix|name|suffix|message)\}');

  final String source;
  final List<Object> _pieces = [];

  ChatTemplate(this.source) {
    var cursor = 0;
    for (final match in _slot.allMatches(source)) {
      if (match.start > cursor) {
        _pieces.add(source.substring(cursor, match.start));
      }
      _pieces.add(ChatSlot.values.byName(match[1]!));
      cursor = match.end;
    }
    if (cursor < source.length) _pieces.add(source.substring(cursor));
  }

  /// The line for [playerName] with [rank] saying [message].
  ///
  /// The name is escaped and colored with the rank's color. The message is
  /// escaped unless [allowColor], and `@name` mentions of [mentionable]
  /// players are highlighted (see [ChatSpan.mention]).
  List<ChatSpan> render({
    required RankStyle rank,
    required String playerName,
    required String message,
    bool allowColor = false,
    Iterable<String> mentionable = const [],
  }) {
    final spans = <ChatSpan>[];
    var literals = '';
    for (final piece in _pieces) {
      switch (piece) {
        case String text:
          spans.add(ChatSpan(null, text));
          literals += text;
        case ChatSlot slot:
          final base = activeCodes(literals);
          switch (slot) {
            case ChatSlot.prefix:
              if (rank.prefix.isNotEmpty) {
                spans.add(ChatSpan(slot, base + rank.prefix));
              }
            case ChatSlot.suffix:
              if (rank.suffix.isNotEmpty) {
                spans.add(ChatSpan(slot, base + rank.suffix));
              }
            case ChatSlot.name:
              spans.add(
                ChatSpan(slot, base + rank.color + escapeLegacy(playerName)),
              );
            case ChatSlot.message:
              spans.addAll(
                messageSpans(
                  message,
                  allowColor: allowColor,
                  mentionable: mentionable,
                  base: base,
                ),
              );
          }
      }
    }
    return spans;
  }
}
