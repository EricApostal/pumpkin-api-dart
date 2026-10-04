import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/api.dart';
import '../core/clock.dart';
import 'format.dart';
import 'model.dart';
import 'spam.dart';
import 'welcome.dart';

/// Sound of a private message (a registry name, see the `customSound`
/// remark in pumpkin_api's feedback docs).
const pmSound = 'minecraft:entity.experience_orb.pickup';

/// The online player with [uuid], or `null`. The handle is only valid in the
/// current callback.
Player? onlinePlayer(Server server, String uuid) {
  final id = Uuids.tryParse(uuid);
  return id == null ? null : server.getPlayerByUuid(id: id);
}

/// The online player called [name] (ignoring case), or `null`.
Player? onlinePlayerByName(Server server, String name) {
  for (final player in server.getAllPlayers()) {
    if (player.getName().toLowerCase() == name.toLowerCase()) return player;
  }
  return null;
}

/// A clickable `[label]` that runs [command] (or, with [suggest], puts it in
/// the chat box).
Text button(
  String label,
  String command,
  String hover, {
  bool suggest = false,
  Text Function(Text text) color = _green,
}) {
  final text = color(Text('[$label]'));
  return (suggest ? text.suggestCommand(command) : text.runCommand(command))
      .hover(Text(hover));
}

Text _green(Text text) => text.green();

/// A chat line from its [spans]. The name can be clicked to start a private
/// message to [playerName], and shows [nameHover] when hovered.
Text chatLine(List<ChatSpan> spans, String playerName, Text nameHover) {
  final line = Text.empty();
  for (final span in spans) {
    final part = Text.legacy(span.legacy);
    if (span.slot == ChatSlot.name) {
      part.suggestCommand('/msg $playerName ').hover(nameHover);
    }
    line.add(part);
  }
  return line;
}

/// ` (1h 2m left)` / ` (permanent)`, to put behind the reason of a mute.
String muteSuffix(MuteInfo mute, Clock clock) {
  final until = mute.until;
  if (until == null) return ' (permanent)';
  return ' (${formatDuration(until.difference(clock.now()))} left)';
}

/// The key of the message that tells a player why [verdict] refused them.
String spamMessageKey(SpamReason reason) => switch (reason) {
  SpamReason.tooFast => 'spam.fast',
  SpamReason.tooMany => 'spam.rate',
  SpamReason.repeated => 'spam.repeat',
};

/// Shows the join title and the summary lines to [player].
void showWelcome(
  Player player,
  MessageCatalog messages,
  WelcomeConfig config,
  WelcomeSummary summary, {
  required bool firstJoin,
  required int online,
  required int max,
}) {
  final values = {'name': MessageFormat.escape(player.getName())};
  final title = firstJoin ? config.firstTitle : config.title;
  final subtitle = firstJoin ? config.firstSubtitle : config.subtitle;
  if (title.isNotEmpty) {
    player.title(
      MessageFormat.format(title, values),
      subtitle: MessageFormat.format(subtitle, values),
      stay: const Duration(seconds: 3),
    );
  }
  player.send(
    messages['welcome.online'].format({'online': online, 'max': max}),
  );
  final balance = summary.balance;
  if (balance != null) {
    player.send(messages['welcome.balance'].format({'balance': balance}));
  }
  final unread = summary.unreadMail;
  if (unread != null && unread > 0) {
    player.send(
      Text.legacy(messages['welcome.mail'].format({'count': unread})) +
          button('Read', '/mail', 'Open your inbox'),
    );
  }
  if (summary.dailyAvailable ?? false) {
    player.send(
      Text.legacy(messages['welcome.daily'].format()) +
          button('Claim', '/daily', 'Claim your daily reward'),
    );
  }
}
