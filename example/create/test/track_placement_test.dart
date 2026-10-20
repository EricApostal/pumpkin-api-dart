// Pure-logic parity of `TrackPlacement`: one use of a track item has to produce the whole run
// between the two clicked ends, not a single block. No host: the level is a map of block states
// (`MemoryTrackLevel`) and the player is a look direction plus an inventory snapshot.
//
// Java sources (branch `port/26.3`):
//   content/trains/track/TrackPlacement.java:210-476   tryConnect: the extents and the curve
//   content/trains/track/TrackPlacement.java:500-588   placeTracks: the blocks of both extents
//   content/trains/track/TrackBlockItem.java:89-137    useOn: select, then tryConnect
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/trains/track/i_track_block.dart';
import 'package:create/src/trains/track/track_block.dart';
import 'package:create/src/trains/track/track_block_item.dart';
import 'package:create/src/trains/track/track_level.dart';
import 'package:create/src/trains/track/track_material.dart';
import 'package:create/src/trains/track/track_placement.dart';
import 'package:create/src/trains/track/track_shape.dart';
import 'package:test/test.dart';

/// `TrackMaterial.ANDESITE.createBlock()`, so `TrackBlockRegistry` knows `create:track`.
TrackBlock registerTrackBlock() => TrackMaterial.ANDESITE.createBlock();

/// A straight track block state with [shape].
BState track(BState base, TrackShape shape) => withTrackShape(base, shape);

/// The player `TrackPlacement` reads: a look direction and a creative inventory.
final class TestPlacementPlayer implements TrackPlacementPlayer {
  TestPlacementPlayer(this.look, {this.creative = true});

  final Vec3 look;
  final bool creative;

  @override
  Vec3 getLookAngle() => look;

  @override
  bool isCreative() => creative;

  @override
  TrackInventory inventory = TrackInventory(const [], 0);

  @override
  void placeItemBackInInventory(String itemKey, int count) {}
}

/// The positions of every track block of [level], sorted.
List<Pos> placedTracks(MemoryTrackLevel level) => [
  for (final entry in level.blocks.entries)
    if (TrackBlockRegistry.isTrack(entry.value)) entry.key,
]..sort((a, b) {
    final byX = a.$1.compareTo(b.$1);
    return byX != 0 ? byX : a.$3.compareTo(b.$3);
  });

void main() {
  late TrackBlock block;
  late BState zo;
  late BState xo;

  setUp(() {
    block = registerTrackBlock();
    zo = track(block.defaultState, TrackShape.zo);
    xo = track(block.defaultState, TrackShape.xo);
  });

  group('select', () {
    test('a click along the track stores the far end as the curve start', () {
      final level = MemoryTrackLevel({(0, 0, 0): zo});
      final stack = TrackItemStack('create:track', 1);

      expect(
        TrackBlockItem.select(level, (0, 0, 0), (0.0, 0.0, 1.0), stack),
        isTrue,
      );

      final from = stack.connectingFrom!;
      expect(from.pos, (0, 0, 0));
      // `getCurveStart`: the block centre, half a block down and half a block along the axis.
      expect(from.axis, (0.0, 0.0, 1.0));
      expect(from.end, (0.5, 0.0, 1.0));
      expect(from.normal, (0.0, 1.0, 0.0));
      expect(TrackBlockItem.isFoil(stack), isTrue);
    });

    test('a click on a block that is no track is not a selection', () {
      final level = MemoryTrackLevel({(0, 0, 0): const BState('minecraft:stone')});
      final stack = TrackItemStack('create:track', 1);
      expect(
        TrackBlockItem.select(level, (0, 0, 0), (0.0, 0.0, 1.0), stack),
        isFalse,
      );
      expect(stack.connectingFrom, isNull);
    });
  });

  group('tryConnect', () {
    test('one use lays the whole straight run, not one block', () async {
      final level = MemoryTrackLevel({(0, 0, 0): zo});
      final stack = TrackItemStack('create:track', 64);
      final player = TestPlacementPlayer((0.0, 0.0, 1.0));

      expect(
        TrackBlockItem.select(level, (0, 0, 0), (0.0, 0.0, 1.0), stack),
        isTrue,
      );

      // The second click: 8 blocks further along the same axis.
      level.blocks[(0, 0, 8)] = zo;
      final info = await TrackPlacement.tryConnect(
        level,
        player,
        (0, 0, 8),
        zo,
        stack,
        false,
        false,
      );

      expect(info.valid, isTrue, reason: info.message);
      expect(info.curve, isNull, reason: 'two ends on one axis connect without a curve');
      // `placeTracks`: `round((distance + 1) / axis.length)` blocks from the first end.
      expect(info.end1Extent, 9);
      expect(info.end2Extent, 0);
      // Both clicked blocks already are tracks: only the seven in between are new (`canPlace`).
      expect(info.requiredTracks, 7);

      final run = placedTracks(level);
      expect(run, [for (var z = 0; z <= 8; z++) (0, 0, z)]);
      for (final pos in run) {
        final state = level.stateAt(pos);
        expect(state.key, 'create:track');
        expect(trackShapeOf(state), TrackShape.zo);
        expect(hasBe(state), isFalse, reason: 'a straight run has no curve');
      }
    });

    test('one use lays a 90 degree turn: both extents and the curve', () async {
      final level = MemoryTrackLevel({(0, 0, 0): zo});
      final stack = TrackItemStack('create:track', 64);

      expect(
        TrackBlockItem.select(level, (0, 0, 0), (0.0, 0.0, 1.0), stack),
        isTrue,
      );

      // The second end: an x track, looked at from -x so its axis points at the first one.
      level.blocks[(9, 0, 8)] = xo;
      final info = await TrackPlacement.tryConnect(
        level,
        TestPlacementPlayer((-1.0, 0.0, 0.0)),
        (9, 0, 8),
        xo,
        stack,
        false,
        false,
      );

      expect(info.valid, isTrue, reason: info.message);
      expect(info.curve, isNotNull, reason: 'a turn is a curve, not a straight run');
      expect(info.end1Extent, 0);
      expect(info.end2Extent, 1);

      // The turn ends: one block at the first end, the two blocks of the second extent.
      expect(placedTracks(level), [(0, 0, 0), (8, 0, 8), (9, 0, 8)]);
      expect(hasBe(level.stateAt((0, 0, 0))), isTrue);
      expect(hasBe(level.stateAt((8, 0, 8))), isTrue);
      expect(hasBe(level.stateAt((9, 0, 8))), isFalse);

      // The curve runs between the two marked blocks.
      expect(info.curve!.bePositions.first, (0, 0, 0));
      expect(info.curve!.bePositions.second, (8, 0, 8));
      expect(info.curve!.getSegmentCount(), greaterThan(0));
      expect(info.requiredTracks, greaterThan(3), reason: 'the curve needs its own tracks');
    });

    test('a second point on the same block is refused', () async {
      final level = MemoryTrackLevel({(0, 0, 0): zo});
      final stack = TrackItemStack('create:track', 64);
      TrackBlockItem.select(level, (0, 0, 0), (0.0, 0.0, 1.0), stack);

      final info = await TrackPlacement.tryConnect(
        level,
        TestPlacementPlayer((0.0, 0.0, 1.0)),
        (0, 0, 0),
        zo,
        stack,
        false,
        false,
      );

      expect(info.valid, isFalse);
      expect(info.message, 'track.second_point');
      expect(placedTracks(level), [(0, 0, 0)]);
    });

    test('a second point beyond maxTrackPlacementLength is refused', () async {
      final level = MemoryTrackLevel({(0, 0, 0): zo});
      final stack = TrackItemStack('create:track', 64);
      TrackBlockItem.select(level, (0, 0, 0), (0.0, 0.0, 1.0), stack);

      level.blocks[(0, 0, 33)] = zo;
      final info = await TrackPlacement.tryConnect(
        level,
        TestPlacementPlayer((0.0, 0.0, 1.0)),
        (0, 0, 33),
        zo,
        stack,
        false,
        false,
      );

      expect(info.valid, isFalse);
      expect(info.message, 'track.too_far');
      expect(info.curve, isNull);
    });

    test('a placement without a selection is refused', () async {
      final level = MemoryTrackLevel({(0, 0, 0): zo});
      final info = await TrackPlacement.tryConnect(
        level,
        TestPlacementPlayer((0.0, 0.0, 1.0)),
        (0, 0, 8),
        zo,
        TrackItemStack('create:track', 64),
        false,
        false,
      );

      expect(info.valid, isFalse);
      expect(info.message, 'track.original_missing');
    });
  });

  group('useOn', () {
    /// A player with [tracks] tracks in the first hotbar slot, not in creative mode.
    TestPlacementPlayer survivalPlayer(Vec3 look, int tracks) {
      final items = List<TrackItemStack?>.filled(36, null);
      items[0] = TrackItemStack('create:track', tracks);
      return TestPlacementPlayer(look, creative: false)
        ..inventory = TrackInventory(items, 0);
    }

    /// The first click of a connection: `useOn` on a track block without a selection.
    Future<TrackUseResult> firstClick(
      MemoryTrackLevel level,
      TrackItemStack stack,
      Vec3 look, {
      Pos at = (0, 0, 0),
      TrackPlacementPlayer? player,
    }) => TrackBlockItem.useOn(
      level: level,
      player: player ?? TestPlacementPlayer(look),
      stack: stack,
      clickedPos: at,
      clickedFace: Direction.up,
      clickedState: level.stateAt(at),
      lookVec: look,
      yRot: 0,
      sneaking: false,
    );

    test('the first click on a track selects it and asks for a second point', () async {
      final level = MemoryTrackLevel({(0, 0, 0): zo});
      final stack = TrackItemStack('create:track', 1);

      final result = await firstClick(level, stack, (0.0, 0.0, 1.0));

      expect(result.outcome, TrackUseOutcome.selected);
      expect(result.handled, isTrue);
      // Java's `select` path shows nothing server side; the client renders the hint itself.
      expect(result.message, isNull);
      expect(stack.connectingFrom, isNotNull);
      expect(placedTracks(level), [(0, 0, 0)], reason: 'selecting places nothing');
    });

    test('a click on a junction refuses to start a connection', () async {
      final level = MemoryTrackLevel({
        (0, 0, 0): track(block.defaultState, TrackShape.crO),
      });
      final stack = TrackItemStack('create:track', 1);

      final result = await firstClick(level, stack, (0.0, 0.0, 1.0));

      expect(result.outcome, TrackUseOutcome.junctionStart);
      expect(result.message, 'create.track.junction_start');
      expect(stack.connectingFrom, isNull);
    });

    test('a click on a non-track block is left to the item', () async {
      final level = MemoryTrackLevel({(0, 0, 0): const BState('minecraft:stone')});
      final stack = TrackItemStack('create:track', 1);

      final result = await firstClick(level, stack, (0.0, 0.0, 1.0));

      expect(result.outcome, TrackUseOutcome.pass);
      expect(result.handled, isFalse, reason: 'super.useOn places the single block');
      expect(stack.connectingFrom, isNull);
    });

    test('sneaking with a selection clears it instead of connecting', () async {
      final level = MemoryTrackLevel({(0, 0, 0): zo});
      final stack = TrackItemStack('create:track', 1);
      await firstClick(level, stack, (0.0, 0.0, 1.0));

      final result = await TrackBlockItem.useOn(
        level: level,
        player: TestPlacementPlayer((0.0, 0.0, 1.0)),
        stack: stack,
        clickedPos: (0, 0, 8),
        clickedFace: Direction.up,
        clickedState: level.stateAt((0, 0, 8)),
        lookVec: (0.0, 0.0, 1.0),
        yRot: 0,
        sneaking: true,
      );

      expect(result.outcome, TrackUseOutcome.selectionCleared);
      expect(result.message, 'create.track.selection_cleared');
      expect(stack.connectingFrom, isNull);
      expect(placedTracks(level), [(0, 0, 0)]);
    });

    test('the second click lays the whole run and clears the selection', () async {
      final level = MemoryTrackLevel({(0, 0, 0): zo});
      final stack = TrackItemStack('create:track', 64);
      await firstClick(level, stack, (0.0, 0.0, 1.0));

      level.blocks[(0, 0, 8)] = zo;
      final result = await TrackBlockItem.useOn(
        level: level,
        player: TestPlacementPlayer((0.0, 0.0, 1.0)),
        stack: stack,
        clickedPos: (0, 0, 8),
        clickedFace: Direction.up,
        clickedState: zo,
        lookVec: (0.0, 0.0, 1.0),
        yRot: 0,
        sneaking: false,
      );

      expect(result.outcome, TrackUseOutcome.placed);
      expect(result.success, isTrue);
      expect(stack.connectingFrom, isNull, reason: 'the next click starts a new connection');
      expect(placedTracks(level), [for (var z = 0; z <= 8; z++) (0, 0, z)]);
    });

    test('click 1 then click 2 on a turn lays a curved track between the positions', () async {
      // The same two clicks the player makes in the world: the first selects the start track,
      // the second clicks the end track 90 degrees away and the curve between them is built.
      final level = MemoryTrackLevel({(0, 0, 0): zo});
      final stack = TrackItemStack('create:track', 64);
      await firstClick(level, stack, (0.0, 0.0, 1.0));
      expect(stack.connectingFrom, isNotNull, reason: 'click 1 stores the pending connection');

      level.blocks[(9, 0, 8)] = xo;
      final result = await TrackBlockItem.useOn(
        level: level,
        player: TestPlacementPlayer((-1.0, 0.0, 0.0)),
        stack: stack,
        clickedPos: (9, 0, 8),
        clickedFace: Direction.up,
        clickedState: xo,
        lookVec: (-1.0, 0.0, 0.0),
        yRot: 0,
        sneaking: false,
      );

      expect(result.outcome, TrackUseOutcome.placed, reason: result.message);
      final curve = result.info!.curve;
      expect(curve, isNotNull, reason: 'the two ends are not on one axis: the run is a curve');
      expect(curve!.bePositions.first, (0, 0, 0));
      expect(curve.bePositions.second, (8, 0, 8));
      // The curve is registered on both ends: the `turn` property is set there and the two
      // blocks are the curve's ends.
      expect(hasBe(level.stateAt((0, 0, 0))), isTrue);
      expect(hasBe(level.stateAt((8, 0, 8))), isTrue);
      expect(placedTracks(level), [(0, 0, 0), (8, 0, 8), (9, 0, 8)]);
      expect(stack.connectingFrom, isNull);
    });

    test('a click next to a non-track block places the run from there', () async {
      final level = MemoryTrackLevel({(0, 0, 0): zo});
      final stack = TrackItemStack('create:track', 64);
      await firstClick(level, stack, (0.0, 0.0, 1.0));

      // An air block is replaceable, so the run ends on the clicked position itself; the shape
      // the item would place is chosen from the look direction (`getStateForPlacement`).
      final result = await TrackBlockItem.useOn(
        level: level,
        player: TestPlacementPlayer((0.0, 0.0, 1.0)),
        stack: stack,
        clickedPos: (0, 0, 8),
        clickedFace: Direction.up,
        clickedState: BState.air,
        lookVec: (0.0, 0.0, 1.0),
        yRot: 0,
        sneaking: false,
      );

      expect(result.outcome, TrackUseOutcome.placed);
      expect(placedTracks(level), [for (var z = 0; z <= 8; z++) (0, 0, z)]);
      expect(trackShapeOf(level.stateAt((0, 0, 8))), TrackShape.zo);
    });

    test('a non-track click that cannot be replaced is placed next to the face', () async {
      final level = MemoryTrackLevel({
        (0, 0, 0): zo,
        (0, 0, 8): const BState('minecraft:stone'),
      });
      final stack = TrackItemStack('create:track', 64);
      await firstClick(level, stack, (0.0, 0.0, 1.0));

      final result = await TrackBlockItem.useOn(
        level: level,
        player: TestPlacementPlayer((0.0, 0.0, 1.0)),
        stack: stack,
        clickedPos: (0, 0, 8),
        clickedFace: Direction.up,
        clickedState: const BState('minecraft:stone'),
        lookVec: (0.0, 0.0, 1.0),
        yRot: 0,
        sneaking: false,
      );

      expect(result.outcome, TrackUseOutcome.placed);
      expect(level.stateAt((0, 0, 8)).key, 'minecraft:stone', reason: 'the clicked block stays');
      expect(trackShapeOf(level.stateAt((0, 1, 8))), TrackShape.zo);
    });

    test('a denied connection keeps the selection for the next click', () async {
      final level = MemoryTrackLevel({(0, 0, 0): zo});
      final stack = TrackItemStack('create:track', 64);
      await firstClick(level, stack, (0.0, 0.0, 1.0));

      // The same block as the first point: `track.second_point`.
      final result = await TrackBlockItem.useOn(
        level: level,
        player: TestPlacementPlayer((0.0, 0.0, 1.0)),
        stack: stack,
        clickedPos: (0, 0, 0),
        clickedFace: Direction.up,
        clickedState: zo,
        lookVec: (0.0, 0.0, 1.0),
        yRot: 0,
        sneaking: false,
      );

      expect(result.outcome, TrackUseOutcome.denied);
      expect(result.message, 'create.track.second_point');
      expect(result.success, isFalse);
      expect(stack.connectingFrom, isNotNull);
    });

    test('a survival placement takes the tracks of the whole run', () async {
      final level = MemoryTrackLevel({(0, 0, 0): zo, (0, 0, 8): zo});
      final stack = TrackItemStack('create:track', 7);
      final player = survivalPlayer((0.0, 0.0, 1.0), 7);
      await firstClick(level, stack, (0.0, 0.0, 1.0), player: player);

      final result = await TrackBlockItem.useOn(
        level: level,
        player: player,
        stack: stack,
        clickedPos: (0, 0, 8),
        clickedFace: Direction.up,
        clickedState: zo,
        lookVec: (0.0, 0.0, 1.0),
        yRot: 0,
        sneaking: false,
      );

      expect(result.outcome, TrackUseOutcome.placed, reason: result.message);
      expect(result.info!.requiredTracks, 7);
      // The seven tracks between the ends come out of the selected slot.
      expect(player.inventory.nonEquipmentItems[0]?.count, 0);
      expect(placedTracks(level), [for (var z = 0; z <= 8; z++) (0, 0, z)]);
    });

    test('a survival placement without enough tracks is refused and places nothing', () async {
      final level = MemoryTrackLevel({(0, 0, 0): zo, (0, 0, 8): zo});
      final stack = TrackItemStack('create:track', 6);
      final player = survivalPlayer((0.0, 0.0, 1.0), 6);
      await firstClick(level, stack, (0.0, 0.0, 1.0), player: player);

      final result = await TrackBlockItem.useOn(
        level: level,
        player: player,
        stack: stack,
        clickedPos: (0, 0, 8),
        clickedFace: Direction.up,
        clickedState: zo,
        lookVec: (0.0, 0.0, 1.0),
        yRot: 0,
        sneaking: false,
      );

      expect(result.outcome, TrackUseOutcome.denied);
      expect(result.message, 'create.track.not_enough_tracks');
      expect(player.inventory.nonEquipmentItems[0]?.count, 6, reason: 'nothing was taken');
      expect(placedTracks(level), [(0, 0, 0), (0, 0, 8)]);
    });

    test('use in the air clears a stuck selection only while sneaking', () {
      final stack = TrackItemStack(
        'create:track',
        1,
        connectingFrom: const ConnectingFrom((0, 0, 0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), (0.5, 0.0, 1.0)),
      );

      expect(TrackBlockItem.use(stack, sneaking: false), isFalse);
      expect(stack.connectingFrom, isNotNull);

      expect(TrackBlockItem.use(stack, sneaking: true), isTrue);
      expect(stack.connectingFrom, isNull);
    });
  });
}
