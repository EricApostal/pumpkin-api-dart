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
import 'dart:async';

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter, stateIdOf;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/host_bridge.dart';
import 'package:create/src/contraptions/bearing/bearing_placement.dart'
    show bearingPlacementRules;
import 'package:create/src/core/blocks.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../content/blocks/physics_assembler/physics_assembler_block_entity.dart';
import '../content/blocks/portable_engine/portable_engine_block.dart';
import '../content/blocks/spring/spring_block_entity.dart';
import '../content/blocks/steering_wheel/steering_wheel_block_entity.dart';
import '../content/blocks/swivel_bearing/swivel_bearing_block_entity.dart';
import '../content/blocks/symmetric_sail/symmetric_sail_lift_provider.dart';
import '../content/blocks/throttle_lever/throttle_lever_block_entity.dart';
import '../content/blocks/torsion_spring/torsion_spring_block_entity.dart';
import '../service/sim_services.dart';
import '../util/sim_placement_fixes.dart';
import 'sim_java_order.dart';

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
  static const List<String> sailColours = simDyeColors;

  /// The portable-engine colours, in dye order.
  static const List<String> engineColours = simDyeColors;

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
/// The order is the Java `SimBlocks` field order (`SimJavaOrder.blocks`), which
/// is what `SimRegistry` pins with `useOrder`; the ids follow that list either
/// way, but the file reads like the Java one.
///
/// [lookup] resolves a block entity by world and position; it is how the block
/// callbacks reach the entity the host ticked.
List<CreateBlock> simBlocks({required SimBlockLookup lookup}) {
  return [
    _physicsAssembler(lookup),
    _swivelBearing(lookup),
    _swivelBearingPlate(lookup),
    _torsionSpring(lookup),
    // `PORTABLE_ENGINES` (`SimBlocks.java:327-353`), in `DyeColor.values()` order.
    for (final colour in SimBlockKeys.engineColours)
      portableEngineBlock(colour, lookup: lookup),
    _steeringWheel(lookup),
    _throttleLever(lookup),
    for (final colour in SimBlockKeys.sailColours) _sail(colour),
    _spring(lookup),
  ];
}

CreateBlock _physicsAssembler(SimBlockLookup lookup) => CreateBlock(
  key: SimBlockKeys.physicsAssembler,
  // `PhysicsAssemblerBlock extends FaceAttachedHorizontalDirectionalBlock` and
  // adds `FACING, FACE` only (`PhysicsAssemblerBlock.java:30,110-112`); it is
  // not waterlogged, so `waterlogged` was two states this block does not have.
  //
  // No placement rules: the host's sources can write `facing` and `axis`, but
  // nothing gives `AttachFace`'s `floor` / `wall` / `ceiling`, and
  // `looking-direction` on the four-valued `facing` is exactly the illegal value
  // the host rejects at load ("property 'facing' has no value 'down'"). The state
  // `getStateForPlacement` chooses is written by the `player-placed` hook
  // instead, like Create's decoration blocks (`sim_placement.dart`).
  properties: [CreateProps.horizontalFacing, SimProps.face],
  defaultState: {'facing': 'north', 'face': 'wall'},
  hardness: 2,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'wood',
  collisionShape: SimShapes.assembler,
  selectionShape: SimShapes.assembler,
  tags: ['minecraft:mineable/pickaxe', 'minecraft:mineable/axe'],
  blockEntityType: PhysicsAssemblerBlockEntity.type,
  behavior: BlockBehavior(
    // `FaceAttachedHorizontalDirectionalBlock.getStateForPlacement`: the player's
    // ordered look directions pick `face` and `facing`. Only the event that carries
    // the player runs it (the host fires a plain `placed` first).
    onPlaced: (server, event) async {
      if (event.player == null) return;
      await fixFaceAttachedPlacement(
        server: server,
        world: event.targetWorld,
        pos: event.pos,
        block: event.block,
        stateIndex: event.stateIndex,
        playerId: event.player,
      );
    },
    onUseWithoutItem: (server, event) {
      final be = lookup<PhysicsAssemblerBlockEntity>(event.targetWorld.getId(), event.pos.toPos());
      // The assembly runs in the Sable component, so it cannot finish inside this
      // synchronous callback: it is started here and the result lands when the
      // round trip completes (the client's `simulated:assemble` path awaits it).
      unawaited(be?.assembleOrDisassemble());
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
  // `SteeringWheelBlock.getStateForPlacement`: `facing` is the opposite of the
  // first horizontal look direction (`getDirection()`) and the wheel is
  // waterlogged like Create's `WrenchableDirectionalBlock` family. `on_floor`
  // reads the clicked face, which no host source gives, so the `player-placed`
  // hook writes the whole state (`sim_placement.dart`).
  placement: const [
    PlacementRule.horizontalFacing('facing', opposite: true),
    PlacementRule.inWater('waterlogged'),
  ],
  behavior: BlockBehavior(
    onPlaced: (server, event) async {
      if (event.player == null) return;
      await fixSteeringWheelPlacement(
        server: server,
        world: event.targetWorld,
        pos: event.pos,
        block: event.block,
        stateIndex: event.stateIndex,
        playerId: event.player,
      );
    },
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
  // `ThrottleLeverBlock extends FaceAttachedHorizontalDirectionalBlock` and does
  // not override `getStateForPlacement`: `face` and `facing` come from the look
  // exactly like the assembler's (`INVERTED` is the wrench's, not a placement).
  behavior: BlockBehavior(
    onPlaced: (server, event) async {
      if (event.player == null) return;
      await fixFaceAttachedPlacement(
        server: server,
        world: event.targetWorld,
        pos: event.pos,
        block: event.block,
        stateIndex: event.stateIndex,
        playerId: event.player,
      );
    },
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
    // Only the white sail has an item: `WHITE_SYMMETRIC_SAIL` registers one
    // (`SimBlocks.java:775-776`) and `DYED_SYMMETRIC_SAILS` registers none
    // (`:779-800`), with a loot table that drops the white sail. Fifteen items
    // the Java does not have shifted the id of every item after them.
    //
    // The Java drop of `simulated:white_symmetric_sail` needs a loot table this
    // port does not ship (`docs/block-registry.md:122-125`), so a dyed sail drops
    // nothing.
    hasItem: colour == 'white',
    drops: colour == 'white' ? BlockDrops.selfItem : BlockDrops.nothing,
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
  // `SimBlocks.SPRING` registers no block item (`SimBlocks.java:843-855`): the
  // item is the standalone `simulated:spring` of `SimItems.SPRING`, a
  // `SpringItem` and not a `BlockItem` (`SimItems.java:41-54`), and the player
  // places the block through `simulated:place_spring`. A block item here
  // registered `simulated:spring` a second time and the whole registry threw.
  //
  // The Java loot table drops one `simulated:spring` (`SimBlocks.java:853-855`),
  // but the host's `self-item` drop is the item linked by `set-block-item`
  // (`docs/block-registry.md:122-125`) and this block has none, so the drop is
  // not expressible yet and the block drops nothing.
  hasItem: false,
  drops: BlockDrops.nothing,
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
  // `TorsionSpringBlock.getStateForPlacement` is
  // `DirectionalKineticBlock.getStateForPlacement` (the neighbour shaft decides
  // `facing`, the look does without one) plus `POWERED = level.hasNeighborSignal`,
  // which the host cannot read on placement: the rule set the bearing family uses
  // is the same Java method, and `POWERED` follows the redstone update that comes
  // with the placement.
  placement: bearingPlacementRules,
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
  // `SwivelBearingBlock` does not override `getStateForPlacement`: `facing` comes
  // from `DirectionalKineticBlock`, the same method the bearing family's rules
  // evaluate (`bearing_placement.dart`). `ASSEMBLED` and `POWERED` are the block
  // entity's, not the placement's.
  placement: bearingPlacementRules,
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
