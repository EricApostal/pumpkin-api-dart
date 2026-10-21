// Registration of the track area for the trains module: the `track` and `fake_track` blocks, their
// block entity types, the track block's callbacks and the fake track's random tick.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../common/host_bridge.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/perf.dart';
import '../../core/registry.dart';
import '../station/host_ops.dart' show sendOverlay;
import '../station/station_block_entity.dart';
import '../support/runtime.dart';
import 'fake_track_block.dart';
import 'i_track_block.dart';
import 'track_block.dart';
import 'track_block_item.dart';
import 'track_host.dart';
import 'track_level.dart';
import 'track_material.dart';
import 'track_placement_rules.dart';
import 'track_targeting_block_item.dart';
import 'track_voxel_shapes.dart';

/// Phase 1: the two blocks and their block entity types. The `track` item is registered with the
/// block by the manifest (`blockItem: 'track'`).
void registerTrack(CreateRegistry registry) {
  final track = TrackMaterial.ANDESITE.createBlock();

  registry.block(
    manifestBlock(
      'track',
      blockEntityType: TrackBlockEntityHost.type,
      placement: trackPlacementRules,
      shapeRules: trackShapeRules(),
      behavior: _trackBehavior(track),
    ),
  );
  registry.block(
    manifestBlock(
      'fake_track',
      blockEntityType: FakeTrackBlockEntityHost.type,
      placement: const [PlacementRule.inWater('waterlogged')],
      // `FakeTrackBlock.getShape` is empty (the block has no collision either).
      selectionShape: BlockShape.empty,
      behavior: BlockBehavior(
        onRandomTick: (server, e) async {
          await FakeTrackBlock.randomTick(
            HostTrackLevel(e.targetWorld, Tr.i.store),
            e.pos.toPos(),
          );
        },
      ),
    ),
  );

  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: TrackBlockEntityHost.type,
      validBlocks: TrackMaterial.allBlocks(),
      create: TrackBlockEntityHost.new,
      tickInterval: 1,
    ),
  );
  registry.blockEntityType(
    const BlockEntityTypeSpec(
      key: FakeTrackBlockEntityHost.type,
      validBlocks: [fakeTrackKey],
      create: FakeTrackBlockEntityHost.new,
      tickInterval: 1,
    ),
  );
}

/// The `TrackBlock` callbacks of the host block.
BlockBehavior _trackBehavior(TrackBlock track) => BlockBehavior(
  onPlaced: (server, e) async {
    if (!Perf.enabled) return _onTrackPlaced(track, e);
    final watch = Stopwatch()..start();
    try {
      await _onTrackPlaced(track, e);
    } finally {
      Perf.record('place.track.onPlaced', watch.elapsedMicroseconds);
    }
  },
  onScheduledTick: (server, e) async {
    final level = HostTrackLevel(e.targetWorld, Tr.i.store);
    final pos = e.pos.toPos();
    if (!Perf.enabled) {
      await track.tick(level, pos, level.stateAt(pos));
      return;
    }
    final watch = Stopwatch()..start();
    try {
      await track.tick(level, pos, level.stateAt(pos));
    } finally {
      Perf.record('track.scheduledTick', watch.elapsedMicroseconds);
    }
  },
  onStateReplaced: (server, e) {
    final level = HostTrackLevel(e.targetWorld, Tr.i.store);
    // The position has the replacing block already, so the old state comes from the block's
    // `baseStateId + oldStateIndex` (`docs/block-callbacks.md`).
    track.onRemoved(
      level,
      e.pos.toPos(),
      HostBlockGetter.stateOfIndex(e.block, e.oldStateIndex),
    );
  },
  onPlayerWillDestroy: (server, e) async {
    final level = HostTrackLevel(e.targetWorld, Tr.i.store);
    final pos = e.pos.toPos();
    await track.playerWillDestroy(
      level,
      pos,
      level.stateAt(pos),
      isCreative: e.player.getGamemode() == GameMode.creative,
    );
    return true;
  },
  // `useItemOn`: a click inside a station's assembly area is the station's (bogey creation and
  // size cycling); otherwise the item still gets its use.
  onUseWithItem: (server, e) => _trackUse(track, e),
  // No `updateShape` hook. Java's `TrackBlock.updateShape` (a portal track whose portal is gone
  // becomes air, `track_block.dart` `TrackBlock.updateShape`) is not ported: the scheduled tick
  // repairs a broken portal connection (`connectToPortal`) and drops the track when the other
  // side is gone. Registering the hook for a handler that keeps the state (`null`) bought
  // nothing and cost a host-to-plugin round trip for every shape update of every neighbour of
  // every written track - tens of milliseconds each (see `HostTrackLevel.setBlocks`), which is
  // the tick a track placement used to spike. Wire it up here if the portal case is ever ported.
);

/// `TrackBlock.onPlace` + `setPlacedBy` of one placed track block ([_trackBehavior]'s `onPlaced`).
Future<void> _onTrackPlaced(TrackBlock track, CustomBlockPlacedEventData e) async {
  final level = HostTrackLevel(e.targetWorld, Tr.i.store);
  final pos = e.pos.toPos();
  final old = e.oldStateId == null
      ? BState.air
      : HostBlockGetter.stateOfId(e.oldStateId!);
  await track.onPlace(level, pos, level.stateAt(pos), old);
  await track.setPlacedBy(level, pos);
}

Future<BlockUseResult> _trackUse(
  TrackBlock track,
  CustomBlockUseEventData e,
) async {
  final worldId = Tr.i.worldId(e.targetWorld);
  final areas = StationBlockEntity.assemblyAreas[worldId];
  if (areas == null) return BlockUseResult.tryEmptyHand;

  final pos = e.pos.toPos();
  final state = HostBlockGetter(e.targetWorld).stateAt(pos);
  for (final entry in areas.entries) {
    if (!entry.value.isInside(pos)) continue;
    final station = Tr.i.store.typed<StationBlockEntity>(
      worldId,
      entry.key.toBlockPos(),
    );
    if (station == null) continue;
    if (await station.trackClicked(e.player, e.hand, track, state, pos)) {
      return BlockUseResult.success;
    }
  }
  return BlockUseResult.tryEmptyHand;
}

/// Phase 2: the material deserialisation warning and the track item's `useOn`.
void loadTrack(CreateContext ctx) {
  TrackMaterial.onDeserializeFailure = (name) =>
      ctx.log.warn('Unknown track material `$name`');

  // `TrackBlockItem.useOn`: the host has no item behaviour hook, so the click is taken before
  // the block and the item act on it. The first click on a track stores the curve start in the
  // held stack, the second runs `TrackPlacement.tryConnect`, which places the whole run.
  ctx.host.intercept(Events.itemUseFirst, (server, e) async {
    if (e.useResult != ItemUseFirstResult.pass) return e;
    final result = await useTrackItemOnBlock(e);
    return result == null ? e : e.copyWith(useResult: result);
  });

  // `TrackTargetingBlockItem.useOn`: the station, signal and observer items select a track
  // position and the placed block is pointed at it.
  installTrackTargeting(ctx);

  // `TrackBlockItem.use` in the air: a sneak-click with a stack that is connecting clears the
  // selection (`clearSelection`), otherwise the item is used normally.
  ctx.host.intercept(Events.playerUseItem, (server, e) async {
    if (e.clickedPos != null) return e;
    final String itemKey;
    try {
      itemKey = await e.item.getRegistryKey();
    } on Object {
      return e;
    }
    if (TrackBlockRegistry.of(itemKey) == null) return e;
    final stack = TrackItemStack(
      itemKey,
      1,
      connectingFrom: readConnectingFrom(e.item),
    );
    final entity = e.player.asEntity();
    final bool sneaking;
    try {
      sneaking = entity.isSneaking();
    } finally {
      entity.dispose();
    }
    if (!TrackBlockItem.use(stack, sneaking: sneaking)) return e;
    await clearTrackComponents(e.player, e.hand);
    sendOverlay(
      e.player,
      trackMessage('create.track.selection_cleared'),
    );
    return e.cancel();
  });
}

/// Phase 3: nothing.
void serverTrackLoaded(CreateRuntime runtime) {}

/// Plugin unload.
void unloadTrack() {
  uninstallTrackTargeting();
  TrackMaterial.onDeserializeFailure = null;
  TrackBlockRegistry.clear();
}
