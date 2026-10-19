// The steam engine: the kinetic side only (it drives the powered shaft). The
// efficiency of the boiler behind it comes from a [SteamEngineBoilerSource]
// that the fluids module provides.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/block_entity.dart';
import '../core/blocks.dart';
import 'behavior_builder.dart';
import 'block_factory.dart';
import 'generators.dart';
import 'geometry.dart';
import 'kinetic_blocks_a.dart';
import 'behaviours.dart';
import 'placement.dart';
import 'placement_helper_host.dart';
import 'placement_helpers.dart';
import 'runtime.dart';
import 'settings.dart';

/// `RotationDirection`.
enum RotationDirection { clockwise, counterClockwise }

/// `SteamEngineBlockEntity`.
class SteamEngineBlockEntity extends CreateBlockEntity {
  late final ScrollValueBehaviour movementDirection;

  SteamEngineBlockEntity(super.worldId, super.pos) {
    movementDirection = addBehaviour(
      ScrollValueBehaviour()
        ..between(0, 1)
        ..onlyActiveWhen(() {
          final shaft = getShaft();
          return shaft == null || !shaft.hasSource;
        }),
    );
  }

  KineticsRuntime get runtime => KineticsRuntime.instance;

  KState get blockState {
    final w = world;
    if (w == null) return KState.air;
    return runtime.states.decode(w.getBlockStateId(pos: pos));
  }

  KPos get kpos => KPos(pos.x, pos.y, pos.z);

  /// `getShaft()`.
  PoweredShaftBlockEntity? getShaft() {
    final facing = steamEngineConnectedDirection(blockState);
    final p = kpos.relative(facing, 2);
    final be = store.at(worldId, BlockPos(x: p.x, y: p.y, z: p.z));
    if (be is PoweredShaftBlockEntity && be.canBePoweredBy(kpos)) return be;
    return null;
  }

  /// The efficiency of the boiler behind the engine, `null` without a tank.
  double? get boilerEfficiency {
    final source = runtime.boilerSource;
    if (source == null) return null;
    final facing = steamEngineConnectedDirection(blockState);
    final t = kpos.relative(facing.opposite);
    return source.engineEfficiency(worldId, t.x, t.y, t.z);
  }

  /// `isValid()`: the block behind is a fluid tank.
  bool get isValid {
    final facing = steamEngineConnectedDirection(blockState).opposite;
    return runtime
        .level(worldId)
        .stateAt(kpos.relative(facing))
        .isCreate('fluid_tank');
  }

  @override
  void tick() {
    super.tick();
    final w = world;
    if (w == null) return;
    final shaft = getShaft();
    final efficiencyRaw = boilerEfficiency;

    if (efficiencyRaw == null || shaft == null || !isValid) {
      if (shaft == null) return;
      if ((shaft.kpos - kpos) != shaft.enginePos) return;
      if (shaft.engineEfficiency == 0) return;
      final facing = steamEngineConnectedDirection(blockState);
      if (w.isLoaded(
        pos: BlockPos(
          x: pos.x + facing.opposite.dx,
          y: pos.y + facing.opposite.dy,
          z: pos.z + facing.opposite.dz,
        ),
      )) {
        shaft.update(kpos, 0, 0);
      }
      return;
    }

    final shaftState = shaft.blockState;
    final targetAxis =
        runtime.blocks.defFor(shaftState)?.rotationAxis(shaftState) ?? KAxis.x;
    final verticalTarget = targetAxis == KAxis.y;

    final state = blockState;
    if (!state.isCreate('steam_engine')) return;
    var facing = steamEngineConnectedDirection(state);
    if (facing.axis == KAxis.y) facing = state.dirOf('facing') ?? Dir.north;

    final efficiency = efficiencyRaw.clamp(0.0, 1.0);

    var conveyedSpeedLevel = efficiency == 0
        ? 1
        : (verticalTarget ? 1 : convertToDirection(1, facing).toInt());
    if (targetAxis == KAxis.z) conveyedSpeedLevel *= -1;
    if (movementDirection.getValue() ==
        RotationDirection.counterClockwise.index) {
      conveyedSpeedLevel *= -1;
    }

    final shaftSpeed = shaft.theoreticalSpeed;
    if (shaft.hasSource &&
        shaftSpeed != 0 &&
        conveyedSpeedLevel != 0 &&
        (shaftSpeed > 0) != (conveyedSpeedLevel > 0)) {
      movementDirection.setValue(1 - movementDirection.getValue());
      conveyedSpeedLevel *= -1;
    }

    shaft.update(
      kpos,
      conveyedSpeedLevel,
      efficiency,
      engineBlock: state.block,
    );
  }

  @override
  void onRemoved() {
    super.onRemoved();
    final shaft = getShaft();
    shaft?.removeEngine(kpos);
  }
}

KineticBlockSpec steamEngineBlockSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'steam_engine',
    blockEntityType: 'create:steam_engine',
    placement: [PlacementRule.inWater('waterlogged')],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      pathfindable: false,
      updateShape: waterloggedUpdateShape,
      use: (c, e) async {
        // SteamEngineBlock.PlacementHelper: a shaft goes on the engine's output.
        if (!e.withItem) return BlockUseResult.pass;
        final item = await e.item.getRegistryKey();
        if (item != 'create:shaft') return BlockUseResult.tryEmptyHand;
        final poweredBlock = c.rt.kineticBlocks['create:powered_shaft'];
        if (poweredBlock == null) return BlockUseResult.tryEmptyHand;
        final player = e.player;
        final look = orderedByNearest(player.getYaw(), player.getPitch());
        final offset = steamEngineShaftOffset(
          helperWorldFor(c.rt, c.worldId, c.world),
          c.kpos,
          c.state,
          look,
          steamEngineShaftValid,
          steamEngineShaftPos,
        );
        if (!offset.success) return BlockUseResult.tryEmptyHand;
        final placed = await placeOffset(
          c.rt,
          c.world,
          c.worldId,
          offset,
          poweredBlock,
          player,
          e.hand,
        );
        return placed ? BlockUseResult.success : BlockUseResult.tryEmptyHand;
      },
      afterPlaced: (c, e) async {
        // SteamEngineBlock.onPlace: the shaft in front becomes a powered shaft.
        final shaftPos = steamEngineShaftPos(c.state, c.kpos);
        final shaftState = c.level.stateAt(shaftPos);
        if (steamEngineShaftValid(c.state, shaftState)) {
          await setKState(
            c.rt,
            c.world,
            BlockPos(x: shaftPos.x, y: shaftPos.y, z: shaftPos.z),
            KState('create:powered_shaft', {
              'axis': shaftState['axis'] ?? 'y',
              'waterlogged': shaftState['waterlogged'] ?? 'false',
            }),
          );
        }
      },
      replaced: (c, e) {
        // affectNeighborsAfterRemoval: the powered shaft checks itself next tick.
        final shaftPos = steamEngineShaftPos(c.state, c.kpos);
        final shaftState = c.level.stateAt(shaftPos);
        if (shaftState.isCreate('powered_shaft')) {
          c.world.scheduleTick(
            BlockPos(x: shaftPos.x, y: shaftPos.y, z: shaftPos.z),
            const Duration(milliseconds: 50),
          );
        }
      },
      canPlace: (c, e) async {
        final player = e.player;
        if (player == null) return true;
        final pc = await placementContextFor(c, player, e.face, e.pos);
        if (pc == null) return true;
        return _steamEnginePlacement(pc) != null;
      },
    ),
  );
  spec = KineticBlockSpec(
    block,
    placement: (ctx, placed, use, world) =>
        _steamEnginePlacement(ctx, base: placed) ?? placed,
  );
  return spec;
}

/// `FaceAttachedHorizontalDirectionalBlock.getStateForPlacement` with the engine's
/// `canSurvive` (attached to a fluid tank).
KState? _steamEnginePlacement(PlacementContext ctx, {KState? base}) {
  final start =
      base ??
      const KState('create:steam_engine', {
        'face': 'floor',
        'facing': 'north',
        'waterlogged': 'false',
      });
  // The nearest looking directions in order.
  for (final direction in _lookOrder(ctx)) {
    KState s;
    if (direction.axis == KAxis.y) {
      s = start.setAll({
        'face': direction == Dir.up ? 'ceiling' : 'floor',
        'facing': ctx.horizontal.name,
      });
    } else {
      s = start.setAll({'face': 'wall', 'facing': direction.opposite.name});
    }
    final attachedTo = ctx.pos.relative(
      steamEngineConnectedDirection(s).opposite,
    );
    if (ctx.stateAt(attachedTo).isCreate('fluid_tank')) return s;
  }
  return null;
}

List<Dir> _lookOrder(PlacementContext ctx) {
  final first = ctx.nearestLooking;
  return [first, ...Dir.values.where((d) => d != first)];
}
