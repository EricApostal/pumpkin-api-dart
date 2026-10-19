/// `CreateAdvancement.awardTo` for all modules. Provided by the `content` module as a service:
///
/// ```dart
/// final adv = ctx.services.require<CreateAdvancements>();
/// await adv.award(player, AllAdvancements.andesiteCasing);
/// ```
library;

import 'package:pumpkin_api/pumpkin_api.dart';

export '../content/advancement_ids.dart';

/// Awards Create's advancements.
abstract interface class CreateAdvancements {
  /// `CreateAdvancement.awardTo(player)`: fires the `create:<id>_builtin` trigger. Returns true
  /// when the advancement was newly granted. Throws an [UnsupportedError] for advancements that
  /// use an external trigger (inventory based), like Java.
  Future<bool> award(Player player, String id);

  /// `CreateAdvancement.isAlreadyAwardedTo(player)`: true if the player has it (or it does not exist).
  bool isAlreadyAwardedTo(Player player, String id);

  /// Whether [id] has a builtin trigger and can be awarded directly.
  bool canAward(String id);
}
