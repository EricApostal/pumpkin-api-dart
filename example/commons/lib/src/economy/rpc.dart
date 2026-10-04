/// The economy as seen by other plugins: the payloads of the IPC channels and
/// the logic behind them. Binding-free, the channels themselves are wired in
/// `economy_module.dart`. The protocol is documented in `docs/economy.md`.
library;

import 'package:dart_mappable/dart_mappable.dart';

import '../core/api.dart';
import '../core/players.dart';
import 'service.dart';

part 'rpc.mapper.dart';

/// Names of the IPC message types (the `type` of the envelope).
abstract final class EconomyChannels {
  static const info = 'economy.info';
  static const balance = 'economy.balance';
  static const charge = 'economy.charge';
  static const pay = 'economy.pay';
  static const transfer = 'economy.transfer';
}

/// `economy.balance`: what does [player] have? [player] is a UUID or a name.
@MappableClass(ignoreNull: true)
class BalanceQuery with BalanceQueryMappable {
  final String player;

  const BalanceQuery({required this.player});
}

/// `economy.charge` (take money from [player]) and `economy.pay` (give money
/// to [player]). [amount] is a positive whole number, [reason] ends up in the
/// player's history.
@MappableClass(ignoreNull: true)
class MoneyRequest with MoneyRequestMappable {
  final String player;
  final int amount;
  final String? reason;

  const MoneyRequest({required this.player, required this.amount, this.reason});
}

/// `economy.transfer`: move money from one player to another.
@MappableClass(ignoreNull: true)
class TransferRequest with TransferRequestMappable {
  final String from;
  final String to;
  final int amount;
  final String? reason;

  const TransferRequest({
    required this.from,
    required this.to,
    required this.amount,
    this.reason,
  });
}

/// Why a request failed.
@MappableEnum(caseStyle: CaseStyle.snakeCase)
enum EconomyErrorCode {
  /// No player with that name or UUID is known.
  unknownPlayer,

  /// The UUID has no account and is not a known player.
  unknownAccount,
  insufficientFunds,

  /// Not a positive amount, a transfer to oneself, or the receiver cannot hold
  /// that much.
  invalidAmount,

  /// The server owner turned IPC access off (`ipcEnabled`).
  disabled,
}

/// The answer to `economy.balance`, `economy.charge`, `economy.pay` and
/// `economy.transfer`. With [ok] the operation happened, otherwise [error]
/// says why and nothing changed.
@MappableClass(ignoreNull: true)
class EconomyReply with EconomyReplyMappable {
  final bool ok;
  final EconomyErrorCode? error;

  /// The balance of the (first) player after the operation, when known.
  final int? balance;

  /// [balance] written for players, like `1,250 coins`.
  final String? formatted;

  const EconomyReply({
    required this.ok,
    this.error,
    this.balance,
    this.formatted,
  });
}

/// The answer to `economy.info`.
@MappableClass()
class CurrencyInfo with CurrencyInfoMappable {
  final String singular;
  final String plural;
  final String symbol;
  final int maxBalance;

  const CurrencyInfo({
    required this.singular,
    required this.plural,
    required this.symbol,
    required this.maxBalance,
  });
}

/// Reads [json] (a decoded JSON object) with [fromMap]. Throws
/// [FormatException] if it is not an object; [fromMap] throws a
/// [MapperException] for missing or mistyped fields.
T decodePayload<T>(Object? json, T Function(Map<String, dynamic> map) fromMap) {
  if (json is! Map) throw const FormatException('Expected a JSON object.');
  return fromMap(json.cast<String, dynamic>());
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Handles the requests other plugins send. Every method takes the name of
/// the calling plugin ([sender]), which is written in front of the reason in
/// the player's history so owners can see who moved their money.
final class EconomyRpc {
  final EconomyService _economy;
  final PlayerDirectory _players;

  EconomyRpc(this._economy, this._players);

  CurrencyInfo info() => CurrencyInfo(
    singular: _economy.config.currencySingular,
    plural: _economy.config.currencyPlural,
    symbol: _economy.config.symbol,
    maxBalance: _economy.config.maxBalance,
  );

  EconomyReply balance(String sender, BalanceQuery query) {
    if (!_economy.config.ipcEnabled) return _error(EconomyErrorCode.disabled);
    final uuid = _resolve(query.player);
    if (uuid == null) return _error(EconomyErrorCode.unknownPlayer);
    if (!_economy.hasAccount(uuid) && _players.byUuid(uuid) == null) {
      return _error(EconomyErrorCode.unknownAccount);
    }
    return _ok(_economy.balance(uuid));
  }

  /// Takes money from a player.
  EconomyReply charge(String sender, MoneyRequest request) => _money(
    request.player,
    (uuid) => _economy.withdraw(
      uuid,
      request.amount,
      reason: _reason(sender, request.reason),
    ),
  );

  /// Gives money to a player.
  EconomyReply pay(String sender, MoneyRequest request) => _money(
    request.player,
    (uuid) => _economy.deposit(
      uuid,
      request.amount,
      reason: _reason(sender, request.reason),
    ),
  );

  EconomyReply transfer(String sender, TransferRequest request) {
    if (!_economy.config.ipcEnabled) return _error(EconomyErrorCode.disabled);
    final from = _resolve(request.from);
    final to = _resolve(request.to);
    if (from == null || to == null) {
      return _error(EconomyErrorCode.unknownPlayer);
    }
    return _reply(
      _economy.transfer(
        from,
        to,
        request.amount,
        reason: _reason(sender, request.reason),
      ),
    );
  }

  EconomyReply _money(String player, Transaction Function(String uuid) action) {
    if (!_economy.config.ipcEnabled) return _error(EconomyErrorCode.disabled);
    final uuid = _resolve(player);
    if (uuid == null) return _error(EconomyErrorCode.unknownPlayer);
    return _reply(action(uuid));
  }

  /// A UUID is taken as it is, anything else is looked up as a player name.
  String? _resolve(String player) {
    final text = player.trim().toLowerCase();
    return _uuidPattern.hasMatch(text) ? text : _players.byName(text)?.uuid;
  }

  String _reason(String sender, String? reason) =>
      reason == null || reason.trim().isEmpty
      ? sender
      : '$sender: ${reason.trim()}';

  EconomyReply _reply(Transaction transaction) {
    if (transaction.isOk) return _ok(transaction.balance);
    final error = switch (transaction.failure!) {
      TransactionFailure.insufficientFunds =>
        EconomyErrorCode.insufficientFunds,
      TransactionFailure.invalidAmount => EconomyErrorCode.invalidAmount,
      TransactionFailure.unknownAccount => EconomyErrorCode.unknownAccount,
    };
    if (error == EconomyErrorCode.unknownAccount) return _error(error);
    return EconomyReply(
      ok: false,
      error: error,
      balance: transaction.balance,
      formatted: _economy.format(transaction.balance),
    );
  }

  EconomyReply _ok(int balance) => EconomyReply(
    ok: true,
    balance: balance,
    formatted: _economy.format(balance),
  );

  EconomyReply _error(EconomyErrorCode code) =>
      EconomyReply(ok: false, error: code);
}
