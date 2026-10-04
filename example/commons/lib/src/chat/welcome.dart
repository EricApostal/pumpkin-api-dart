import '../core/api.dart';

/// What a joining player is told. A field is `null` when the service behind
/// it is not installed, and that part is left out.
final class WelcomeSummary {
  /// The formatted balance, like `1,250 coins`.
  final String? balance;

  /// Unread mail.
  final int? unreadMail;

  /// Whether the daily reward can be claimed now.
  final bool? dailyAvailable;

  const WelcomeSummary({this.balance, this.unreadMail, this.dailyAvailable});

  /// Asks the services that exist about [uuid].
  factory WelcomeSummary.collect(
    String uuid, {
    Economy? economy,
    MailApi? mail,
    RewardsApi? rewards,
  }) => WelcomeSummary(
    balance: _balance(economy, uuid),
    unreadMail: mail?.unreadCount(uuid),
    dailyAvailable: rewards?.canClaimDaily(uuid),
  );

  static String? _balance(Economy? economy, String uuid) {
    if (economy == null) return null;
    return economy.format(economy.balance(uuid));
  }
}
