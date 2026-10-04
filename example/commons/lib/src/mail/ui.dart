import 'package:pumpkin_api/pumpkin_api.dart';

import 'model.dart';
import 'service.dart';

/// The sound of a notification (a registry name, see the `customSound`
/// remark in pumpkin_api's feedback docs).
const mailSound = 'minecraft:entity.experience_orb.pickup';

/// The online player with [uuid], or `null`. The handle is only valid in the
/// current callback.
Player? onlinePlayer(Server server, String uuid) {
  final id = Uuids.tryParse(uuid);
  return id == null ? null : server.getPlayerByUuid(id: id);
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

/// Tells [player] about a message that just arrived, in chat (with a
/// `[Read]` button) and above the hotbar, with a sound.
void notifyNewMail(Player player, MessageCatalog messages, MailMessage mail) {
  final from = {'player': MessageFormat.escape(mail.fromName)};
  player.send(
    Text.legacy(messages.text('notify.new', from)) +
        button('Read', '/mail read ${mail.id}', 'Click to read'),
  );
  player.actionBar(messages['notify.actionBar'].format(from));
  player.customSound(mailSound, volume: 0.6, pitch: 1.4);
}

/// Tells [player] how many unread messages wait, with a `[Read]` button.
void notifyUnread(Player player, MessageCatalog messages, int count) {
  player.send(
    Text.legacy(messages.text('notify.unread', {'count': count})) +
        button('Read', '/mail', 'Open your inbox'),
  );
}

/// One line of the inbox: unread marker, id, sender, age, a preview and
/// `[Read] [Reply] [Delete]` buttons.
Text inboxLine(MailMessage mail, DateTime now) {
  final unread = !mail.read;
  final name = Text(mail.fromName);
  final preview = Text(_preview(mail.text)).hover(Text(mail.text));
  return Text.empty()
      .add(unread ? Text('● ').gold() : Text('  ').darkGray())
      .add(Text('#${mail.id} ').darkGray())
      .add(unread ? name.yellow().bold() : name.gray())
      .add(Text(' ${formatAgo(now.difference(mail.sentAt))}: ').darkGray())
      .add(unread ? preview.white() : preview.gray())
      .add(Text(' '))
      .add(button('Read', '/mail read ${mail.id}', 'Read this message'))
      .add(Text(' '))
      .add(
        button(
          'Reply',
          '/mail send ${mail.fromName} ',
          'Reply to ${mail.fromName}',
          suggest: true,
          color: (t) => t.aqua(),
        ),
      )
      .add(Text(' '))
      .add(
        button(
          'Delete',
          '/mail delete ${mail.id}',
          'Delete this message',
          color: (t) => t.red(),
        ),
      );
}

String _preview(String text) =>
    text.length <= 32 ? text : '${text.substring(0, 31)}…';

/// The `« Prev | Next »` footer of a paged list, running [command] with
/// `{page}` replaced.
Text pageFooter(Page<Object?> page, String command) {
  Text step(String label, bool enabled, int target) => enabled
      ? Text(label)
            .yellow()
            .runCommand(MessageFormat.format(command, {'page': target}))
      : Text(label).darkGray();
  return Text.empty()
      .add(step('« Prev', page.hasPrevious, page.number - 1))
      .add(Text(' | ').gray())
      .add(step('Next »', page.hasNext, page.number + 1));
}
