// ignore_for_file: prefer_initializing_formals
// (the public named parameters differ from the private fields)

import '../core/api.dart';
import '../core/clock.dart';
import '../core/players.dart';
import '../core/storage.dart';
import 'amount.dart';
import 'model.dart';

/// Why a `/pay` of some amount would be refused, see
/// [EconomyService.payProblem].
enum PayProblem {
  /// Paying yourself.
  self,

  /// The recipient never joined the server.
  unknownRecipient,

  /// Less than [EconomyConfig.payMinimum].
  belowMinimum,

  /// The payer has too little money.
  insufficientFunds,

  /// The payment would take the recipient over [EconomyConfig.maxBalance].
  recipientFull,
}

/// One place of the richest-players list.
final class LeaderboardEntry {
  final String uuid;

  /// The player's name, or the UUID for a player the server no longer knows.
  final String name;
  final int balance;

  const LeaderboardEntry(this.uuid, this.name, this.balance);
}

/// The accounts: balances, the rules around moving money, and the bounded
/// history. This is the [Economy] other modules use.
///
/// Every money movement is validated completely before anything is changed,
/// then applied in one step, so a transfer can never take money without
/// giving it (or the other way round). Balances are written to disk
/// immediately; the history is only marked dirty (the plugin saves it every few
/// seconds), since it is large and only an audit trail.
///
/// A player has an account once they joined ([ensureAccount]) or when money
/// first moves to or from them. A player the server knows but who has no
/// account yet reads as holding the starting balance. Nobody else (an
/// unknown UUID) can be paid or charged: that is
/// [TransactionFailure.unknownAccount].
///
/// Amounts that cannot be applied, which includes a deposit that would exceed
/// [EconomyConfig.maxBalance] and a transfer to oneself, are reported as
/// [TransactionFailure.invalidAmount].
final class EconomyService implements Economy {
  final JsonDocument<Accounts> _accounts;
  final JsonDocument<History> _history;
  final PlayerDirectory _players;
  final Clock _clock;

  /// The (sanitized) settings.
  final EconomyConfig config;

  EconomyService({
    required JsonDocument<Accounts> accounts,
    required JsonDocument<History> history,
    required EconomyConfig config,
    required PlayerDirectory players,
    required Clock clock,
  }) : _accounts = accounts,
       _history = history,
       _players = players,
       _clock = clock,
       config = config.sanitized();

  // -- Economy ----------------------------------------------------------------

  @override
  String get currencyName => config.currencyPlural;

  @override
  String format(int amount) {
    final number = groupDigits(amount);
    if (config.symbol.isNotEmpty) return '${config.symbol}$number';
    final name = amount.abs() == 1
        ? config.currencySingular
        : config.currencyPlural;
    return '$number $name';
  }

  /// Like [format] with a sign: `+50 coins`, `-1 coin`.
  String formatChange(int change) =>
      change < 0 ? '-${format(-change)}' : '+${format(change)}';

  @override
  int balance(String uuid) =>
      _accounts.value.balances[uuid] ??
      (_isKnown(uuid) ? config.startingBalance : 0);

  @override
  bool canAfford(String uuid, int amount) =>
      amount > 0 && _exists(uuid) && balance(uuid) >= amount;

  @override
  Transaction deposit(String uuid, int amount, {String? reason}) {
    if (amount <= 0) {
      return Transaction.failed(
        TransactionFailure.invalidAmount,
        balance(uuid),
      );
    }
    if (!_exists(uuid)) {
      return const Transaction.failed(TransactionFailure.unknownAccount, 0);
    }
    final current = _current(uuid);
    if (amount > config.maxBalance - current) {
      return Transaction.failed(TransactionFailure.invalidAmount, current);
    }
    _commit([
      _Change(uuid, current + amount, TransactionKind.deposit, reason: reason),
    ]);
    return Transaction.ok(current + amount);
  }

  @override
  Transaction withdraw(String uuid, int amount, {String? reason}) {
    if (amount <= 0) {
      return Transaction.failed(
        TransactionFailure.invalidAmount,
        balance(uuid),
      );
    }
    if (!_exists(uuid)) {
      return const Transaction.failed(TransactionFailure.unknownAccount, 0);
    }
    final current = _current(uuid);
    if (current < amount) {
      return Transaction.failed(TransactionFailure.insufficientFunds, current);
    }
    _commit([
      _Change(uuid, current - amount, TransactionKind.withdraw, reason: reason),
    ]);
    return Transaction.ok(current - amount);
  }

  /// Moves [amount] from [from] to [to], or does nothing at all. The returned
  /// balance is the one of [from].
  @override
  Transaction transfer(String from, String to, int amount, {String? reason}) {
    if (amount <= 0 || from == to) {
      return Transaction.failed(
        TransactionFailure.invalidAmount,
        balance(from),
      );
    }
    if (!_exists(from) || !_exists(to)) {
      return Transaction.failed(
        TransactionFailure.unknownAccount,
        balance(from),
      );
    }
    final fromBalance = _current(from);
    final toBalance = _current(to);
    if (fromBalance < amount) {
      return Transaction.failed(
        TransactionFailure.insufficientFunds,
        fromBalance,
      );
    }
    if (amount > config.maxBalance - toBalance) {
      return Transaction.failed(TransactionFailure.invalidAmount, fromBalance);
    }
    _commit([
      _Change(
        from,
        fromBalance - amount,
        TransactionKind.transferOut,
        other: to,
        reason: reason,
      ),
      _Change(
        to,
        toBalance + amount,
        TransactionKind.transferIn,
        other: from,
        reason: reason,
      ),
    ]);
    return Transaction.ok(fromBalance - amount);
  }

  // -- Beyond the interface -----------------------------------------------------

  /// Whether [uuid] has an account (as opposed to being a known player who
  /// has not used money yet).
  bool hasAccount(String uuid) => _accounts.value.balances.containsKey(uuid);

  /// Opens the account of [uuid] with the starting balance if it has none.
  /// Returns whether it was created.
  bool ensureAccount(String uuid) {
    if (hasAccount(uuid)) return false;
    _commit(const [], open: [uuid]);
    return true;
  }

  /// Sets the balance of [uuid] to [amount] (0 up to the maximum balance).
  Transaction set(String uuid, int amount, {String? reason}) {
    if (amount < 0 || amount > config.maxBalance) {
      return Transaction.failed(
        TransactionFailure.invalidAmount,
        balance(uuid),
      );
    }
    if (!_exists(uuid)) {
      return const Transaction.failed(TransactionFailure.unknownAccount, 0);
    }
    _commit([_Change(uuid, amount, TransactionKind.set, reason: reason)]);
    return Transaction.ok(amount);
  }

  /// Gives [uuid] the starting balance again.
  Transaction reset(String uuid, {String? reason}) =>
      set(uuid, config.startingBalance, reason: reason ?? 'Reset');

  /// Whether `/pay` should ask the payer to confirm [amount].
  bool needsConfirmation(int amount) =>
      config.confirmAbove > 0 && amount > config.confirmAbove;

  /// What stops [from] paying [amount] to [to] with `/pay`, or `null` if
  /// nothing does. Checks in the order of [PayProblem].
  PayProblem? payProblem(String from, String to, int amount) {
    if (from == to) return PayProblem.self;
    if (!_exists(to)) return PayProblem.unknownRecipient;
    if (amount < config.payMinimum) return PayProblem.belowMinimum;
    if (balance(from) < amount) return PayProblem.insufficientFunds;
    if (amount > config.maxBalance - balance(to)) {
      return PayProblem.recipientFull;
    }
    return null;
  }

  /// Whether a deposit of [amount] to [uuid] stays within the maximum balance.
  bool canHold(String uuid, int amount) =>
      amount <= config.maxBalance - balance(uuid);

  /// The remembered transactions of [uuid], newest first, at most [limit].
  List<LedgerEntry> history(String uuid, {int? limit}) {
    final entries =
        (_history.value.entries[uuid] ?? const <LedgerEntry>[]).reversed;
    return (limit == null ? entries : entries.take(limit)).toList();
  }

  /// Everyone with money, richest first. Equal balances are ordered by name,
  /// so the list is stable.
  List<LeaderboardEntry> leaderboard() {
    final list = [
      for (final MapEntry(:key, :value) in _accounts.value.balances.entries)
        if (value > 0)
          LeaderboardEntry(key, _players.nameOf(key) ?? key, value),
    ];
    list.sort((a, b) {
      final byBalance = b.balance.compareTo(a.balance);
      if (byBalance != 0) return byBalance;
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.uuid.compareTo(b.uuid);
    });
    return list;
  }

  /// The 1-based place of [uuid] on the [leaderboard], or `null` without money.
  int? rankOf(String uuid) {
    final index = leaderboard().indexWhere((e) => e.uuid == uuid);
    return index < 0 ? null : index + 1;
  }

  /// All the money in the economy.
  int get totalSupply =>
      _accounts.value.balances.values.fold(0, (sum, balance) => sum + balance);

  // -- Internals ----------------------------------------------------------------

  bool _isKnown(String uuid) => _players.byUuid(uuid) != null;

  bool _exists(String uuid) => hasAccount(uuid) || _isKnown(uuid);

  /// The balance to compute with: the account, or the starting balance of an
  /// account that is about to be opened.
  int _current(String uuid) =>
      _accounts.value.balances[uuid] ?? config.startingBalance;

  /// Applies already validated [changes] in one step, opening the accounts
  /// they touch and those in [open] first.
  void _commit(List<_Change> changes, {List<String> open = const []}) {
    final now = _clock.now();
    final starting = config.startingBalance;
    final balances = {..._accounts.value.balances};
    final entries = {..._history.value.entries};

    void record(String uuid, LedgerEntry entry) {
      final list = [...?entries[uuid], entry];
      final cap = config.historyPerAccount;
      if (list.length > cap) list.removeRange(0, list.length - cap);
      if (list.isEmpty) {
        entries.remove(uuid);
      } else {
        entries[uuid] = list;
      }
    }

    void openAccount(String uuid) {
      if (balances.containsKey(uuid)) return;
      balances[uuid] = starting;
      record(
        uuid,
        LedgerEntry(
          at: now,
          kind: TransactionKind.set,
          change: starting,
          balance: starting,
          reason: 'Starting balance',
        ),
      );
    }

    open.forEach(openAccount);
    for (final change in changes) {
      openAccount(change.uuid);
      record(
        change.uuid,
        LedgerEntry(
          at: now,
          kind: change.kind,
          change: change.balance - balances[change.uuid]!,
          balance: change.balance,
          other: change.other,
          reason: change.reason,
        ),
      );
      balances[change.uuid] = change.balance;
    }
    _accounts.value = Accounts(balances: balances);
    _history.value = History(entries: entries);
    _accounts.save();
  }
}

final class _Change {
  final String uuid;
  final int balance;
  final TransactionKind kind;
  final String? other;
  final String? reason;

  const _Change(this.uuid, this.balance, this.kind, {this.other, this.reason});
}
