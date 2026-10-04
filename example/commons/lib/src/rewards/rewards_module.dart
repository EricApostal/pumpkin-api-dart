import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/api.dart';
import '../core/module.dart';
import '../core/permissions.dart';
import '../core/players.dart';
import 'commands.dart';
import 'messages.dart';
import 'model.dart';
import 'permissions.dart';
import 'playtime.dart';
import 'service.dart';
import 'ui.dart';

/// Daily reward with a login streak, a reward calendar, and playtime tracking
/// with playtime rewards. Needs the economy; provides [RewardsApi].
final class RewardsModule extends Module {
  PlaytimeService? _playtime;

  @override
  String get name => 'rewards';

  @override
  List<String> get dependsOn => const ['economy'];

  @override
  List<PermNode> get permissions => RewardsPerms.all;

  @override
  void onLoad(ModuleHost host) {
    final economy = host.services.require<Economy>();
    final players = host.services.require<PlayerDirectory>();
    final config = host.docs.open<RewardsConfig>(
      'rewards/config.json',
      decode: RewardsConfigMapper.fromJson,
      encode: (v) => v.toJson(),
      create: RewardsConfig.new,
    );
    final dailyFile = host.docs.open<DailyFile>(
      'rewards/daily.json',
      decode: DailyFileMapper.fromJson,
      encode: (v) => v.toJson(),
      create: DailyFile.new,
    );
    final playtimeFile = host.docs.open<PlaytimeFile>(
      'rewards/playtime.json',
      decode: PlaytimeFileMapper.fromJson,
      encode: (v) => v.toJson(),
      create: PlaytimeFile.new,
    );

    final daily = DailyService(
      economy: economy,
      doc: dailyFile,
      config: config.value.daily,
      clock: host.clock,
    );
    final playtime = PlaytimeService(
      economy: economy,
      doc: playtimeFile,
      players: players,
      config: config.value.playtime,
      clock: host.clock,
    );
    _playtime = playtime;
    host.services.provide<RewardsApi>(daily);

    final context = host.context;
    context.installMenus();
    final ui = RewardsUi(daily, economy, host.messages(rewardsMessages));
    RewardsCommands(host, ui, playtime, players, economy).register();

    context.listen(Events.playerJoin, (server, event) {
      final uuid = event.player.asEntity().getUuid().asString;
      playtime.join(uuid);
      // Let the join messages scroll by before talking to the player.
      server.after(const Duration(seconds: 3), (server) {
        _withPlayer(server, uuid, ui.welcome);
      });
    });
    context.listen(Events.playerLeave, (server, event) {
      playtime.leave(event.player.asEntity().getUuid().asString);
    });

    void tick(Server server) {
      final online = server.getAllPlayers();
      final payouts = playtime.tick([for (final p in online) uuidOf(p)]);
      for (final payout in payouts) {
        _withPlayer(server, payout.uuid, (player) {
          ui.milestone(player, payout, playtime.playtime(payout.uuid));
        });
        host.log.info(
          '${players.nameOf(payout.uuid) ?? payout.uuid} reached ${payout.milestone.minutes} minutes of playtime',
        );
      }
    }

    context.every(Duration(seconds: playtime.config.tickSeconds), tick);
    // Start counting whoever is online already (the plugin was reloaded).
    context.after(const Duration(seconds: 1), tick);
    host.log.info(
      'Daily rewards ${daily.config.enabled ? 'on' : 'off'}, '
      '${daily.config.milestones.length} streak and '
      '${playtime.config.milestones.length} playtime milestones.',
    );
  }

  @override
  void onUnload() => _playtime?.flush();

  void _withPlayer(
    Server server,
    String uuid,
    void Function(Player player) use,
  ) {
    final player = server.getPlayerByUuid(id: Uuids.parse(uuid));
    if (player != null) use(player);
  }
}
