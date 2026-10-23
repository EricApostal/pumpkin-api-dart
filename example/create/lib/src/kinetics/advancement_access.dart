// The kinetics module's awards: the service handle plus the two Java forms
// (`AdvancementBehaviour.awardPlayer` / `awardPlayerIfNear` and a direct `awardTo`).
//
// Java awards a block entity's advancement through its `AdvancementBehaviour`: the player that
// *placed* the block, only while they are online. The port fills `CreateBlockEntity.placedBy` on
// every placement (`core/block_entity.dart`), so the placer is known without per-block behaviour
// state; this file turns that uuid into the award.
//
// The module hands its services here from `onLoad` (`KineticsRuntime` is built without a
// `CreateServices` handle).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/advancements.dart' show CreateAdvancements;
import '../content/advancement_ids.dart' show AllAdvancements;
import '../core/block_entity.dart' show CreateBlockEntity;
import '../core/services.dart' show CreateServices;

/// The kinetics module's advancement access (`ctx.services` of `KineticsModule.onLoad`).
abstract final class KineticsAdvancements {
  static CreateServices? _services;

  /// Called once from the module's `onLoad`.
  static void install(CreateServices services) => _services = services;

  /// Called from the module's `onUnload`.
  static void clear() => _services = null;

  /// The advancement service, or `null` when the content module is not loaded.
  static CreateAdvancements? get of => _services?.find<CreateAdvancements>();

  /// `AdvancementBehaviour.awardPlayer`: awards [id] to the player that placed [be], when they
  /// are online. A block nobody placed, an offline placer and a service that cannot grant the id
  /// are all no-ops (Java's `isAlreadyAwardedTo` short-circuits the same way).
  static void awardPlacer(CreateBlockEntity be, String id) {
    final service = of;
    final uuid = be.placedBy;
    if (service == null || uuid == null) return;
    final player = service.playerByUuid(uuid);
    if (player == null) return;
    unawaited(
      service.award(player, id).catchError((Object _) => false),
    );
  }

  /// `AdvancementBehaviour.awardPlayerIfNear`: like [awardPlacer], only while the placer is
  /// within [maxDistance] of the block (`AdvancementBehaviour.java:77-87`).
  static void awardPlacerIfNear(
    CreateBlockEntity be,
    String id,
    int maxDistance,
  ) {
    final service = of;
    final uuid = be.placedBy;
    if (service == null || uuid == null) return;
    final player = service.playerByUuid(uuid);
    if (player == null) return;
    try {
      final (x, y, z) = player.getPosition();
      final dx = x - (be.pos.x + 0.5);
      final dy = y - (be.pos.y + 0.5);
      final dz = z - (be.pos.z + 0.5);
      if (dx * dx + dy * dy + dz * dz > maxDistance * maxDistance) return;
    } on Object {
      return;
    }
    unawaited(
      service.award(player, id).catchError((Object _) => false),
    );
  }

  /// `CreateAdvancement.awardTo(player)`: a direct award, the form the hand crank uses.
  static void awardPlayer(Player player, String id) {
    final service = of;
    if (service == null) return;
    unawaited(
      service.award(player, id).catchError((Object _) => false),
    );
  }

  /// `CreateAdvancement.awardTo(world.getPlayerByUUID(uuid))`: the uuid form, for the sites that
  /// only know the player's uuid (the placement events carry a `Uuid`).
  static void awardUuid(Uuid uuid, String id) {
    final service = of;
    if (service == null) return;
    final player = service.playerByUuid(uuid.asString);
    if (player == null) return;
    awardPlayer(player, id);
  }

  /// `AllAdvancements.HAND_CRANK`.
  static void awardHandCrank(Player player) =>
      awardPlayer(player, AllAdvancements.handCrank);
}