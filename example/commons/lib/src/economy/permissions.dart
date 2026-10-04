import '../core/permissions.dart';

/// Permission nodes of the economy module.
abstract final class EconomyPerms {
  static const balance = PermNode(
    'commons:economy.balance',
    'See your own balance and history with /balance',
  );
  static const balanceOthers = PermNode(
    'commons:economy.balance.others',
    'See the balance and history of other players',
    PermDefault.op,
  );
  static const pay = PermNode(
    'commons:economy.pay',
    'Pay other players with /pay',
  );
  static const baltop = PermNode(
    'commons:economy.baltop',
    'See the richest players with /baltop',
  );
  static const admin = PermNode(
    'commons:economy.admin',
    'Give, take, set and reset balances with /eco',
    PermDefault.op,
  );

  static const all = [balance, balanceOthers, pay, baltop, admin];
}
