import 'package:dart_mappable/dart_mappable.dart';

part 'model.mapper.dart';

/// Where an announcement is shown.
@MappableEnum()
enum AnnouncementMode {
  /// A chat line (the only mode with click and hover actions).
  chat,

  /// Above the hotbar, repeated for `displaySeconds`.
  actionbar,

  /// A boss bar that drains over `displaySeconds`.
  bossbar,

  /// A title with an optional subtitle.
  title,
}

/// One entry of `announcements/config.json`.
@MappableClass()
class Announcement with AnnouncementMappable {
  /// The text, with `&` color codes and the placeholders `{online}`, `{max}`
  /// and `{time}`.
  final String text;

  /// The subtitle of a title announcement.
  final String? subtitle;

  final AnnouncementMode mode;

  /// A command (`/shop`) that runs when the chat line is clicked.
  final String? command;

  /// A link that opens when the chat line is clicked. [command] wins.
  final String? url;

  /// Text shown when the chat line is hovered.
  final String? hover;

  /// Only players with this permission see it. Empty: everybody.
  final String? permission;

  /// Only players in this world (`overworld`, `the_nether`) see it.
  final String? world;

  const Announcement({
    required this.text,
    this.subtitle,
    this.mode = AnnouncementMode.chat,
    this.command,
    this.url,
    this.hover,
    this.permission,
    this.world,
  });
}

/// The names `bossBarColor` can have.
const bossBarColorNames = [
  'pink',
  'blue',
  'red',
  'green',
  'yellow',
  'purple',
  'white',
];

/// Settings from `announcements/config.json`.
@MappableClass()
class AnnouncementsConfig with AnnouncementsConfigMappable {
  final bool enabled;

  /// Time between two announcements.
  final int intervalSeconds;

  /// Pick the next announcement at random (never the same twice in a row)
  /// instead of in order.
  final bool random;

  /// How long boss bars, action bar messages and titles stay.
  final int displaySeconds;

  /// One of [bossBarColorNames].
  final String bossBarColor;

  /// Put before every chat announcement.
  final String chatPrefix;

  /// Shifts `{time}` from UTC, in minutes (120 is UTC+2).
  final int utcOffsetMinutes;

  final List<Announcement> messages;

  const AnnouncementsConfig({
    this.enabled = true,
    this.intervalSeconds = 300,
    this.random = false,
    this.displaySeconds = 10,
    this.bossBarColor = 'yellow',
    this.chatPrefix = '&8[&6!&8] &r',
    this.utcOffsetMinutes = 0,
    this.messages = const [
      Announcement(
        text: '&eThere are &6{online} &eplayers online. Say hello in chat!',
      ),
      Announcement(
        text: "&eDon't forget your daily reward! &a[Claim]",
        command: '/daily',
        hover: '&7Click to claim it',
      ),
      Announcement(
        text: '&6{online}/{max} &fplayers online - it is &e{time}',
        mode: AnnouncementMode.bossbar,
      ),
      Announcement(
        text: '&7Tip: write &f@name&7 in chat to get someone\'s attention',
        mode: AnnouncementMode.actionbar,
      ),
    ],
  });

  Duration get interval =>
      Duration(seconds: intervalSeconds < 1 ? 1 : intervalSeconds);

  Duration get displayTime =>
      Duration(seconds: displaySeconds < 1 ? 1 : displaySeconds);
}
