import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/api.dart';
import '../core/clock.dart';
import '../core/services.dart';
import 'model.dart';
import 'service.dart';

/// Shows announcements to players: chat lines, the action bar, titles and a
/// boss bar. It owns the boss bar and the repeating action bar tasks, so
/// [dispose] must be called when the plugin unloads.
final class AnnouncementDisplay {
  final Clock _clock;
  final Services _services;
  final Set<ScheduledTask> _tasks = {};

  AnnouncementsConfig _config;
  ManagedBossBar? _bar;
  Announcement? _barAnnouncement;

  AnnouncementDisplay(this._clock, this._services, this._config);

  /// Uses the new configuration for what is shown next.
  set config(AnnouncementsConfig value) => _config = value;

  ModerationApi? get _moderation => _services.find<ModerationApi>();

  /// Whether [player] sees [announcement].
  bool isVisible(Announcement announcement, Player player) => isVisibleTo(
    announcement,
    hasPermission: (node) => player.hasPermission(node: node),
    worldName: player.getWorld().getName(),
  );

  /// Whether any online player sees [announcement].
  bool hasAudience(Server server, Announcement announcement) =>
      server.getAllPlayers().any((p) => isVisible(announcement, p));

  /// Shows [announcement] to everybody who may see it.
  void show(Server server, Announcement announcement) {
    final audience = [
      for (final p in server.getAllPlayers())
        if (isVisible(announcement, p)) p.uuidString,
    ];
    if (audience.isEmpty) return;
    final text = _format(server, announcement.text);
    switch (announcement.mode) {
      case AnnouncementMode.chat:
        _chat(server, audience, announcement, text);
      case AnnouncementMode.actionbar:
        _actionBar(server, audience, text);
      case AnnouncementMode.title:
        final subtitle = announcement.subtitle;
        for (final player in _online(server, audience)) {
          player.title(
            text,
            subtitle: subtitle == null ? null : _format(server, subtitle),
            stay: _config.displayTime,
          );
        }
      case AnnouncementMode.bossbar:
        _bossBar(server, announcement, audience, text);
    }
  }

  /// A player joined: if a boss bar is showing and they may see it, show it
  /// to them too. They are looked up again after a moment, because the
  /// join event's player handle must not be given away.
  void playerJoined(Server server, String uuid) {
    server.after(const Duration(seconds: 1), (server) {
      final bar = _bar;
      final announcement = _barAnnouncement;
      final id = Uuids.tryParse(uuid);
      if (bar == null || announcement == null || bar.isRemoved || id == null) {
        return;
      }
      final player = server.getPlayerByUuid(id: id);
      if (player == null || !isVisible(announcement, player)) return;
      bar.addPlayerById(server, id);
    });
  }

  /// Removes the boss bar and stops repeating action bar messages.
  void dispose() {
    _removeBar();
    for (final task in _tasks) {
      task.cancel();
    }
    _tasks.clear();
  }

  // -- Modes -----------------------------------------------------------------

  void _chat(
    Server server,
    List<String> audience,
    Announcement announcement,
    String text,
  ) {
    final line = Text.legacy('${_config.chatPrefix}$text');
    final command = announcement.command;
    final url = announcement.url;
    if (command != null && command.isNotEmpty) {
      line.runCommand(command.startsWith('/') ? command : '/$command');
    } else if (url != null && url.isNotEmpty) {
      line.openUrl(url);
    }
    final hover = announcement.hover;
    if (hover != null && hover.isNotEmpty) line.hover(hover);
    for (final player in _online(server, audience)) {
      player.send(line);
    }
  }

  /// The action bar fades after about three seconds, so the message is sent
  /// again every two seconds until the display time is over.
  void _actionBar(Server server, List<String> audience, String text) {
    for (final player in _online(server, audience)) {
      player.actionBar(text);
    }
    var repeats = (_config.displayTime.inMilliseconds / 2000).ceil() - 1;
    if (repeats <= 0) return;
    late final ScheduledTask task;
    task = server.every(const Duration(seconds: 2), (server) {
      for (final player in _online(server, audience)) {
        player.actionBar(text);
      }
      if (--repeats <= 0) {
        task.cancel();
        _tasks.remove(task);
      }
    });
    _tasks.add(task);
  }

  /// One boss bar at a time: a new one replaces the one still showing.
  void _bossBar(
    Server server,
    Announcement announcement,
    List<String> audience,
    String text,
  ) {
    _removeBar();
    final bar = ManagedBossBar(
      text,
      color:
          BossBarColor.fromWireName(_config.bossBarColor.toLowerCase()) ??
          BossBarColor.yellow,
    );
    for (final uuid in audience) {
      final id = Uuids.tryParse(uuid);
      if (id != null) bar.addPlayerById(server, id);
    }
    _bar = bar;
    _barAnnouncement = announcement;
    bar.countdown(
      _config.displayTime,
      onFinish: (finished) {
        if (identical(_bar, finished)) {
          _bar = null;
          _barAnnouncement = null;
        }
      },
    );
  }

  void _removeBar() {
    _bar?.remove();
    _bar = null;
    _barAnnouncement = null;
  }

  // -- Helpers ---------------------------------------------------------------

  Iterable<Player> _online(Server server, List<String> uuids) sync* {
    for (final uuid in uuids) {
      final id = Uuids.tryParse(uuid);
      final player = id == null ? null : server.getPlayerByUuid(id: id);
      if (player != null) yield player;
    }
  }

  /// Fills `{online}`, `{max}` and `{time}`. Vanished players are not counted.
  String _format(Server server, String template) {
    final moderation = _moderation;
    final online = moderation == null
        ? server.getPlayerCount()
        : server
              .getAllPlayers()
              .where((p) => !moderation.isVanished(p.uuidString))
              .length;
    return MessageFormat.format(template, {
      'online': online,
      'max': server.getMaxPlayers(),
      'time': formatClock(_clock.now(), _config.utcOffsetMinutes),
    });
  }
}
