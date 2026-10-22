// The honey glue volume: its size checks and its rotation, kept apart from the
// entity so they run on the VM in tests.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.content.entities.honey_glue.HoneyGlueEntity
//       and HoneyGlueMaxSizing
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports

import 'dart:typed_data';

import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/contraptions/core/nbt_map.dart' show NbtMap;
import 'package:create/src/core/nbt.dart' show NbtKind, NetworkNbt;
import 'package:pumpkin_api/pumpkin_api_core.dart' show PacketReader;

/// The result of a size check: whether the bounds are usable, and the text of the
/// reason when they are not.
typedef HoneyGlueCheck = (bool ok, String reason);

/// `HoneyGlueMaxSizing`.
abstract final class HoneyGlueMaxSizing {
  /// The reason texts, as the Java strings (`Pair.of(false, "…")`). Java prints
  /// them literally in the HUD (`SimLang.text(pair.getSecond() + …)`), so there is
  /// no key to translate.
  static const String tooSmall = 'Contracted area is too small';
  static const String tooLarge = 'Expanded area is too large';

  /// `checkBounds(bb)`: at least one block on every axis, at most
  /// [maxRange] blocks.
  static HoneyGlueCheck checkBounds(Aabb bb, {required int maxRange}) {
    if (checkBBMin(bb)) return (false, tooSmall);
    if (checkBBMax(bb, maxRange: maxRange)) return (false, tooLarge);
    return (true, '');
  }

  /// `checkBBMin(bb)`: a volume thinner than one block on any axis.
  static bool checkBBMin(Aabb bb) => bb.xSize < 1 || bb.ySize < 1 || bb.zSize < 1;

  /// `checkBBMax(bb)`: a volume larger than the configured range.
  static bool checkBBMax(Aabb bb, {required int maxRange}) =>
      bb.xSize > maxRange || bb.ySize > maxRange || bb.zSize > maxRange;
}

/// The parts of a honey glue volume that do not need the entity.
abstract final class HoneyGlueVolumeLogic {
  /// `contains(pos)`: the block centre is inside the box.
  static bool contains(Aabb box, Pos pos) =>
      box.contains((pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5));

  /// `resetPositionToBounds()`: the entity sits at the bottom centre of its box.
  static (double, double, double) positionForBounds(Aabb box) {
    final center = box.center;
    return (center.$1, box.minY, center.$3);
  }

  /// `rotate(rotation)`: a quarter turn swaps the horizontal extents.
  ///
  /// The box is first moved to the origin, turned, and moved back; only a
  /// quarter turn changes the shape.
  static Aabb rotate(Aabb box, int quarterTurns) {
    if (quarterTurns % 2 == 0) return box;
    final local = Aabb(
      box.minX - box.center.$1,
      box.minY - box.minY,
      box.minZ - box.center.$3,
      box.maxX - box.center.$1,
      box.maxY - box.minY,
      box.maxZ - box.center.$3,
    );
    final turned = Aabb(
      local.minZ,
      local.minY,
      local.minX,
      local.maxZ,
      local.maxY,
      local.maxX,
    );
    return Aabb(
      turned.minX + box.center.$1,
      turned.minY + box.minY,
      turned.minZ + box.center.$3,
      turned.maxX + box.center.$1,
      turned.maxY + box.minY,
      turned.maxZ + box.center.$3,
    );
  }

  /// `setBounds(bounds)`: the box and the two block corners the client uses.
  static ({Aabb box, Pos blockMin, Pos blockMax}) setBounds(Aabb bounds) => (
    box: bounds,
    blockMin: (bounds.minX.floor(), bounds.minY.floor(), bounds.minZ.floor()),
    blockMax: (bounds.maxX.floor(), bounds.maxY.floor(), bounds.maxZ.floor()),
  );
}

/// `HoneyGlueEntity.writeSpawnData` (`HoneyGlueEntityMixin`): the client's only
/// source of the box, as the nameless NBT root `writeNbt` puts on the wire.
///
/// `addAdditionalSaveData` stores the box relative to [position] under `From` /
/// `To` and the position itself under `Pos`, the shape `VecHelper` writes (a list
/// of three doubles), so a rotated schematic can move the box; the client
/// rebuilds the world box with `new AABB(from, to).move(pos)`
/// (`readAdditionalSaveData`). Without this data a NeoForge client keeps the
/// entity, draws nothing and discards it on its first tick.
Uint8List honeyGlueSpawnData(Aabb box, (double, double, double) position) {
  final (px, py, pz) = position;
  return NetworkNbt.encode(
    (NbtMap()
          ..putVec('From', (box.minX - px, box.minY - py, box.minZ - pz))
          ..putVec('To', (box.maxX - px, box.maxY - py, box.maxZ - pz))
          ..putVec('Pos', position))
        .toValue(),
  );
}

/// `HoneyGlueEntity.readAdditionalSaveData`: the box of a volume from its spawn
/// data, `null` when the entity carries none.
Aabb? honeyGlueBoxFromSpawnData(List<int>? data) {
  if (data == null || data.isEmpty) return null;
  final root = NetworkNbt.read(PacketReader(data));
  if (root == null || root.kind != NbtKind.compound) return null;
  final map = NbtMap.of(root);
  final pos = map.getVec('Pos');
  final from = map.getVec('From');
  final to = map.getVec('To');
  return Aabb(
    from.$1 + pos.$1,
    from.$2 + pos.$2,
    from.$3 + pos.$3,
    to.$1 + pos.$1,
    to.$2 + pos.$2,
    to.$3 + pos.$3,
  );
}
