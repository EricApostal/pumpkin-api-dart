import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/module.dart';
import '../core/permissions.dart';
import '../core/storage.dart';
import 'commands.dart';
import 'model.dart';
import 'permissions.dart';
import 'service.dart';
import 'ui.dart';

/// Rotating server announcements in chat, the action bar, titles or a boss
/// bar, and `/announce` for one-off broadcasts.
///
/// The rotation is driven by a one second tick that asks the
/// [AnnouncementService] whether an announcement is due, so a reload can
/// change the interval without rescheduling anything.
final class AnnouncementsModule extends Module {
  static const _configPath = 'announcements/config.json';

  @override
  String get name => 'announcements';

  /// Moderation loads first so vanished players are not counted in `{online}`.
  @override
  List<String> get dependsOn => const ['moderation'];

  @override
  List<PermNode> get permissions => AnnouncementPerms.all;

  ScheduledTask? _tick;
  AnnouncementDisplay? _display;

  @override
  void onLoad(ModuleHost host) {
    final doc = host.docs.open<AnnouncementsConfig>(
      _configPath,
      decode: AnnouncementsConfigMapper.fromJson,
      encode: (v) => v.toJson(),
      create: AnnouncementsConfig.new,
    )..save();
    final config = doc.value;
    _warn(host, configProblems(config));

    final service = AnnouncementService(host.clock, config);
    final display = AnnouncementDisplay(host.clock, host.services, config);
    _display = display;

    List<String> reload() {
      final loaded = _readConfig(host.docs.backend);
      service.config = loaded;
      display.config = loaded;
      final problems = configProblems(loaded);
      _warn(host, problems);
      return problems;
    }

    AnnouncementCommands(
      service: service,
      display: display,
      reload: reload,
    ).register(host.context);

    host.context.listen(Events.playerJoin, (server, event) {
      display.playerJoined(server, event.player.uuidString);
    });
    _tick = host.context.every(const Duration(seconds: 1), (server) {
      try {
        final due = service.poll(
          hasAudience: (a) => display.hasAudience(server, a),
        );
        if (due != null) display.show(server, due);
      } catch (e, s) {
        host.log.error(
          'Could not show an announcement',
          error: e,
          stackTrace: s,
        );
      }
    });
    host.log.info(
      '${config.messages.length} announcements, every ${config.intervalSeconds}s.',
    );
  }

  @override
  void onUnload() {
    _tick?.cancel();
    _display?.dispose();
  }

  /// Reads the file again. The old configuration stays in use if the file is
  /// missing or broken, and the file itself is left alone.
  AnnouncementsConfig _readConfig(StorageBackend backend) {
    final text = backend.read(_configPath);
    if (text == null) {
      throw CommandException('$_configPath does not exist.');
    }
    try {
      return AnnouncementsConfigMapper.fromJson(text);
    } catch (e) {
      throw CommandException('$_configPath is not valid, nothing changed: $e');
    }
  }

  void _warn(ModuleHost host, List<String> problems) {
    for (final problem in problems) {
      host.log.warn('$_configPath: $problem');
    }
  }
}
