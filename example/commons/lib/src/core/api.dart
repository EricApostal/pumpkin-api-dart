/// Service interfaces that modules offer each other. They are plain Dart (no
/// server bindings), so every module can be tested against fakes. A module
/// provides its implementation with `host.services.provide<Economy>(...)`.
library;

// -- Economy ------------------------------------------------------------------

enum TransactionFailure { insufficientFunds, invalidAmount, unknownAccount }

/// Result of a money movement: either it happened, or [failure] says why.
final class Transaction {
  final TransactionFailure? failure;

  /// The balance of the (first) account after the operation.
  final int balance;

  const Transaction.ok(this.balance) : failure = null;
  const Transaction.failed(this.failure, this.balance);

  bool get isOk => failure == null;
}

/// Whole-number currency. Amounts are always positive; there are no decimals,
/// so there is no rounding to get wrong.
abstract interface class Economy {
  /// The currency shown to players, like `coins`.
  String get currencyName;

  /// Formats [amount] for players: `1,250 coins`.
  String format(int amount);

  int balance(String uuid);

  bool canAfford(String uuid, int amount);

  Transaction deposit(String uuid, int amount, {String? reason});

  Transaction withdraw(String uuid, int amount, {String? reason});

  Transaction transfer(String from, String to, int amount, {String? reason});
}

// -- Moderation ---------------------------------------------------------------

final class MuteInfo {
  final String reason;

  /// When the mute ends, or `null` if it is permanent.
  final DateTime? until;
  final String by;

  const MuteInfo({required this.reason, required this.until, required this.by});
}

abstract interface class ModerationApi {
  /// The mute of [uuid] if it is currently active.
  MuteInfo? activeMute(String uuid);

  bool isVanished(String uuid);
}

// -- Mail ---------------------------------------------------------------------

abstract interface class MailApi {
  int unreadCount(String uuid);
}

// -- Rewards ------------------------------------------------------------------

abstract interface class RewardsApi {
  /// Whether [uuid] can claim today's reward.
  bool canClaimDaily(String uuid);
}
