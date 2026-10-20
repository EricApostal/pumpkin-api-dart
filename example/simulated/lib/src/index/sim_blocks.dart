// The blocks of Simulated: their states, shapes and the hooks the host calls.
//
// Java builds these through Registrate. A Dart block is a [CreateBlock] plus a
// [BlockBehavior]; the order of this file is the registration order, which
// decides the state ids a NeoForge client expects.
//
// Host: this file uses `pumpkin_api`.
//
// Java: dev.simulated_team.simulated.index.SimBlocks
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter, stateIdOf;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/host_bridge.dart';
import 'package:create/src/core/blocks.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../content/blocks/physics_assembler/physics_assembler_block_entity.dart';
import '../content/blocks/spring/spring_block_entity.dart';
import '../content/blocks/steering_wheel/steering_wheel_block_entity.dart';
import '../content/blocks/swivel_bearing/swivel_bearing_block_entity.dart';
import '../content/blocks/symmetric_sail/symmetric_sail_lift_provider.dart';
import '../content/blocks/throttle_lever/throttle_lever_block_entity.dart';
import '../content/blocks/torsion_spring/torsion_spring_block_entity.dart';
import '../service/sim_services.dart';

/// The state properties Simulated adds to the vanilla ones.
abstract final class SimProps {
  /// `AttachFace`: floor, wall, ceiling.
  static final BlockProperty face = BlockProperty.enumeration('face', ['floor', 'wall', 'ceiling']);

  /// `SpringBlock.Size`.
  static final BlockProperty size = BlockProperty.enumeration('size', ['small', 'medium', 'large']);

  static final BlockProperty assembled = BlockProperty.boolean('assembled');
  static final BlockProperty inverted = BlockProperty.boolean('inverted');
  static final BlockProperty onFloor = BlockProperty.boolean('on_floor');
}

/// The block keys.
abstract final class SimBlockKeys {
  static const String physicsAssembler = 'simulated:physics_assembler';
  static const String steeringWheel = 'simulated:steering_wheel';
  static const String throttleLever = 'simulated:throttle_lever';
  static const String spring = 'simulated:spring';
  static const String torsionSpring = 'simulated:torsion_spring';
  static const String swivelBearing = 'simulated:swivel_bearing';
  static const String swivelBearingPlate = 'simulated:swivel_bearing_link_block';

  /// The sail colours, in dye order.
  static const List<String> sailColours = [
    'white',
    'orange',
    'magenta',
    'light_blue',
    'yellow',
    'lime',
    'pink',
    'gray',
    'light_gray',
    'cyan',
    'purple',
    'blue',
    'brown',
    'green',
    'red',
    'black',
  ];

  static String sail(String colour) => 'simulated:${colour}_symmetric_sail';
}

/// The block shapes: the plates of the blocks that are not full cubes.
abstract final class SimShapes {
  /// The assembler's body: a plate on the face it is attached to, plus a lever.
  static final BlockShape assembler = BlockShape.boxes(const [
    BlockBox(2 / 16, 0, 2 / 16, 14 / 16, 3 / 16, 14 / 16),
    BlockBox(6 / 16, 3 / 16, 6 / 16, 10 / 16, 10 / 16, 10 / 16),
  ]);

  /// The spring's coil, one block deep along its facing.
  static final BlockShape spring = BlockShape.boxes(const [
    BlockBox(4 / 16, 0, 4 / 16, 12 / 16, 1, 12 / 16),
  ]);

  /// The torsion spring's body.
  static final BlockShape torsionSpring = BlockShape.boxes(const [
    BlockBox(2 / 16, 2 / 16, 0, 14 / 16, 14 / 16, 1),
  ]);

  /// The swivel bearing's body, before it is assembled.
  static final BlockShape swivelBearing = BlockShape.boxes(const [
    BlockBox(0, 0, 0, 1, 1, 1),
  ]);

  /// The swivel bearing's plate.
  static final BlockShape swivelBearingPlate = BlockShape.boxes(const [
    BlockBox(0, 0, 0, 1, 1, 2 / 16),
  ]);

  /// The steering wheel's mount.
  static final BlockShape steeringWheel = BlockShape.boxes(const [
    BlockBox(0, 0, 0, 1, 3 / 16, 1),
    BlockBox(2 / 16, 3 / 16, 6 / 16, 14 / 16, 1, 10 / 16),
  ]);

  /// The throttle lever's body.
  static final BlockShape throttleLever = BlockShape.boxes(const [
    BlockBox(3 / 16, 0, 3 / 16, 13 / 16, 3 / 16, 13 / 16),
    BlockBox(6 / 16, 3 / 16, 6 / 16, 10 / 16, 12 / 16, 10 / 16),
  ]);

  /// The sail: a thin sheet across its axis.
  static BlockShape sail(String axis) => switch (axis) {
    'x' => BlockShape.boxes(const [BlockBox(0, 0, 0, 1 / 16, 1, 1)]),
    'z' => BlockShape.boxes(const [BlockBox(0, 0, 0, 1, 1, 1 / 16)]),
    _ => BlockShape.boxes(const [BlockBox(0, 0, 0, 1, 1 / 16, 1)]),
  };
}

/// Resolves a block entity by world and position.
typedef SimBlockLookup = E? Function<E>(String worldId, (int, int, int) pos);

/// Builds the blocks of the mod, in registration order.
///
/// [lookup] resolves a block entity by world and position; it is how the block
/// callbacks reach the entity the host ticked.
List<CreateBlock> simBlocks({required SimBlockLookup lookup}) {
  final blocks = <CreateBlock>[
    _physicsAssembler(lookup),
    _steeringWheel(lookup),
    _throttleLever(lookup),
    for (final colour in SimBlockKeys.sailColours) _sail(colour),
    _spring(lookup),
    _torsionSpring(lookup),
    _swivelBearing(lookup),
    _swivelBearingPlate(lookup),
  ];
  return blocks;
}

CreateBlock _physicsAssembler(SimBlockLookup lookup) => CreateBlock(
  key: SimBlockKeys.physicsAssembler,
  properties: [CreateProps.horizontalFacing, SimProps.face, CreateProps.waterlogged],
  defaultState: {'facing': 'north', 'face': 'wall', 'waterlogged': 'false'},
  hardness: 2,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'wood',
  collisionShape: SimShapes.assembler,
  selectionShape: SimShapes.assembler,
  tags: ['minecraft:mineable/pickaxe', 'minecraft:mineable/axe'],
  blockEntityType: PhysicsAssemblerBlockEntity.type,
  behavior: BlockBehavior(
    onUseWithoutItem: (server, event) {
      final be = lookup<PhysicsAssemblerBlockEntity>(event.targetWorld.getId(), event.pos.toPos());
      be?.assembleOrDisassemble();
      return BlockUseResult.success;
    },
  ),
);

CreateBlock _steeringWheel(SimBlockLookup lookup) => CreateBlock(
  key: SimBlockKeys.steeringWheel,
  properties: [CreateProps.horizontalFacing, SimProps.onFloor, CreateProps.waterlogged],
  defaultState: {'facing': 'north', 'on_floor': 'true', 'waterlogged': 'false'},
  hardness: 2,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'wood',
  collisionShape: SimShapes.steeringWheel,
  selectionShape: SimShapes.steeringWheel,
  tags: ['minecraft:mineable/axe'],
  blockEntityType: SteeringWheelBlockEntity.type,
  behavior: BlockBehavior(
    onComparatorOutput: (server, event) {
      final be = lookup<SteeringWheelBlockEntity>(event.targetWorld.getId(), event.pos.toPos());
      if (be == null) return null;
      final side = Direction.byName(event.face.wireName) ?? Direction.north;
      return be.analogOutput(side);
    },
  ),
);

CreateBlock _throttleLever(SimBlockLookup lookup) => CreateBlock(
  key: SimBlockKeys.throttleLever,
  properties: [CreateProps.horizontalFacing, SimProps.face, SimProps.inverted],
  defaultState: {'facing': 'north', 'face': 'wall', 'inverted': 'false'},
  hardness: 1,
  blastResistance: 3,
  soundType: 'wood',
  collisionShape: SimShapes.throttleLever,
  selectionShape: SimShapes.throttleLever,
  tags: ['minecraft:mineable/axe'],
  blockEntityType: ThrottleLeverBlockEntity.type,
  behavior: BlockBehavior(
    onUseWithoutItem: (server, event) {
      final be = lookup<ThrottleLeverBlockEntity>(event.targetWorld.getId(), event.pos.toPos());
      be?.changeState(back: event.sneaking);
      return BlockUseResult.success;
    },
    onWeakPower: (server, event) {
      final be = lookup<ThrottleLeverBlockEntity>(event.targetWorld.getId(), event.pos.toPos());
      return be?.logic.outputSignal ?? 0;
    },
    onStrongPower: (server, event) {
      final be = lookup<ThrottleLeverBlockEntity>(event.targetWorld.getId(), event.pos.toPos());
      return be?.logic.outputSignal ?? 0;
    },
  ),
);

CreateBlock _sail(String colour) {
  final key = SimBlockKeys.sail(colour);
  return CreateBlock(
    key: key,
    properties: [CreateProps.axis],
    defaultState: {'axis': 'y'},
    hardness: 1,
    blastResistance: 1,
    soundType: 'wool',
    canOcclude: false,
    collisionShape: SimShapes.sail('y'),
    selectionShape: SimShapes.sail('y'),
    shapeRules: [
      for (final axis in ['x', 'z'])
        ShapeRule(when: {'axis': axis}, collisionShape: SimShapes.sail(axis), selectionShape: SimShapes.sail(axis)),
    ],
    tags: ['simulated:symmetric_sails'],
    behavior: BlockBehavior(
      onUseWithItem: (server, event) async {
        final itemKey = await event.item.getRegistryKey();
        final colour = SimServices.dyeColorOf(itemKey);
        if (colour == null) return BlockUseResult.pass;
        final world = event.targetWorld;
        final base = event.pos.toPos();
        final state = HostBlockGetter.stateOfIndex(event.block, event.stateIndex);
        SymmetricSailDye.applyDye(
          state: state,
          colour: colour,
          neighbourAt: (offset) => _sailStateAt(world, base, offset),
          setAt: (offset, newState) {
            final target = (base.$1 + offset.$1, base.$2 + offset.$2, base.$3 + offset.$3);
            final id = stateIdOf(newState);
            if (id == null) return;
            ignoredSet(world, target, id);
          },
        );
        return BlockUseResult.success;
      },
    ),
  );
}

CreateBlock _spring(SimBlockLookup lookup) => CreateBlock(
  key: SimBlockKeys.spring,
  properties: [CreateProps.facing, SimProps.size],
  defaultState: {'facing': 'up', 'size': 'medium'},
  hardness: 1,
  blastResistance: 2,
  soundType: 'metal',
  collisionShape: SimShapes.spring,
  selectionShape: SimShapes.spring,
  tags: ['minecraft:mineable/pickaxe'],
  blockEntityType: SpringBlockEntity.type,
  behavior: BlockBehavior(
    onUseWithoutItem: (server, event) {
      final be = lookup<SpringBlockEntity>(event.targetWorld.getId(), event.pos.toPos());
      if (be == null) return BlockUseResult.pass;
      final back = event.sneaking;
      be.tryChangeLength(back ? -0.25 : 0.25);
      return BlockUseResult.success;
    },
  ),
);

CreateBlock _torsionSpring(SimBlockLookup lookup) => CreateBlock(
  key: SimBlockKeys.torsionSpring,
  properties: [CreateProps.facing, CreateProps.powered],
  defaultState: {'facing': 'up', 'powered': 'false'},
  hardness: 2,
  blastResistance: 6,
  soundType: 'metal',
  collisionShape: SimShapes.torsionSpring,
  selectionShape: SimShapes.torsionSpring,
  tags: ['minecraft:mineable/pickaxe'],
  blockEntityType: TorsionSpringBlockEntity.type,
  behavior: BlockBehavior(
    onComparatorOutput: (server, event) {
      final be = lookup<TorsionSpringBlockEntity>(event.targetWorld.getId(), event.pos.toPos());
      if (be == null) return null;
      return be.analogOutput(event.face.wireName);
    },
    onNeighborUpdate: (server, event) {
      final world = event.targetWorld;
      final be = lookup<TorsionSpringBlockEntity>(world.getId(), event.pos.toPos());
      be?.onSignalChanged();
    },
  ),
);

CreateBlock _swivelBearing(SimBlockLookup lookup) => CreateBlock(
  key: SimBlockKeys.swivelBearing,
  properties: [CreateProps.facing, SimProps.assembled, CreateProps.powered],
  defaultState: {'facing': 'up', 'assembled': 'false', 'powered': 'false'},
  hardness: 5,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'netherite_block',
  canOcclude: false,
  collisionShape: SimShapes.swivelBearing,
  selectionShape: SimShapes.swivelBearing,
  tags: ['minecraft:mineable/pickaxe', 'simulated:non_movable', 'create:non_movable'],
  blockEntityType: SwivelBearingBlockEntity.type,
  behavior: BlockBehavior(
    onUseWithoutItem: (server, event) {
      final be = lookup<SwivelBearingBlockEntity>(event.targetWorld.getId(), event.pos.toPos());
      if (be == null) return BlockUseResult.pass;
      be.assembleNextTick = true;
      return BlockUseResult.success;
    },
  ),
);

CreateBlock _swivelBearingPlate(SimBlockLookup lookup) => CreateBlock(
  key: SimBlockKeys.swivelBearingPlate,
  properties: [CreateProps.facing],
  defaultState: {'facing': 'up'},
  hardness: 5,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'netherite_block',
  collisionShape: SimShapes.swivelBearingPlate,
  selectionShape: SimShapes.swivelBearingPlate,
  hasItem: false,
  drops: BlockDrops.nothing,
  tags: ['minecraft:mineable/pickaxe', 'simulated:non_movable', 'create:non_movable', 'simulated:super_light'],
  blockEntityType: SwivelBearingPlateBlockEntity.type,
  behavior: BlockBehavior(
    onUseWithoutItem: (server, event) {
      final be = lookup<SwivelBearingPlateBlockEntity>(event.targetWorld.getId(), event.pos.toPos());
      be?.setParentAssembleNextTick();
      return BlockUseResult.success;
    },
  ),
);

/// The state of a sail at [base] + [offset].
BState _sailStateAt(World world, (int, int, int) base, (int, int, int) offset) {
  final pos = (base.$1 + offset.$1, base.$2 + offset.$2, base.$3 + offset.$3);
  return HostBlockGetter.stateOfId(world.getBlockStateId(pos: pos.toBlockPos()));
}

void ignoredSet(World world, (int, int, int) pos, int stateId) {
  world
      .setBlockState(pos: pos.toBlockPos(), state: stateId, updateFlags: BlockUpdateFlags.normal)
      .catchError((Object _) {});
}
