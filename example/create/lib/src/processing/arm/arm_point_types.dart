// `AllArmInteractionPointTypes`: the kinds of blocks the mechanical arm can interact with, in the
// registration order of the `create:arm_interaction_point_type` registry (the manifest order).
//
// Ported from `content/kinetics/mechanicalArm/AllArmInteractionPointTypes.java`. The types of
// blocks other modules own (basin, belt, chute, funnel, ...) only check the block key, so they do
// not depend on those modules being loaded.
import '../../api/block_state.dart';
import '../../common/common.dart';
import '../support/kinetics_bridge.dart';
import 'arm_interaction_point.dart';

/// The basin (`create:basin`).
class BasinType extends ArmInteractionPointType {
  const BasinType() : super('create:basin');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) =>
      state.key == 'create:basin';
}

/// A belt segment that transports items (`BeltBlock.canTransportObjects`).
class BeltType extends ArmInteractionPointType {
  const BeltType() : super('create:belt');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) {
    if (state.key != 'create:belt') return false;
    if (level.stateAt(pos.above).key == 'create:belt_tunnel') return false;
    return state['part'] != 'pulley';
  }

  @override
  ArmInteractionPoint createPoint(ArmWorld level, Pos pos, BState state) =>
      BeltPoint(this, level, pos, state);
}

/// The blaze burner (`create:blaze_burner`).
class BlazeBurnerType extends ArmInteractionPointType {
  const BlazeBurnerType() : super('create:blaze_burner');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) =>
      state.key == 'create:blaze_burner';

  @override
  ArmInteractionPoint createPoint(ArmWorld level, Pos pos, BState state) =>
      BlazeBurnerPoint(this, level, pos, state);
}

/// A chute (`create:chute`, `create:smart_chute`).
class ChuteType extends ArmInteractionPointType {
  const ChuteType() : super('create:chute');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) =>
      state.key == 'create:chute' || state.key == 'create:smart_chute';

  @override
  ArmInteractionPoint createPoint(ArmWorld level, Pos pos, BState state) =>
      TopFaceArmInteractionPoint(this, level, pos, state);
}

/// The mechanical crafter (`create:mechanical_crafter`).
class CrafterType extends ArmInteractionPointType {
  const CrafterType() : super('create:crafter');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) =>
      state.key == 'create:mechanical_crafter';

  @override
  ArmInteractionPoint createPoint(ArmWorld level, Pos pos, BState state) =>
      CrafterPoint(this, level, pos, state);
}

/// The crushing wheel controller (`create:crushing_wheel_controller`).
class CrushingWheelsType extends ArmInteractionPointType {
  const CrushingWheelsType() : super('create:crushing_wheels');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) =>
      state.key == 'create:crushing_wheel_controller';

  @override
  ArmInteractionPoint createPoint(ArmWorld level, Pos pos, BState state) =>
      CrushingWheelPoint(this, level, pos, state);
}

/// The deployer (`create:deployer`).
class DeployerType extends ArmInteractionPointType {
  const DeployerType() : super('create:deployer');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) =>
      state.key == 'create:deployer';

  @override
  ArmInteractionPoint createPoint(ArmWorld level, Pos pos, BState state) =>
      DeployerPoint(this, level, pos, state);
}

/// Depots, weighted ejectors and track stations.
class DepotType extends ArmInteractionPointType {
  const DepotType() : super('create:depot');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) =>
      state.key == 'create:depot' ||
      state.key == 'create:weighted_ejector' ||
      state.key == 'create:track_station';

  @override
  ArmInteractionPoint createPoint(ArmWorld level, Pos pos, BState state) =>
      DepotPoint(this, level, pos, state);
}

/// A funnel that takes items.
class FunnelType extends ArmInteractionPointType {
  const FunnelType() : super('create:funnel');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) {
    final key = state.key;
    if (!key.endsWith('_funnel') && key != 'create:funnel') return false;
    if (state.flag('extracting')) return false;
    if (state['shape'] == 'pushing') return false;
    return true;
  }

  @override
  ArmInteractionPoint createPoint(ArmWorld level, Pos pos, BState state) =>
      FunnelPoint(this, level, pos, state);
}

/// The millstone (`create:millstone`).
class MillstoneType extends ArmInteractionPointType {
  const MillstoneType() : super('create:millstone');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) =>
      state.key == 'create:millstone';
}

/// The packager and repackager.
class PackagerType extends ArmInteractionPointType {
  const PackagerType() : super('create:packager');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) =>
      state.key == 'create:packager' || state.key == 'create:repackager';
}

/// An upward facing saw that runs.
class SawType extends ArmInteractionPointType {
  const SawType() : super('create:saw');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) {
    if (state.key != 'create:mechanical_saw') return false;
    if (state.dir('facing') != Direction.up) return false;
    final be = level.beAt(pos);
    return be is KineticBlockEntity && be.speed != 0;
  }

  @override
  ArmInteractionPoint createPoint(ArmWorld level, Pos pos, BState state) =>
      DepotPoint(this, level, pos, state);
}

/// A campfire.
class CampfireType extends ArmInteractionPointType {
  const CampfireType() : super('create:campfire');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) =>
      state.key == 'minecraft:campfire' ||
      state.key == 'minecraft:soul_campfire';

  @override
  ArmInteractionPoint createPoint(ArmWorld level, Pos pos, BState state) =>
      CampfirePoint(this, level, pos, state);
}

/// A composter.
class ComposterType extends ArmInteractionPointType {
  const ComposterType() : super('create:composter');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) =>
      state.key == 'minecraft:composter';

  @override
  ArmInteractionPoint createPoint(ArmWorld level, Pos pos, BState state) =>
      ComposterPoint(this, level, pos, state);
}

/// A jukebox.
class JukeboxType extends ArmInteractionPointType {
  const JukeboxType() : super('create:jukebox');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) =>
      state.key == 'minecraft:jukebox';

  @override
  ArmInteractionPoint createPoint(ArmWorld level, Pos pos, BState state) =>
      JukeboxPoint(this, level, pos, state);
}

/// A respawn anchor.
class RespawnAnchorType extends ArmInteractionPointType {
  const RespawnAnchorType() : super('create:respawn_anchor');

  @override
  bool canCreatePoint(ArmWorld level, Pos pos, BState state) =>
      state.key == 'minecraft:respawn_anchor';

  @override
  ArmInteractionPoint createPoint(ArmWorld level, Pos pos, BState state) =>
      RespawnAnchorPoint(this, level, pos, state);
}

/// The point types in registration order (the manifest's
/// `create:arm_interaction_point_type` entries).
const List<ArmInteractionPointType> armInteractionPointTypes = [
  BasinType(),
  BeltType(),
  BlazeBurnerType(),
  ChuteType(),
  CrafterType(),
  CrushingWheelsType(),
  DeployerType(),
  DepotType(),
  FunnelType(),
  MillstoneType(),
  PackagerType(),
  SawType(),
  CampfireType(),
  ComposterType(),
  JukeboxType(),
  RespawnAnchorType(),
];

/// The keys of the point types, for the synced registry.
List<String> get armInteractionPointTypeKeys => [
  for (final type in armInteractionPointTypes) type.key,
];

/// The type registered under [key], `null` for an unknown one.
ArmInteractionPointType? armPointTypeOf(String key) {
  for (final type in armInteractionPointTypes) {
    if (type.key == key) return type;
  }
  return null;
}

/// `ArmInteractionPointType.getPrimaryType`: the first type that accepts the block.
ArmInteractionPointType? primaryArmPointType(
  ArmWorld level,
  Pos pos,
  BState state,
) {
  for (final type in armInteractionPointTypes) {
    if (type.canCreatePoint(level, pos, state)) return type;
  }
  return null;
}

/// `ArmInteractionPoint.create`.
ArmInteractionPoint? createArmInteractionPoint(
  ArmWorld level,
  Pos pos,
  BState state,
) {
  final type = primaryArmPointType(level, pos, state);
  return type?.createPoint(level, pos, state);
}

/// `ArmInteractionPoint.isInteractable`.
bool isArmInteractable(ArmWorld level, Pos pos, BState state) =>
    primaryArmPointType(level, pos, state) != null;
