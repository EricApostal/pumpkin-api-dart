// What the honey glue payloads decide, without the entity or the level.
//
// Three rules, one per payload:
//
//  * `honey_glue_spawn` — the dragged box must pass `HoneyGlueMaxSizing`, and
//    only then does the server spawn a volume;
//  * `honey_glue_change_bounds` — a resize that fails the same check *kills* the
//    volume (the player shrank it below a block or stretched it past the
//    configured range), it does not clamp it;
//  * `honey_glue_sync` — the client ignores the update when the uuid is its own,
//    because it already applied the resize locally.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.packets.honey_glue.*
//       …content.entities.honey_glue.HoneyGlueMaxSizing
// create's barrel does not export `Aabb` yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/bounds.dart' show Aabb;

import 'honey_glue_logic.dart';

/// What the server does with a honey glue payload.
enum HoneyGlueAction {
  /// The box is valid: spawn the volume.
  spawn,

  /// The box is valid: resize the volume and sync it.
  resize,

  /// The box is invalid: remove the volume (and play the dissolve sound).
  discard,

  /// The payload is not for this client (its own resize); ignore it.
  ignore,
}

/// The decisions of the three honey glue payloads.
abstract final class HoneyGluePacketLogic {
  /// `HoneyGlueSpawnPacket.handle`.
  static HoneyGlueAction onSpawn(Aabb bounds, {required int maxRange}) =>
      HoneyGlueMaxSizing.checkBounds(bounds, maxRange: maxRange).$1 ? HoneyGlueAction.spawn : HoneyGlueAction.discard;

  /// `HoneyGlueChangeBoundsPacket.handle`.
  static HoneyGlueAction onChangeBounds(Aabb bounds, {required int maxRange}) =>
      HoneyGlueMaxSizing.checkBounds(bounds, maxRange: maxRange).$1 ? HoneyGlueAction.resize : HoneyGlueAction.discard;

  /// `HoneyGlueSyncBoundsPacketClient.handle`: ignore an update the client
  /// itself caused.
  static HoneyGlueAction onSync({required String? senderUuid, required String? selfUuid}) =>
      senderUuid != null && senderUuid == selfUuid ? HoneyGlueAction.ignore : HoneyGlueAction.resize;
}
