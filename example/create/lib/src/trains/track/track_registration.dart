// Registration of the track area for the trains module: the `track` and `fake_track` blocks, their
// block entity types, the track block's callbacks and the fake track's random tick.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart';
import '../../common/host_bridge.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../support/runtime.dart';
import 'fake_track_block.dart';
import 'i_track_block.dart';
import 'track_block.dart';
import 'track_host.dart';
import 'track_material.dart';

/// Phase 1: the two blocks and their block entity types. The `track` item is registered with the
/// block by the manifest (`blockItem: 'track'`).
void registerTrack(CreateRegistry registry) {
  final track = TrackMaterial.ANDESITE.createBlock();

  registry.block(
    manifestBlock(
      'track',
      blockEntityType: TrackBlockEntityHost.type,
      placement: const [PlacementRule.inWater('waterlogged')],
      behavior: _trackBehavior(track),
    ),
  );
  registry.block(
    manifestBlock(
      'fake_track',
      blockEntityType: FakeTrackBlockEntityHost.type,
      placement: const [PlacementRule.inWater('waterlogged')],
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
    final level = HostTrackLevel(e.targetWorld, Tr.i.store);
    final pos = e.pos.toPos();
    final old = e.oldStateId == null
        ? BState.air
        : HostBlockGetter.stateOfId(e.oldStateId!);
    await track.onPlace(level, pos, level.stateAt(pos), old);
    await track.setPlacedBy(level, pos);
  },
  onScheduledTick: (server, e) async {
    final level = HostTrackLevel(e.targetWorld, Tr.i.store);
    final pos = e.pos.toPos();
    await track.tick(level, pos, level.stateAt(pos));
  },
  onStateReplaced: (server, e) {
    final level = HostTrackLevel(e.targetWorld, Tr.i.store);
    track.onRemoved(
      level,
      e.pos.toPos(),
      HostBlockGetter.stateOfId(e.oldStateIndex),
    );
  },
  onPlayerWillDestroy: (server, e) async {
    final level = HostTrackLevel(e.targetWorld, Tr.i.store);
    await track.playerWillDestroy(
      level,
      e.pos.toPos(),
      HostBlockGetter.stateOfId(e.stateIndex),
      isCreative: e.player.getGamemode() == GameMode.creative,
    );
    return true;
  },
  // `updateShape`: a portal track whose portal is gone becomes air. The host keeps the state when
  // the callback returns `null`; the portal connection is repaired on the next scheduled tick.
  onUpdateShape: (server, e) => null,
);

/// Phase 2: the material deserialisation warning.
void loadTrack(CreateContext ctx) {
  TrackMaterial.onDeserializeFailure = (name) =>
      ctx.log.warn('Unknown track material `$name`');
}

/// Phase 3: nothing.
void serverTrackLoaded(CreateRuntime runtime) {}

/// Plugin unload.
void unloadTrack() {
  TrackMaterial.onDeserializeFailure = null;
  TrackBlockRegistry.clear();
}
