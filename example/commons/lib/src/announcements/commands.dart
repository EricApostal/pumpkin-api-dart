import 'package:pumpkin_api/pumpkin_api.dart';

import 'model.dart';
import 'permissions.dart';
import 'service.dart';
import 'ui.dart';

/// `/announce` and `/announcements`.
final class AnnouncementCommands {
  final AnnouncementService _service;
  final AnnouncementDisplay _display;

  /// Re-reads the configuration file and returns what is wrong with it.
  /// Throws a [CommandException] if the file can't be used.
  final List<String> Function() _reload;

  AnnouncementCommands({
    required this._service,
    required this._display,
    required this._reload,
  });

  void register(Context context) {
    context.command(
      'announce',
      description: 'Broadcast a message to everybody',
      permission: AnnouncementPerms.admin.node,
      (c) => c.arg(
        'message',
        ArgumentTypes.greedyString,
        runs: (ctx) {
          _display.show(ctx.server, Announcement(text: ctx.string('message')));
          ctx.sender.send('&aAnnouncement sent.');
        },
      ),
    );
    context.command(
      'announcements',
      description: 'Manage the rotating announcements',
      permission: AnnouncementPerms.admin.node,
      (c) => c
        ..runs(_list)
        ..sub('list', description: 'List the configured messages', runs: _list)
        ..sub('next', description: 'Show the next message now', runs: _next)
        ..sub(
          'reload',
          description: 'Reload announcements/config.json',
          runs: _reloadConfig,
        ),
    );
  }

  void _list(CommandContext ctx) {
    final config = _service.config;
    final sender = ctx.sender;
    sender.send(
      '&e--- Announcements (${config.messages.length}) ---\n'
      '&7${config.enabled ? 'Every ${formatDuration(config.interval)}' : 'Turned off'}, '
      '${config.random ? 'random order' : 'in order'}',
    );
    for (final (i, a) in config.messages.indexed) {
      final filters = [
        if (a.permission != null && a.permission!.isNotEmpty) a.permission!,
        if (a.world != null && a.world!.isNotEmpty) 'in ${a.world}',
      ];
      sender.send(
        Text('${i + 1}. ').gray() +
            Text('[${a.mode.name}] ').aqua() +
            Text.legacy(_preview(a.text)).hover(Text.legacy(a.text)) +
            Text(filters.isEmpty ? '' : ' (${filters.join(', ')})').darkGray(),
      );
    }
  }

  void _next(CommandContext ctx) {
    final server = ctx.server;
    final announcement = _service.next(
      hasAudience: (a) => _display.hasAudience(server, a),
    );
    if (announcement == null) {
      ctx.fail('There is nothing to announce to the players who are online.');
    }
    _display.show(server, announcement);
    ctx.sender.send('&aShown message of type ${announcement.mode.name}.');
  }

  void _reloadConfig(CommandContext ctx) {
    final problems = _reload();
    ctx.sender.send(
      '&aReloaded ${_service.config.messages.length} announcements.',
    );
    for (final problem in problems) {
      ctx.sender.send('&e! $problem');
    }
  }

  String _preview(String text) =>
      text.length <= 60 ? text : '${text.substring(0, 59)}…';
}
