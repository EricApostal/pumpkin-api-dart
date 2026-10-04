import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/api.dart';
import '../core/module.dart';
import '../core/permissions.dart';
import '../core/players.dart';
import 'commands.dart';
import 'model.dart';
import 'permissions.dart';
import 'rpc.dart';
import 'service.dart';

/// Money: balances, `/pay`, `/baltop`, `/eco`, and an IPC interface for other
/// plugins. Provides [Economy].
final class EconomyModule extends Module {
  @override
  String get name => 'economy';

  @override
  List<PermNode> get permissions => EconomyPerms.all;

  @override
  void onLoad(ModuleHost host) {
    final players = host.services.require<PlayerDirectory>();
    final config = host.docs.open<EconomyConfig>(
      'economy/config.json',
      decode: EconomyConfigMapper.fromJson,
      encode: (v) => v.toJson(),
      create: EconomyConfig.new,
    );
    final accounts = host.docs.open<Accounts>(
      'economy/accounts.json',
      decode: AccountsMapper.fromJson,
      encode: (v) => v.toJson(),
      create: Accounts.new,
    );
    final history = host.docs.open<History>(
      'economy/history.json',
      decode: HistoryMapper.fromJson,
      encode: (v) => v.toJson(),
      create: History.new,
    );

    final economy = EconomyService(
      accounts: accounts,
      history: history,
      config: config.value,
      players: players,
      clock: host.clock,
    );
    host.services.provide<Economy>(economy);

    // Everyone who joins gets an account (with the starting balance).
    host.context.listen(Events.playerJoin, (server, event) {
      economy.ensureAccount(event.player.asEntity().getUuid().asString);
    });

    EconomyCommands(host, economy, players).register();
    _registerIpc(host, EconomyRpc(economy, players));
    host.log.info(
      '${accounts.value.balances.length} accounts, ${economy.format(economy.totalSupply)} in circulation.',
    );
  }

  /// Makes the economy available to other plugins, see `docs/economy.md`.
  void _registerIpc(ModuleHost host, EconomyRpc rpc) {
    final subscriptions = [
      IpcChannel.json(EconomyChannels.info)
          .handle((sender, _) => rpc.info().toMap()),
      IpcChannel<BalanceQuery>(
        EconomyChannels.balance,
        (m) => m.toMap(),
        (json) => decodePayload(json, BalanceQueryMapper.fromMap),
      ).handle((sender, m) => rpc.balance(sender, m).toMap()),
      IpcChannel<MoneyRequest>(
        EconomyChannels.charge,
        (m) => m.toMap(),
        (json) => decodePayload(json, MoneyRequestMapper.fromMap),
      ).handle((sender, m) => rpc.charge(sender, m).toMap()),
      IpcChannel<MoneyRequest>(
        EconomyChannels.pay,
        (m) => m.toMap(),
        (json) => decodePayload(json, MoneyRequestMapper.fromMap),
      ).handle((sender, m) => rpc.pay(sender, m).toMap()),
      IpcChannel<TransferRequest>(
        EconomyChannels.transfer,
        (m) => m.toMap(),
        (json) => decodePayload(json, TransferRequestMapper.fromMap),
      ).handle((sender, m) => rpc.transfer(sender, m).toMap()),
    ];
    for (final subscription in subscriptions) {
      host.context.onUnload(subscription.cancel);
    }
  }
}
