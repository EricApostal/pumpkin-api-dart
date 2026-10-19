// Behaviours of the steam whistle and its extensions.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../common/host_bridge.dart';
import '../common/pos.dart';
import 'behaviour_support.dart';
import 'block_entities.dart';
import 'runtime.dart';
import 'whistle.dart';





/// Hooks other modules can provide to the whistle (the boiler of the fluid tank it sits on).
abstract interface class WhistleBoilerHooks {
  /// `FluidTankBlock.updateBoilerState(state, level, tankPos)`.
  Future<void> updateBoilerState(World world, Pos tankPos);
}

/// `WhistleBlock.queuePitchUpdate`: asks the whistle at [pos] to recompute its pitch next tick.
void queuePitchUpdate(World world, Pos pos) {
  final level = HostBlockGetter(world);
  if (level.stateAt(pos).key == whistleKey) {
    world.scheduleBlockTick(pos: pos.toBlockPos(), delayTicks: 1, priority: TickPriority.normal);
  }
}

/// `WhistleBlock.incrementSize`: grows the extension stack with a note.
Future<void> incrementWhistleSize(DecorationRuntime rt, World world, Pos pos) async {
  final level = HostBlockGetter(world);
  final ext = rt.blocks[whistleExtensionKey]!;
  final growth = whistleIncrementSize(level, pos, BState(ext.key, ext.definition.defaultState));
  if (growth == null) return;
  await setBlockState(world, growth.pos, growth.state);
  final base = level.stateAt(pos);
  final volume = 1.0;
  // The sound of the whistle's block sound type: a note block xylophone plus the hit sound.
  rt.playSound(world, growth.pos, 'minecraft:block.note_block.xylophone', volume: volume / 4, pitch: growth.pitch);
  rt.playSound(world, growth.pos, rt.hitSoundOf(base.key), volume: volume, pitch: growth.pitch);
}

BlockBehavior whistleBehavior(DecorationRuntime rt) {
  WhistleBoilerHooks? boiler() => rt.ctx.services.find<WhistleBoilerHooks>();

  return BlockBehavior(
    onCanPlace: (server, e) async {
      final world = e.targetWorld;
      final pos = e.pos.toPos();
      final face = e.face;
      final player = rt.playerOf(server, e.player);
      if (face == null || player == null) return e.canPlace;
      final block = rt.blocks[e.block]!;
      final state = whistleStateForPlacement(
        level: HostBlockGetter(world),
        pos: pos,
        defaultState: BState(block.key, block.definition.defaultState),
        clickedFace: dirOf(face),
        horizontalDirection: rt.horizontalDirection(player),
        hasNeighborSignal: false,
      );
      return state != null && e.canPlace;
    },
    onPlaced: (server, e) async {
      final world = e.targetWorld;
      final pos = e.pos.toPos();
      final level = HostBlockGetter(world);
      var state = rt.stateOf(e.block, e.stateIndex);
      if (shouldFixPlacement(rt, e.block, e.oldStateId, e.player, pos)) {
        final player = rt.playerOf(server, e.player);
        final click = rt.clickFor(e.player, pos);
        if (player != null && click != null) {
          final block = rt.blocks[e.block]!;
          final fixed = whistleStateForPlacement(
            level: level,
            pos: pos,
            defaultState: BState(block.key, block.definition.defaultState).setValue('size', state['size'] ?? 'medium'),
            clickedFace: click.face,
            horizontalDirection: rt.horizontalDirection(player),
            hasNeighborSignal: await hasNeighborSignal(world, pos),
          );
          if (fixed == null) {
            scheduleBreak(world, pos);
            return;
          }
          if (fixed != state) {
            await setBlockState(world, pos, fixed);
            state = fixed;
          }
        }
      }
      await boiler()?.updateBoilerState(world, pos.relative(whistleAttachedDirection(state)));
      queuePitchUpdate(world, pos);
    },
    onNeighborUpdate: (server, e) async {
      final world = e.targetWorld;
      final pos = e.pos.toPos();
      final state = rt.stateOf(e.block, e.stateIndex);
      final powered = await hasNeighborSignal(world, pos);
      if (powered != state.flag('powered')) {
        await setBlockState(world, pos, state.cycleFlag('powered'), flags: BlockUpdateFlags.clientsOnly);
      }
    },
    onUpdateShape: (server, e) async {
      final world = e.targetWorld;
      final pos = e.pos.toPos();
      final state = rt.stateOf(e.block, e.stateIndex);
      final next = whistleUpdateShape(HostBlockGetter(world), pos, state, dirOf(e.direction));
      if (next.isAir) scheduleBreak(world, pos);
      return null;
    },
    onScheduledTick: (server, e) async {
      final world = e.targetWorld;
      final pos = e.pos.toPos();
      final level = HostBlockGetter(world);
      final state = level.stateAt(pos);
      if (state.key != e.block) return;
      if (!whistleCanSurvive(level, pos, state)) {
        await breakWithDrops(world, pos);
        return;
      }
      rt.store.typed<WhistleBlockEntity>(world.getId(), e.pos)?.updatePitch();
    },
    onUseWithItem: (server, e) async {
      final held = await e.item.getRegistryKey();
      if (held != whistleKey) return BlockUseResult.tryEmptyHand;
      await incrementWhistleSize(rt, e.targetWorld, e.pos.toPos());
      return BlockUseResult.success;
    },
    onStateReplaced: (server, e) async {
      final old = rt.stateOf(e.block, e.oldStateIndex);
      await boiler()?.updateBoilerState(e.targetWorld, e.pos.toPos().relative(whistleAttachedDirection(old)));
    },
  );
}

BlockBehavior whistleExtenderBehavior(DecorationRuntime rt) => BlockBehavior(
  onUseWithItem: (server, e) async {
    final held = await e.item.getRegistryKey();
    if (held != whistleKey) return BlockUseResult.tryEmptyHand;
    final world = e.targetWorld;
    final root = whistleFindRoot(HostBlockGetter(world), e.pos.toPos());
    if (HostBlockGetter(world).stateAt(root).key != whistleKey) return BlockUseResult.tryEmptyHand;
    await incrementWhistleSize(rt, world, root);
    return BlockUseResult.success;
  },
  onPlaced: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    // `onPlace`: a new extension or a changed shape moves the pitch of the whistle below.
    queuePitchUpdate(world, whistleFindRoot(HostBlockGetter(world), pos));
  },
  onStateReplaced: (server, e) async {
    final world = e.targetWorld;
    queuePitchUpdate(world, whistleFindRoot(HostBlockGetter(world), e.pos.toPos()));
  },
  onUpdateShape: (server, e) async {
    final block = rt.blocks[e.block]!;
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = rt.stateOf(e.block, e.stateIndex);
    final next = whistleExtenderUpdateShape(HostBlockGetter(world), pos, state, dirOf(e.direction));
    if (next.isAir) {
      scheduleBreak(world, pos);
      return null;
    }
    return shapeAnswer(block, state, next);
  },
  onScheduledTick: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final level = HostBlockGetter(world);
    final state = level.stateAt(pos);
    if (state.key == e.block && !whistleExtenderCanSurvive(level, pos, state)) await breakWithDrops(world, pos);
  },
  onCloneItem: (server, e) async => ItemStack.create(registryKey: whistleKey, count: 1),
);
