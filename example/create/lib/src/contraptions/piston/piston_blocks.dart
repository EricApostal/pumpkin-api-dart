// The mechanical piston, its head and its extension poles: placement, the slime ball upgrade, the
// scheduled tick that clears a failed assembly, and the cleanup when the base or the head is
// broken.
//
// Java: `content/contraptions/piston/{MechanicalPistonBlock,MechanicalPistonHeadBlock,
// PistonExtensionPoleBlock}`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../api/wrenchable.dart';
import '../../common/common.dart';
import '../../core/blocks.dart';
import '../blocks/actuator_runtime.dart';
import 'linear_actuator_logic.dart';
import 'piston_contraption.dart';

const String mechanicalPistonKey = 'create:mechanical_piston';
const String stickyMechanicalPistonKey = 'create:sticky_mechanical_piston';
const String pistonExtensionPoleKey = 'create:piston_extension_pole';
const String pistonHeadKey = 'create:mechanical_piston_head';

/// The piston family block definitions.
List<CreateBlock> buildPistonBlocks() => [
  manifestBlock(
    'mechanical_piston',
    // `DirectionalAxisKineticBlock.getFacingForPlacement`: the nearest looking direction,
    // opposite (a sneaking player flips it; the host rule cannot see sneaking).
    placement: const [PlacementRule.lookingDirection('facing', opposite: true)],
    behavior: pistonBehavior(sticky: false),
    blockEntityType: mechanicalPistonKey,
  ),
  manifestBlock(
    'sticky_mechanical_piston',
    placement: const [PlacementRule.lookingDirection('facing', opposite: true)],
    behavior: pistonBehavior(sticky: true),
    blockEntityType: mechanicalPistonKey,
  ),
  manifestBlock(
    'piston_extension_pole',
    placement: const [
      PlacementRule.clickedFace('facing'),
      PlacementRule.inWater('waterlogged'),
    ],
    behavior: null,
  ),
  manifestBlock(
    'mechanical_piston_head',
    placement: const [
      PlacementRule.clickedFace('facing'),
      PlacementRule.inWater('waterlogged'),
    ],
    behavior: pistonHeadBehavior(),
  ),
];

/// `MechanicalPistonBlock` behaviour: an empty hand starts the assembly, a slime ball makes the
/// piston sticky, a neighbour change rechecks the head, and breaking the base removes the head.
BlockBehavior pistonBehavior({required bool sticky}) => BlockBehavior(
  onPlaced: (server, e) async {
    // `DirectionalAxisKineticBlock.getStateForPlacement`: a shaft above or below turns the
    // piston's rotation axis. (A vertical facing uses the player's horizontal look, which the
    // placement event does not carry; the host default stays.)
    if (e.moved || e.player == null) return;
    final pos = (e.pos.x, e.pos.y, e.pos.z);
    final state = HostBlockGetter.stateOfId(e.stateIndex);
    final facing = state.dir('facing') ?? Direction.north;
    if (!facing.axis.isHorizontal) return;
    final level = HostBlockGetter(e.targetWorld);
    final alongFirst = pistonAlongFirstForPlacement(
      facing,
      (Direction side) =>
          prefersShaftConnection(level, pos.relative(side), side),
    );
    final next = state.setFlag('axis_along_first', alongFirst);
    if (next != state) await setBlockState(e.targetWorld, pos, next);
  },
  onUseWithItem: (server, e) async {
    // `Player.mayBuild()`: adventure and spectator players cannot place blocks.
    if (e.player.isAdventure || e.player.isSpectator)
      return BlockUseResult.tryEmptyHand;
    if (e.sneaking) return BlockUseResult.tryEmptyHand;
    final String itemKey;
    try {
      itemKey = await e.item.getRegistryKey();
    } catch (_) {
      return BlockUseResult.tryEmptyHand;
    }
    if (itemKey == 'minecraft:slime_ball') {
      if (sticky) return BlockUseResult.tryEmptyHand;
      final state = HostBlockGetter.stateOfId(e.stateIndex);
      if (state['state'] != 'retracted') return BlockUseResult.tryEmptyHand;
      final facing = state.dir('facing') ?? Direction.north;
      if (toDirection(e.face) != facing) return BlockUseResult.tryEmptyHand;
      final pos = (e.pos.x, e.pos.y, e.pos.z);
      final next = BState(stickyMechanicalPistonKey, {
        'facing': facing.serializedName,
        'axis_along_first': state['axis_along_first'] ?? 'true',
        'state': 'retracted',
      });
      await setBlockState(e.targetWorld, pos, next);
      return BlockUseResult.success;
    }
    if (itemKey != 'minecraft:air' && itemKey.isNotEmpty)
      return BlockUseResult.tryEmptyHand;
    final runtime = ActuatorRuntime.maybe;
    final be = _pistonLookup(runtime, e.targetWorld.getId(), e.pos);
    be?.startAssembly();
    return BlockUseResult.success;
  },
  onUseWithoutItem: (server, e) async {
    if (e.sneaking) return BlockUseResult.pass;
    final runtime = ActuatorRuntime.maybe;
    final be = _pistonLookup(runtime, e.targetWorld.getId(), e.pos);
    be?.startAssembly();
    return BlockUseResult.success;
  },
  onNeighborUpdate: (server, e) async {
    // `neighborChanged` schedules a tick; the tick clears a stale assembly exception.
    e.targetWorld.scheduleBlockTick(
      pos: e.pos,
      delayTicks: 1,
      priority: TickPriority.normal,
    );
  },
  onScheduledTick: (server, e) async {
    final runtime = ActuatorRuntime.maybe;
    final be = _pistonLookup(runtime, e.targetWorld.getId(), e.pos);
    be?.clearAssemblyExceptionIfHeadMissing();
  },
  onPlayerWillDestroy: (server, e) async {
    final world = e.targetWorld;
    final pos = (e.pos.x, e.pos.y, e.pos.z);
    final state = HostBlockGetter.stateOfId(e.stateIndex);
    final direction = state.dir('facing') ?? Direction.north;
    final drop = e.player.getGamemode() != GameMode.creative;
    await destroyPistonExtensions(world, pos, direction, drop: drop);
    return true;
  },
);

/// `MechanicalPistonBlock.playerWillDestroy`: break the head (with the poles in front of the
/// base) and the poles behind the base. Also runs when a moving piston is removed
/// (`MechanicalPistonBlockEntity.disassemble` calls it with a `null` player, so everything
/// drops).
Future<void> destroyPistonExtensions(
  World world,
  Pos pos,
  Direction direction, {
  required bool drop,
}) async {
  final maxPoles = ActuatorRuntime.instance.settings.maxPistonPoles;
  final level = HostBlockGetter(world);

  Pos? head;
  for (var offset = 1; offset < maxPoles; offset++) {
    final current = pos.relative(direction, offset);
    final block = level.stateAt(current);
    if (pistonPoleMatchesAxis(block, direction.axis)) continue;
    if (isPistonHead(block) && block.dir('facing') == direction) head = current;
    break;
  }

  if (head != null) {
    for (final p in pos.boxTo(head)) {
      if (p == pos) continue;
      await world.breakBlock(BlockPos(x: p.$1, y: p.$2, z: p.$3), drop: drop);
    }
  }

  for (var offset = 1; offset < maxPoles; offset++) {
    final current = pos.relative(direction.opposite, offset);
    final block = level.stateAt(current);
    if (!pistonPoleMatchesAxis(block, direction.axis)) break;
    await world.breakBlock(
      BlockPos(x: current.$1, y: current.$2, z: current.$3),
      drop: drop,
    );
  }
}

/// `MechanicalPistonHeadBlock.playerWillDestroy`: remove the poles and retract the base.
BlockBehavior pistonHeadBehavior() => BlockBehavior(
  onPlayerWillDestroy: (server, e) async {
    final world = e.targetWorld;
    final pos = (e.pos.x, e.pos.y, e.pos.z);
    final state = HostBlockGetter.stateOfId(e.stateIndex);
    final direction = state.dir('facing') ?? Direction.north;
    final drop = e.player.getGamemode() != GameMode.creative;

    Pos? base;
    for (
      var offset = 1;
      offset < ActuatorRuntime.instance.settings.maxPistonPoles;
      offset++
    ) {
      final current = pos.relative(direction.opposite, offset);
      final block = HostBlockGetter(world).stateAt(current);
      if (pistonPoleMatchesAxis(block, direction.axis)) continue;
      if (isPistonStateKey(block.key) && block.dir('facing') == direction)
        base = current;
      break;
    }

    if (base != null) {
      for (final p in pos.boxTo(base)) {
        if (p == pos || p == base) continue;
        await world.breakBlock(
          BlockPos(x: p.$1, y: p.$2, z: p.$3),
          drop: drop,
        );
      }
      final baseState = HostBlockGetter(world).stateAt(base);
      await setBlockState(
        world,
        base,
        baseState.setValue('state', 'retracted'),
      );
    }
    return true;
  },
);

/// `MechanicalPistonBlock.onWrenched`: only a retracted piston may be rotated.
Wrenchable pistonWrenchable() => CallbackWrenchable(
  onWrenchedOverride: (c) async {
    if (c.properties['state'] != 'retracted') return WrenchResult.pass;
    return c.registry.defaultRotate(c);
  },
);

PistonBlockEntityLookup? _pistonLookup(
  ActuatorRuntime? runtime,
  String worldId,
  BlockPos pos,
) {
  final be = runtime?.store.at(worldId, pos);
  return be is PistonBlockEntityLookup ? be as PistonBlockEntityLookup : null;
}

/// What the piston block behaviour asks of the block entity (avoids a circular import).
abstract interface class PistonBlockEntityLookup {
  void startAssembly();

  void clearAssemblyExceptionIfHeadMissing();
}
