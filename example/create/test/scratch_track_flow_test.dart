import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/trains/track/i_track_block.dart';
import 'package:create/src/trains/track/track_block.dart';
import 'package:create/src/trains/track/track_block_item.dart';
import 'package:create/src/trains/track/track_level.dart';
import 'package:create/src/trains/track/track_material.dart';
import 'package:create/src/trains/track/track_shape.dart';
import 'package:test/test.dart';

final class P implements TrackPlacementPlayer {
  P(this.look, {this.creative = false});
  final Vec3 look;
  final bool creative;

  @override
  Vec3 getLookAngle() => look;

  @override
  bool isCreative() => creative;

  @override
  TrackInventory inventory = TrackInventory(
    List<TrackItemStack?>.generate(36, (i) => TrackItemStack('create:track', 64)),
    0,
  );

  @override
  void placeItemBackInInventory(String itemKey, int count) {}
}

void main() {
  test('two click flow', () async {
    final block = TrackMaterial.ANDESITE.createBlock();
    final level = MemoryTrackLevel({(0, 0, 0): const BState('minecraft:stone')});
    final player = P((0.0, 0.0, 1.0));
    final stack = player.inventory.nonEquipmentItems[0]!;

    // click 1: top face of the stone at (0,0,0), nothing selected
    var r = await TrackBlockItem.useOn(
      level: level,
      player: player,
      stack: stack,
      clickedPos: (0, 0, 0),
      clickedFace: Direction.up,
      clickedState: level.stateAt((0, 0, 0)),
      lookVec: player.look,
      yRot: 0,
      sneaking: false,
    );
    print('click1: ${r.outcome}');
    final placed = TrackBlockItem.placementState(level, (0, 1, 0), 'create:track', player.look, 0)!;
    level.blocks[(0, 1, 0)] = placed;
    print('placed at 0,1,0: ${placed.props}');

    // click 2: on the track, selects
    r = await TrackBlockItem.useOn(
      level: level,
      player: player,
      stack: stack,
      clickedPos: (0, 1, 0),
      clickedFace: Direction.up,
      clickedState: level.stateAt((0, 1, 0)),
      lookVec: player.look,
      yRot: 0,
      sneaking: false,
    );
    print('click2: ${r.outcome} connectingFrom=${stack.connectingFrom}');

    // click 3: top face of stone at (0,0,8)
    level.blocks[(0, 0, 8)] = const BState('minecraft:stone');
    r = await TrackBlockItem.useOn(
      level: level,
      player: player,
      stack: stack,
      clickedPos: (0, 0, 8),
      clickedFace: Direction.up,
      clickedState: level.stateAt((0, 0, 8)),
      lookVec: player.look,
      yRot: 0,
      sneaking: false,
    );
    print('click3: ${r.outcome} msg=${r.message} info=${r.info?.message}');
    print("blocks: ${level.blocks.keys.toList()}");
    print('required=${r.info?.requiredTracks} e1=${r.info?.end1Extent} e2=${r.info?.end2Extent}');
    for (final e in level.blocks.entries) {
      print('  ${e.key} -> ${e.value.key} ${trackShapeOf(e.value).serializedName}');
    }
  });
}
