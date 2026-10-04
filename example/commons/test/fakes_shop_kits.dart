import 'package:commons/src/core/api.dart';

/// A whole-number economy that remembers every call.
final class FakeEconomy implements Economy {
  final Map<String, int> balances = {};
  final List<String> log = [];

  /// Make [deposit] fail, to test refunds that go wrong.
  bool refuseDeposits = false;

  @override
  String get currencyName => 'coins';

  @override
  String format(int amount) => '$amount coins';

  @override
  int balance(String uuid) => balances[uuid] ?? 0;

  @override
  bool canAfford(String uuid, int amount) => balance(uuid) >= amount;

  @override
  Transaction deposit(String uuid, int amount, {String? reason}) {
    if (refuseDeposits) {
      return Transaction.failed(
        TransactionFailure.unknownAccount,
        balance(uuid),
      );
    }
    balances[uuid] = balance(uuid) + amount;
    log.add('+$amount ${reason ?? ''}');
    return Transaction.ok(balances[uuid]!);
  }

  @override
  Transaction withdraw(String uuid, int amount, {String? reason}) {
    if (balance(uuid) < amount) {
      return Transaction.failed(
        TransactionFailure.insufficientFunds,
        balance(uuid),
      );
    }
    balances[uuid] = balance(uuid) - amount;
    log.add('-$amount ${reason ?? ''}');
    return Transaction.ok(balances[uuid]!);
  }

  @override
  Transaction transfer(String from, String to, int amount, {String? reason}) =>
      throw UnimplementedError();
}
