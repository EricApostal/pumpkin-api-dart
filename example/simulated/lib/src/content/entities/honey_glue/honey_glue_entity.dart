// The honey glue entity: an invisible box that glues the blocks inside it
// together, like Create's super glue but volumetric.
//
// The entity itself is a host entity of type `simulated:honey_glue`; the port
// keeps its data in [HoneyGlue] and the live volumes in [HoneyGlueTracker], which
// the assembly reads.
//
// Host: this file uses `pumpkin_api` only for the entity type spec.
//
// Java: dev.simulated_team.simulated.content.entities.honey_glue.HoneyGlueEntity
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports

import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:pumpkin_api/pumpkin_api.dart' show EntityCategory, EntityTypeSpec;

import 'honey_glue_logic.dart';

/// The entity type key.
const String honeyGlueEntityKey = 'simulated:honey_glue';

/// The entity type: no hitbox of its own, never saved by the chunk (it is
/// spawned again from its bounds), and not summonable.
const EntityTypeSpec honeyGlueEntityType = EntityTypeSpec(
  key: honeyGlueEntityKey,
  width: 0.5,
  height: 0.5,
  category: EntityCategory.misc,
  trackingRange: 10,
  updateInterval: 20,
  summonable: false,
  saveable: true,
  pickable: false,
  collidable: false,
  pushable: false,
  fireImmune: true,
);

/// One honey glue volume.
final class HoneyGlue {
  /// The host entity id.
  final int id;

  /// The box, in world coordinates.
  Aabb box;

  /// The block corners the client uses (`blockMin` / `blockMax`).
  Pos blockMin;
  Pos blockMax;

  HoneyGlue(this.id, Aabb box)
    : box = box,
      blockMin = (box.minX.floor(), box.minY.floor(), box.minZ.floor()),
      blockMax = (box.maxX.floor(), box.maxY.floor(), box.maxZ.floor());

  /// `contains(pos)`.
  bool contains(Pos pos) => HoneyGlueVolumeLogic.contains(box, pos);

  /// `setBounds(bounds)`.
  void setBounds(Aabb bounds) {
    box = bounds;
    final corners = HoneyGlueVolumeLogic.setBounds(bounds);
    blockMin = corners.blockMin;
    blockMax = corners.blockMax;
  }

  /// `move(type, pos)`: the glue dies as soon as anything moves it.
  bool shouldDiscardOnMove(double lengthSquared) => lengthSquared > 0;

  /// `tick()` on the server: a volume thinner than 0.9 blocks on any axis is
  /// invalid and is removed.
  bool get isInvalid => box.xSize < 0.9 || box.ySize < 0.9 || box.zSize < 0.9;
}

/// The honey glue volumes of one world.
final class HoneyGlueTracker {
  final Map<int, HoneyGlue> _volumes = {};

  /// Every volume.
  Iterable<HoneyGlue> get volumes => _volumes.values;

  /// The volume with [id], or `null`.
  HoneyGlue? byId(int id) => _volumes[id];

  /// Adds or replaces a volume.
  void put(HoneyGlue glue) => _volumes[glue.id] = glue;

  /// Removes a volume.
  void remove(int id) => _volumes.remove(id);

  /// The volumes whose box intersects [area].
  List<HoneyGlue> inArea(Aabb area) => [
    for (final glue in _volumes.values)
      if (glue.box.intersects(area)) glue,
  ];

  /// Forgets every volume (server stop).
  void clear() => _volumes.clear();
}

/// The trackers, by world id.
final Map<String, HoneyGlueTracker> honeyGlueTrackers = {};

/// The tracker of [worldId], created on first use.
HoneyGlueTracker honeyGlueTrackerOf(String worldId) =>
    honeyGlueTrackers.putIfAbsent(worldId, HoneyGlueTracker.new);
