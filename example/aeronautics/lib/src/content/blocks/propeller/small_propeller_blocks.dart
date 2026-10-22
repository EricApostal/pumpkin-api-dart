// The small propellers: a kinetic block entity that turns a shaft's speed into
// airflow, and the three block variants.
//
// Java: `content/blocks/propeller/small/{BasePropellerBlockEntity,wooden/*,andesite/*,smart_propeller/*}`.
//
// The block entity owns the pure [SmallPropellerLogic] and a
// [PropellerActorBehaviour]; sable calls `sable$physicsTick` through
// `BlockEntitySubLevelPropellerActor` once per physics substep, and the thrust
// goes into the `sable:propulsion` force group.
// ignore_for_file: implementation_imports
import 'package:create/create.dart';
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Axis, Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/kinetics/behavior_builder.dart' show buildKineticBehavior;
import 'package:create/src/kinetics/block_data.dart' show facingShaftTag;
import 'package:create/src/kinetics/block_factory.dart' show KineticBlockSpec;
import 'package:create/src/kinetics/kinetic_block_entity.dart';
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart';

import '../../../config/aero_config.dart';
import '../../../host/host_propeller_push_world.dart';
import '../../../host/world_balloon_world.dart';
import '../../../propeller/placement.dart'
    show propellerPlacementRules, smartPropellerPlacement;
import '../../../propeller/propeller_actor_behaviour.dart';
import '../../../propeller/small_propeller.dart';
import 'propeller_block_entity_mixin.dart';

/// The block keys of the small propellers.
abstract final class SmallPropellerKeys {
  static const String wooden = 'aeronautics:wooden_propeller';
  static const String andesite = 'aeronautics:andesite_propeller';
  static const String smart = 'aeronautics:smart_propeller';
}

/// `BasePropellerBlockEntity`.
abstract class BasePropellerBlockEntity extends KineticBlockEntity
    with SubLevelPropellerActorMixin, PropellerBlockEntityMixin
    implements BlockEntitySubLevelPropellerActor, BlockEntityPropeller, PropellerActorView {
  BasePropellerBlockEntity(super.worldId, super.pos);

  final SmallPropellerLogic _logic = SmallPropellerLogic();

  /// The pure rotation and thrust maths.
  SmallPropellerLogic get logic => _logic;

  /// The thrust direction, in the sub-level's frame.
  @override
  final Vector3d thrustDirection = Vector3d();

  late final PropellerActorBehaviour prop = _createProp();

  late final PropellerPushWorld _pushWorld = HostPropellerPushWorld(world!, blockPos);

  /// The thrust scalar of this propeller, from the config.
  double get configThrust;

  /// The airflow scalar of this propeller, from the config.
  double get configAirflow;

  /// The radius of the disc, for the entity push.
  double get radius;

  /// The distance of the disc along the facing axis.
  double get offset => 0;

  /// `BasePropellerBlock.REVERSED`.
  bool get reversed => bState.flag('reversed');

  /// The state of the block as plain data.
  BState get bState => BState(blockState.block, blockState.props);

  PropellerActorBehaviour _createProp() {
    final behaviour = PropellerActorBehaviour(this);
    behaviour.maxParticleAmount = 5;
    behaviour.particleSmoothing = 2;
    behaviour.addSimpleLayer(offset, radius);
    return behaviour;
  }

  // -- BlockEntityPropeller ------------------------------------------------------

  @override
  Direction getBlockDirection() => blockDirection;

  @override
  double getAirflow() => airflow;

  @override
  double getThrust() => thrust;

  @override
  bool isActive() => logic.isActive;

  @override
  SableLevel getLevel() {
    final w = world;
    if (w == null) {
      throw StateError('$this: the world is not loaded');
    }
    return balloonWorldOf(w).level;
  }

  @override
  Pos getBlockPos() => blockPos;

  @override
  BlockEntityPropeller getPropeller() => this;

  // -- PropellerActorView ---------------------------------------------------------

  @override
  Direction get blockDirection => bState.dir('facing') ?? Direction.north;

  @override
  Pos get blockPos => (pos.x, pos.y, pos.z);

  @override
  double get thrust => logic.thrust(configThrust);

  @override
  double get airflow => logic.airflow(configAirflow);

  @override
  double get airPressure {
    final level = getLevel();
    final center = Vector3d(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5);
    return DimensionPhysicsData.getAirPressure(level, SubLevelHelper.projectOutOfSubLevel(level, center));
  }

  // -- Lifecycle -----------------------------------------------------------------

  @override
  void onLoad() {
    logic.facing = blockDirection;
    super.onLoad();
  }

  @override
  void tick() {
    logic.reversed = reversed;
    logic.facing = blockDirection;
    logic.updateRotationSpeed(speed);
    logic.tick();
    updateThrustDirection();

    super.tick();

    if (logic.isActive) prop.pushEntities(_pushWorld);
  }

  /// Sets [thrustDirection] from the block's facing; the smart propeller
  /// overrides this with its hinge.
  void updateThrustDirection() {
    thrustDirection.set(
      logic.facing.stepX.toDouble(),
      logic.facing.stepY.toDouble(),
      logic.facing.stepZ.toDouble(),
    );
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putFloat('RotationSpeed', logic.rotationSpeed);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    logic.rotationSpeed = tag.getDouble('RotationSpeed') ?? 0;
  }
}

/// `WoodenPropellerBlockEntity`.
final class WoodenPropellerBlockEntity extends BasePropellerBlockEntity {
  WoodenPropellerBlockEntity(super.worldId, super.pos);

  @override
  double get configThrust => AeroConfig.server.physics.woodenPropellerThrust;

  @override
  double get configAirflow => AeroConfig.server.physics.woodenPropellerAirflow;

  @override
  double get radius => 1.5;

  @override
  double get offset => 3 / 16;
}

/// `AndesitePropellerBlockEntity`.
final class AndesitePropellerBlockEntity extends BasePropellerBlockEntity {
  AndesitePropellerBlockEntity(super.worldId, super.pos);

  @override
  double get configThrust => AeroConfig.server.physics.andesitePropellerThrust;

  @override
  double get configAirflow => AeroConfig.server.physics.andesitePropellerAirflow;

  @override
  double get radius => 1;
}

/// `SmartPropellerBlockEntity`.
final class SmartPropellerBlockEntity extends BasePropellerBlockEntity {
  SmartPropellerBlockEntity(super.worldId, super.pos);

  /// The smart propeller's own maths: the hinge and the tilted thrust.
  final SmartPropellerLogic smart = SmartPropellerLogic();

  @override
  SmallPropellerLogic get logic => smart;

  @override
  double get configThrust => AeroConfig.server.physics.smartPropellerThrust;

  @override
  double get configAirflow => AeroConfig.server.physics.smartPropellerAirflow;

  @override
  double get radius => 1;

  @override
  double get offset => 10 / 16;

  @override
  void onLoad() {
    smart.ceiling = bState.flag('ceiling');
    smart.horizontalAxis = bState.axisOf('horizontal_axis') ?? Axis.x;
    smart.hingeAngle = smart.ceiling ? 180 : 0;
    smart.hingeTarget = smart.hingeAngle;
    super.onLoad();
  }

  @override
  void tick() {
    super.tick();

    smart.ceiling = bState.flag('ceiling');
    smart.horizontalAxis = bState.axisOf('horizontal_axis') ?? Axis.x;

    final level = getLevel();
    final subLevel = SubLevelHelper.getContaining(level, blockPos);
    smart.updateHingeAngle(subLevel?.logicalPose.orientation());
    smart.tickHinge(0.1);
    smart.updateThrustDirection();
  }

  /// `SmartPropellerBlockEntity.setThrustDirection`.
  @override
  void updateThrustDirection() {
    smart.updateThrustDirection();
    thrustDirection.setFrom(smart.thrustDir);
  }

  @override
  void sable$physicsTick(ServerSubLevel subLevel, RigidBodyHandle handle, double timeStep) {
    updateThrustDirection();
    if (!logic.isActive) return;
    applyForces(subLevel, thrustDirection, timeStep);
  }
}

/// The block definitions of the three small propellers.
List<CreateBlock> buildSmallPropellerBlocks() => [
  _smallPropellerBlock(SmallPropellerKeys.wooden, 'aeronautics:wooden_propeller'),
  _smallPropellerBlock(SmallPropellerKeys.andesite, 'aeronautics:andesite_propeller'),
  _smartPropellerBlock(),
];

CreateBlock _smallPropellerBlock(String key, String type) => CreateBlock(
  key: key,
  properties: [CreateProps.facing, BlockProperty.boolean('reversed')],
  defaultState: {'facing': 'north'},
  hardness: 2,
  blastResistance: 4,
  requiresCorrectTool: true,
  soundType: 'wood',
  canOcclude: false,
  tags: [facingShaftTag],
  placement: propellerPlacementRules,
  blockEntityType: type,
);

/// `SmartPropellerBlock`: `HorizontalAxisKineticBlock`'s hinge axis, swapped, plus `ceiling`.
///
/// The host cannot express the swap in a placement rule, so the state the host placed is
/// corrected once the placing player is known (`KineticBlockSpec.placement`), the same way
/// Create's own kinetic blocks correct theirs.
CreateBlock _smartPropellerBlock() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = CreateBlock(
    key: SmallPropellerKeys.smart,
    properties: [
      BlockProperty.enumeration('horizontal_axis', ['x', 'z']),
      BlockProperty.boolean('reversed'),
      BlockProperty.boolean('ceiling'),
    ],
    defaultState: {'horizontal_axis': 'x'},
    hardness: 2,
    blastResistance: 4,
    requiresCorrectTool: true,
    soundType: 'copper',
    canOcclude: false,
    tags: [facingShaftTag],
    blockEntityType: 'aeronautics:smart_propeller',
    behavior: buildKineticBehavior(() => block, specRef: () => spec),
  );
  spec = KineticBlockSpec(
    block,
    placement: (ctx, placed, use, world) => smartPropellerPlacement(ctx, placed),
  );
  return block;
}
