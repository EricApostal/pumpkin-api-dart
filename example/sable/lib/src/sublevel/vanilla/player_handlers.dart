// Players and sub-levels: teleporting out of a plot, the death message for
// falling off a ship, respawn anchors on one, and the freeze used while a ship
// is being assembled under a player.
//
// Java patches `ServerPlayer#teleportTo`, `CombatTracker#getFallMessage`,
// `ServerPlayer#setRespawnPosition`, `LivingEntity#stopSleeping` and the player
// tick for the freeze. A plugin sees all of these as events, so the handlers
// here return the value the event should carry.
//
// Java: dev.ryanhcode.sable.mixin.entity.teleport_players.ServerPlayerMixin
// Java: dev.ryanhcode.sable.mixin.death_message.CombatTrackerMixin
// Java: dev.ryanhcode.sable.mixin.death_message.EntityMixin
// Java: dev.ryanhcode.sable.mixin.respawn_point.ServerPlayerMixin
// Java: dev.ryanhcode.sable.mixin.respawn_point.sleeping.LivingEntityMixin
// Java: dev.ryanhcode.sable.mixin.player_freezing.PlayerMixin
// Java: dev.ryanhcode.sable.mixin.player_freezing.ServerPlayerMixin
//
// Pure: no host imports.
import '../math/vector.dart';
import '../util/uuid.dart';
import '../model/sub_level.dart';

/// Positions a player is moved to.
abstract final class PlayerProjection {
  /// `teleport_players/ServerPlayerMixin`: `teleportTo` is called with a
  /// position that may be inside a plot (a command, a portal, a plugin); the
  /// player must end up at the corresponding world position.
  static Vector3d projectOut(SubLevel? containing, Vector3d target) {
    if (containing == null) return Vector3d.copy(target);
    return containing.logicalPose.transformPosition(Vector3d.copy(target));
  }

  /// `respawn_point`: the same projection for a respawn position.
  static Vector3d projectRespawn(
    SubLevel? containing,
    Vector3d respawnPosition,
  ) => projectOut(containing, respawnPosition);

  /// `sleeping/LivingEntityMixin#stopSleeping`: a player that wakes up on a
  /// ship stands on the deck, not half inside it.
  ///
  /// Java projects the position and then moves it down by half the entity's
  /// height.
  static Vector3d standUpPosition(
    SubLevel? containing,
    Vector3d position,
    double halfHeight,
  ) {
    final projected = projectOut(containing, position);
    return Vector3d(projected.x, projected.y - halfHeight, projected.z);
  }
}

/// Death messages.
abstract final class FallDeathMessage {
  /// The translation key Sable adds for "fell off a ship".
  static const String key = 'death.attack.fall.from_sublevel';

  /// `CombatTrackerMixin#sable$getFallMessage`: a fall that started on a ship
  /// names the ship, as long as the entity is no longer on it.
  ///
  /// Returns `null` when the vanilla message should stand.
  static String? message({
    required String? subLevelName,
    required bool stillTracking,
  }) {
    if (subLevelName == null || subLevelName.isEmpty) return null;
    if (stillTracking) return null;
    return key;
  }
}

/// The respawn anchor a player has on a ship.
///
/// Java keeps a tracking point id on `ServerPlayer` and stores it as the
/// `RespawnPoint` int array. Here the state is a plain object the plugin keeps
/// per player; [savedValue] / [fromSavedValue] are the on-disk form, unchanged
/// from Java so a world written by the mod still loads.
final class RespawnAnchor {
  /// The tracking point id, or `null` when the player's spawn is not on a ship.
  String? pointId;

  RespawnAnchor([this.pointId]);

  /// The NBT key Java uses.
  static const String savedKey = 'RespawnPoint';

  /// Whether a spawn point is on a ship.
  bool get isOnSubLevel => pointId != null;

  /// Replaces the anchor when the player's spawn point changes.
  ///
  /// [containing] is the sub-level containing the new spawn block, [generate]
  /// creates the tracking point and returns its id.
  void onSpawnChanged({
    required SubLevel? containing,
    required void Function(String oldPointId) remove,
    required String Function() generate,
  }) {
    final old = pointId;
    if (old != null) {
      remove(old);
      pointId = null;
    }

    if (containing != null) {
      pointId = generate();
    }
  }

  /// The anchor as it is written to the player's data, or `null`.
  List<int>? savedValue() => pointId == null ? null : uuidToInts(pointId!);

  /// Restores an anchor from the player's data.
  static RespawnAnchor fromSavedValue(List<int>? value) =>
      RespawnAnchor(value == null ? null : uuidFromInts(value));
}

/// A player frozen while the ship under them is being assembled.
///
/// Java stores the sub-level id and the local anchor on the player and, every
/// tick, teleports the player to the anchor until 160 ticks have passed without
/// a refresh. The payload sent to the client is `sable:freeze_player`.
final class FrozenPlayer {
  /// The sub-level the player is frozen to.
  String? subLevelId;

  /// The anchor, in the sub-level's coordinates.
  Vector3d? anchor;

  /// Ticks since the freeze was last refreshed.
  int ticks;

  FrozenPlayer({this.subLevelId, this.anchor, this.ticks = 0});

  /// The tick budget before the freeze is dropped (`sable$tickStopFreezing`).
  static const int timeoutTicks = 160;

  bool get isFrozen => subLevelId != null;

  /// Advances one tick; returns true when the freeze expired.
  bool tick() {
    if (subLevelId == null) return false;
    ticks++;
    if (ticks > timeoutTicks) {
      clear();
      return true;
    }
    return false;
  }

  /// Freezes the player to [subLevelId] at [localAnchor], or clears the freeze
  /// when [subLevelId] is `null`.
  void freezeTo(String? subLevelId, Vector3d? localAnchor) {
    this.subLevelId = subLevelId;
    anchor = localAnchor == null ? null : Vector3d.copy(localAnchor);
    ticks = 0;
  }

  /// Drops the freeze.
  void clear() => freezeTo(null, null);

  /// Where the player is put each tick while frozen: the anchor transformed by
  /// the ship's last pose, so the player rides the assembly.
  Vector3d? teleportTarget(SubLevel subLevel) {
    final local = anchor;
    if (local == null) return null;
    return subLevel.lastPose.transformPosition(Vector3d.copy(local));
  }

  /// Whether the client has to be told about the freeze when it joins
  /// (`PlayerListMixin#sable$player`).
  bool get needsJoinPayload => subLevelId != null;
}
