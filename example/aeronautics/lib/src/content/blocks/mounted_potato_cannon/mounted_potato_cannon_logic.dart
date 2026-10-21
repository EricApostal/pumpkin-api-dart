// The pure part of the mounted potato cannon: its `State`, the server state
// machine and the ammo slot. No host imports, so the saved form runs on the Dart
// VM.
//
// Java: `content/blocks/mounted_potato_cannon/MountedPotatoCannonBlockEntity`
// (`State`, `resetAndUpdate`, `tick`, `getBarrelPos`, the `inventory` tag).
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/conveyance/nbt_names.dart'
    show enumFromNbtName, enumNbtName;
import 'package:create/src/equipment/potato/potato_model.dart'
    show PotatoType, PotatoTypes;

import '../../../config/aero_config.dart';

/// `MountedPotatoCannonBlockEntity.State`.
///
/// The declaration order is Java's, because the state is saved by name and an
/// unknown name falls back to the first constant.
enum MountedPotatoCannonState { charged, firing, charging }

/// The number of projectiles a shot splits into, and the extra damage each one
/// carries (`aeronautics$setDamageMultiplier(2)`).
const double mountedCannonDamageMultiplier = 2;

/// The multiplier the cannon applies to the projectile's velocity
/// (`type.velocityMultiplier() * 2`).
const double mountedCannonRange = 2;

/// `MountedPotatoCannonBlockEntity`'s server state, without the host.
final class MountedPotatoCannonLogic {
  /// The slot size (`SingleSlotContainer(16)`).
  static const int slotLimit = 16;

  /// `barrelTimer` starts here after a shot and counts up to 100.
  static const int barrelReset = 100;

  MountedPotatoCannonState state = MountedPotatoCannonState.charging;

  /// `chargeTimer`, 0 to 1.
  double chargeTimer = 0;

  /// `initialAmmoReloadTicks`, -1 without ammo.
  int initialAmmoReloadTicks = -1;

  /// `recoilMagnitude`, halved every tick.
  double recoilMagnitude = 0;

  /// `barrelTimer`: ticks since the shot.
  int barrelTimer = barrelReset;

  /// `itemTimer`: ticks since the ammo stack changed.
  int itemTimer = 20;

  /// `blocked`: a collider sits in the barrel's way.
  bool blocked = false;

  /// `blockedLength`: how far the barrel is pushed out of the muzzle.
  double blockedLength = 0;

  /// `getChargeUpSpeed`: how much of the charge one tick adds.
  double chargeUpSpeed(double speed) {
    if (initialAmmoReloadTicks == -1 || speed == 0) return 0;
    return speed.abs() / (64 * initialAmmoReloadTicks);
  }

  /// `resetAndUpdate`: the ammo changed, so the charge starts over.
  void resetAndUpdate({required bool hasAmmo, required int reloadTicks}) {
    state = MountedPotatoCannonState.charging;
    initialAmmoReloadTicks = hasAmmo ? reloadTicks : -1;
    chargeTimer = 0;
    itemTimer = 0;
  }

  /// `resetToCharging`.
  void resetToCharging() {
    state = MountedPotatoCannonState.charging;
    itemTimer = 0;
    chargeTimer = 0;
  }

  /// The tick that is not the host's: recoil decay, the two timers, and the
  /// state machine.
  ///
  /// [powered] is the block's `POWERED`, [speed] the kinetic speed, and
  /// [trapdoorInFront] whether the block the cannon faces is a mangrove trapdoor.
  /// Returns whether the cannon fires this tick.
  bool tick({
    required double speed,
    required bool powered,
    required bool trapdoorInFront,
  }) {
    if (recoilMagnitude > 0) recoilMagnitude *= 0.5;
    if (itemTimer < 20) itemTimer++;
    if (barrelTimer < barrelReset) barrelTimer++;

    var fires = false;
    switch (state) {
      case MountedPotatoCannonState.charging:
        if (initialAmmoReloadTicks != -1) {
          if (chargeTimer < 1) chargeTimer += chargeUpSpeed(speed);
          if (chargeTimer >= 1) state = MountedPotatoCannonState.charged;
        }
      case MountedPotatoCannonState.charged:
        final internalBlocked = trapdoorInFront ? false : blocked;
        if (!internalBlocked && powered) {
          state = MountedPotatoCannonState.firing;
          barrelTimer = 0;
        }
      case MountedPotatoCannonState.firing:
        // Two ticks of delay so the client's barrel animation starts first.
        if (barrelTimer > 2) {
          fires = true;
          resetToCharging();
        }
    }
    return fires;
  }

  /// `getBarrelPos`: the muzzle, pushed out further when the barrel is blocked.
  (double, double, double) barrelPos(
    Pos pos,
    (double, double, double) aiming,
    bool blockedByTrapdoor,
  ) {
    final center = (pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5);
    if (blocked && blockedByTrapdoor) {
      final scale = blockedLength / 1.725;
      return (
        center.$1 + aiming.$1 * scale,
        center.$2 + aiming.$2 * scale,
        center.$3 + aiming.$3 * scale,
      );
    }
    return (
      center.$1 + aiming.$1 * 1.2,
      center.$2 + aiming.$2 * 1.2,
      center.$3 + aiming.$3 * 1.2,
    );
  }

  /// `recoilMagnitude = (split / 2) * config`.
  void applyRecoil(int split) {
    recoilMagnitude =
        (split / 2) * AeroConfig.server.physics.mountedPotatoCannonMagnitude;
  }

  /// `write`: `State` is `state.name()`, the Java constant name
  /// (`MountedPotatoCannonBlockEntity.java:297`).
  Map<String, Object?> toMap() => {
    'ItemRotationID': 0,
    'ItemTimer': itemTimer,
    'ChargeTimer': chargeTimer,
    'State': enumNbtName(state.name),
    'BarrelTimer': barrelTimer,
  };

  void readMap(Map<String, Object?> map) {
    chargeTimer = (map['ChargeTimer'] as num?)?.toDouble() ?? 0;
    barrelTimer = (map['BarrelTimer'] as num?)?.toInt() ?? 0;
    itemTimer = (map['ItemTimer'] as num?)?.toInt() ?? 0;
    state = stateByName(map['State'] as String?);
  }

  /// `readEnum`: by name (case insensitively, so an older lower-case save still
  /// reads), falling back to the first constant.
  static MountedPotatoCannonState stateByName(String? name) =>
      enumFromNbtName(name, MountedPotatoCannonState.values);
}

/// `MountedPotatoCannonInventory`: one slot of 16, holding an item that a potato
/// projectile type accepts.
final class MountedPotatoCannonInventory {
  /// The item key in the slot, `null` when empty.
  String? item;

  /// The stack size, at most [MountedPotatoCannonLogic.slotLimit].
  int count;

  /// The projectile type the slot's item resolves to (`cachedProjectileType`).
  PotatoType? projectileType;

  MountedPotatoCannonInventory({
    this.item,
    this.count = 0,
    this.projectileType,
  });

  bool get isEmpty => item == null || count <= 0;

  /// `getAmmo`: the stack and its type, `null` without a type.
  ({String item, int count, PotatoType type})? get ammo {
    final key = item;
    final type = projectileType;
    if (key == null || type == null || count <= 0) return null;
    return (item: key, count: count, type: type);
  }

  /// `canInsertItem`: only items a type accepts.
  static bool canInsert(
    PotatoTypes types,
    String itemKey, {
    bool Function(String tag, String key)? inTag,
  }) => types.forItem(itemKey, inTag: inTag) != null;

  /// `ContainerSlot.insertStack(info, min(count, 16), simulate)`: how many the
  /// slot takes, and the resulting inventory.
  ///
  /// Returns the number inserted; [apply] false only reports it.
  int insert(
    PotatoType? type,
    String itemKey,
    int amount, {
    required bool apply,
  }) {
    if (type == null) return 0;
    if (item != null && item != itemKey) return 0;
    final space = MountedPotatoCannonLogic.slotLimit - count;
    final inserted = amount < space ? amount : space;
    if (inserted <= 0) return 0;
    if (apply) {
      item = itemKey;
      count += inserted;
      projectileType = type;
    }
    return inserted;
  }

  /// `slot.setStack(ItemStack.EMPTY)` and `extractSlot(0, 1, false)`.
  void extract([int amount = 1]) {
    if (count <= amount) {
      clear();
    } else {
      count -= amount;
    }
  }

  /// `clearContent`.
  void clear() {
    item = null;
    count = 0;
    projectileType = null;
  }

  Map<String, Object?> toMap() => {
    if (item != null) 'item': item,
    'count': count,
  };

  void readMap(
    Map<String, Object?> map,
    PotatoTypes types, {
    bool Function(String tag, String key)? inTag,
  }) {
    item = map['item'] as String?;
    count = (map['count'] as num?)?.toInt() ?? 0;
    projectileType = item == null ? null : types.forItem(item!, inTag: inTag);
  }
}
