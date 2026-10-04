/// Data of the economy module: the config file, the accounts and the bounded
/// transaction history. Plain dart_mappable classes, no server bindings.
library;

import 'package:dart_mappable/dart_mappable.dart';

part 'model.mapper.dart';

/// The largest balance every JSON consumer can represent exactly (2^53 - 1).
const int maxSupportedBalance = 9007199254740991;

/// Settings of the economy, stored in `economy/config.json`. Keys that are
/// missing use the defaults, and [sanitized] repairs values that make no sense.
@MappableClass()
class EconomyConfig with EconomyConfigMappable {
  /// Name of one unit, like `coin`.
  final String currencySingular;

  /// Name of several units, like `coins`.
  final String currencyPlural;

  /// Prefix for amounts, like `$`. When set, amounts read `$1,250` instead of
  /// `1,250 coins`.
  final String symbol;

  /// Balance of a new account.
  final int startingBalance;

  /// The smallest amount `/pay` accepts.
  final int payMinimum;

  /// `/pay` asks for confirmation above this amount, `0` never asks.
  final int confirmAbove;

  /// How long a `/pay` confirmation stays valid, in seconds.
  final int confirmSeconds;

  /// No account can hold more than this.
  final int maxBalance;

  /// How many transactions are remembered per account.
  final int historyPerAccount;

  /// Whether other plugins may use the economy through IPC.
  final bool ipcEnabled;

  const EconomyConfig({
    this.currencySingular = 'coin',
    this.currencyPlural = 'coins',
    this.symbol = '',
    this.startingBalance = 100,
    this.payMinimum = 1,
    this.confirmAbove = 1000,
    this.confirmSeconds = 15,
    this.maxBalance = 1000000000000,
    this.historyPerAccount = 25,
    this.ipcEnabled = true,
  });

  /// This config with out-of-range values brought back into range: at least
  /// one unit for [payMinimum], a [maxBalance] between 1 and
  /// [maxSupportedBalance], a [startingBalance] that fits, and no negative
  /// counts. Empty names fall back to the defaults.
  EconomyConfig sanitized() {
    final max = maxBalance.clamp(1, maxSupportedBalance);
    return EconomyConfig(
      currencySingular: currencySingular.trim().isEmpty
          ? 'coin'
          : currencySingular.trim(),
      currencyPlural: currencyPlural.trim().isEmpty
          ? 'coins'
          : currencyPlural.trim(),
      symbol: symbol,
      startingBalance: startingBalance.clamp(0, max),
      payMinimum: payMinimum.clamp(1, max),
      confirmAbove: confirmAbove < 0 ? 0 : confirmAbove,
      confirmSeconds: confirmSeconds < 1 ? 1 : confirmSeconds,
      maxBalance: max,
      historyPerAccount: historyPerAccount.clamp(0, 500),
      ipcEnabled: ipcEnabled,
    );
  }

  Duration get confirmTimeout => Duration(seconds: confirmSeconds);
}

/// Every account's balance by player UUID, `economy/accounts.json`.
@MappableClass()
class Accounts with AccountsMappable {
  final Map<String, int> balances;

  const Accounts({this.balances = const {}});
}

/// Why a balance changed.
@MappableEnum(caseStyle: CaseStyle.snakeCase)
enum TransactionKind { deposit, withdraw, transferIn, transferOut, set }

/// One line of an account's history.
@MappableClass()
class LedgerEntry with LedgerEntryMappable {
  final DateTime at;
  final TransactionKind kind;

  /// How much the balance changed (negative when money left the account).
  final int change;

  /// The balance after the change.
  final int balance;

  /// The UUID of the other side of a transfer.
  final String? other;

  /// Free text: who asked and why.
  final String? reason;

  const LedgerEntry({
    required this.at,
    required this.kind,
    required this.change,
    required this.balance,
    this.other,
    this.reason,
  });
}

/// The most recent transactions of each account (newest last),
/// `economy/history.json`. Each list is cut to
/// [EconomyConfig.historyPerAccount] entries.
@MappableClass()
class History with HistoryMappable {
  final Map<String, List<LedgerEntry>> entries;

  const History({this.entries = const {}});
}
