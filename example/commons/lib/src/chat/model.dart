import 'package:dart_mappable/dart_mappable.dart';

part 'model.mapper.dart';

/// How a rank looks in chat. The first rank of `ChatConfig.ranks` whose
/// [permission] the player has is used.
@MappableClass()
class RankStyle with RankStyleMappable {
  /// The permission node that earns this rank. Empty matches everybody.
  final String permission;

  /// Text before the name, with `&` color codes: `&c[Admin] `.
  final String prefix;

  /// Text after the name.
  final String suffix;

  /// Color code of the name, like `&c`.
  final String color;

  const RankStyle({
    this.permission = '',
    this.prefix = '',
    this.suffix = '',
    this.color = '&f',
  });
}

/// Anti-spam limits. A message must pass all of them.
@MappableClass()
class SpamConfig with SpamConfigMappable {
  final bool enabled;

  /// The shortest pause between two messages.
  final int cooldownMillis;

  /// At most [maxMessages] messages in any [windowSeconds] seconds (`0`
  /// messages means no such limit).
  final int maxMessages;
  final int windowSeconds;

  /// The same message (ignoring case and punctuation) is refused again for
  /// this long. `0` allows repeating.
  final int repeatSeconds;

  const SpamConfig({
    this.enabled = true,
    this.cooldownMillis = 1000,
    this.maxMessages = 5,
    this.windowSeconds = 10,
    this.repeatSeconds = 30,
  });
}

/// The title and chat lines shown to a player who joins.
@MappableClass()
class WelcomeConfig with WelcomeConfigMappable {
  final bool enabled;

  /// How long after joining the summary is shown (the client needs a moment
  /// to load the world).
  final int delaySeconds;

  /// The title, with `{name}`. Empty shows no title.
  final String title;
  final String subtitle;

  /// The title for a player's very first visit.
  final String firstTitle;
  final String firstSubtitle;

  const WelcomeConfig({
    this.enabled = true,
    this.delaySeconds = 1,
    this.title = '&6Welcome back',
    this.subtitle = '&e{name}',
    this.firstTitle = '&6Welcome',
    this.firstSubtitle = '&eenjoy your stay, {name}',
  });
}

/// Settings from `chat/config.json`. Every text here is a template with `&`
/// color codes.
@MappableClass()
class ChatConfig with ChatConfigMappable {
  /// A chat line: `{prefix}`, `{name}`, `{suffix}` and `{message}`.
  final String format;

  /// Join, leave and first join messages. Placeholders: `{prefix}`,
  /// `{name}`, `{suffix}`, `{online}` and for the first join `{count}` (how
  /// many players have joined so far). An empty text shows no message.
  final String joinFormat;
  final String leaveFormat;
  final String firstJoinFormat;

  /// Private messages: `{player}` is the other side, `{message}` the text.
  /// The spy format has `{from}`, `{to}` and `{message}`.
  final String pmSentFormat;
  final String pmReceivedFormat;
  final String spyFormat;

  /// Ranks, checked in order, and the look of everybody else.
  final List<RankStyle> ranks;
  final RankStyle defaultRank;

  /// Whether `@name` highlights and pings the player.
  final bool mentions;

  /// Registry name of the mention sound.
  final String mentionSound;

  final SpamConfig spam;
  final WelcomeConfig welcome;

  const ChatConfig({
    this.format = '{prefix}{name}{suffix}&8: &f{message}',
    this.joinFormat = '&e{prefix}{name}&e joined the game',
    this.leaveFormat = '&e{prefix}{name}&e left the game',
    this.firstJoinFormat =
        '&6&l» &eWelcome &6{name}&e, our player number &6{count}&e!',
    this.pmSentFormat = '&8[&7You &8→ &f{player}&8] &7{message}',
    this.pmReceivedFormat = '&8[&f{player} &8→ &7You&8] &7{message}',
    this.spyFormat = '&8[&6Spy&8] &7{from} &8→ &7{to}&8: &7{message}',
    this.ranks = const [
      RankStyle(
        permission: 'commons:chat.rank.admin',
        prefix: '&c[Admin] ',
        color: '&c',
      ),
      RankStyle(
        permission: 'commons:chat.rank.moderator',
        prefix: '&9[Mod] ',
        color: '&9',
      ),
      RankStyle(
        permission: 'commons:chat.rank.vip',
        prefix: '&6[VIP] ',
        color: '&6',
      ),
    ],
    this.defaultRank = const RankStyle(color: '&7'),
    this.mentions = true,
    this.mentionSound = 'minecraft:block.note_block.pling',
    this.spam = const SpamConfig(),
    this.welcome = const WelcomeConfig(),
  });
}

/// Everything in `chat/ignores.json`.
@MappableClass()
class IgnoreData with IgnoreDataMappable {
  /// UUIDs a player ignores, by the ignoring player's UUID.
  final Map<String, List<String>> ignored;

  const IgnoreData({this.ignored = const {}});
}
