import '../core/permissions.dart';

/// Permission nodes of the rewards module.
abstract final class RewardsPerms {
  static const daily = PermNode(
    'commons:rewards.daily',
    'Claim the daily reward with /daily',
  );
  static const calendar = PermNode(
    'commons:rewards.calendar',
    'Open the reward calendar with /rewards',
  );
  static const playtime = PermNode(
    'commons:rewards.playtime',
    'See your playtime with /playtime',
  );
  static const playtimeOthers = PermNode(
    'commons:rewards.playtime.others',
    'See the playtime of other players',
  );
  static const playtop = PermNode(
    'commons:rewards.playtop',
    'See the players with the most playtime with /playtop',
  );

  static const all = [daily, calendar, playtime, playtimeOthers, playtop];
}
