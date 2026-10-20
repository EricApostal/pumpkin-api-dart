// The placement state and the shape of the sails, as pure logic: `SailBlock.getStateForPlacement`
// (the player's nearest looking direction, turned around), `SailBlock.PlacementHelper` (a sail
// item continues the row of sails in the plane of the canvas) and `AllShapes.SAIL` /
// `SAIL_FRAME` / `SAIL_FRAME_COLLISION` (the plate and the frame's open border).
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

import 'package:create/src/api/block_state.dart';
import 'package:create/src/api/placement.dart';
import 'package:create/src/common/direction.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/contraptions/bearing/sail.dart';

const white = 'create:white_sail';
const frame = 'create:sail_frame';

MapBlockGetter world([Map<Pos, BState>? blocks]) => MapBlockGetter(blocks: blocks);

BState sail(Direction facing, {String key = white}) =>
    BState(key, {'facing': facing.serializedName});

/// The extent of [box] along [axis] (the plate's thickness when the axis is the facing axis).
double thickness(BlockBox box, Axis axis) => switch (axis) {
  Axis.x => box.maxX - box.minX,
  Axis.y => box.maxY - box.minY,
  Axis.z => box.maxZ - box.minZ,
};

/// Whether [box] covers the whole block along [axis].
bool spans(BlockBox box, Axis axis) => switch (axis) {
  Axis.x => box.minX == 0 && box.maxX == 1,
  Axis.y => box.minY == 0 && box.maxY == 1,
  Axis.z => box.minZ == 0 && box.maxZ == 1,
};

/// `BlockBox` has no value equality, so compare the six coordinates of each box.
void expectBoxes(List<BlockBox> actual, List<BlockBox> expected, {String? reason}) {
  expect(actual, hasLength(expected.length), reason: reason);
  for (var i = 0; i < expected.length; i++) {
    final a = actual[i], e = expected[i];
    expect(
      [a.minX, a.minY, a.minZ, a.maxX, a.maxY, a.maxZ],
      [e.minX, e.minY, e.minZ, e.maxX, e.maxY, e.maxZ],
      reason: '${reason ?? ''} box $i',
    );
  }
}

/// The `facing` the host gives a sail a player looking along [look] places
/// (`state_for_placement`: the registered `looking-direction` rule with `opposite`).
Direction placedFacing(Direction look) {
  final rule = sailPlacement.single;
  expect(rule.property, 'facing');
  expect(
    rule.source,
    PlacementSourceKind.lookingDirection,
    reason: 'the sail follows the look, not the clicked face',
  );
  return rule.opposite ? look.opposite : look;
}

void main() {
  group('sail state selection', () {
    test('the placement rule turns the nearest looking direction around', () {
      // `SailBlock.getStateForPlacement`: `WrenchableDirectionalBlock` puts the nearest looking
      // direction in FACING and the sail inverts it.
      expect(sailPlacement, hasLength(1));
      final rule = sailPlacement.single;
      expect(rule.property, 'facing');
      expect(rule.source, PlacementSourceKind.lookingDirection);
      expect(rule.opposite, isTrue);
    });

    test('a sail faces the player who places it', () {
      // Head-on against a wall: looking north at its south face, the canvas faces south, out of
      // the wall. (`clicked-face` would give north here and place the sail backwards.)
      expect(placedFacing(Direction.north), Direction.south);
      expect(placedFacing(Direction.south), Direction.north);
      expect(placedFacing(Direction.east), Direction.west);
      expect(placedFacing(Direction.west), Direction.east);
      // On the floor looking down, and under a ceiling looking up: the canvas faces the player.
      expect(placedFacing(Direction.down), Direction.up);
      expect(placedFacing(Direction.up), Direction.down);
    });

    test('only the sail and frame items continue a row', () {
      expect(isSailItemKey(white), isTrue);
      expect(isSailItemKey(frame), isTrue);
      // Dyed sails share the white sail item and have no item of their own.
      expect(isSailItemKey('create:red_sail'), isFalse);
      expect(isSailItemKey('minecraft:red_dye'), isFalse);
      expect(isSailItemKey('minecraft:shears'), isFalse);
    });
  });

  group('sail row placement', () {
    test('extends the row to the side closest to the click', () {
      final level = world({(0, 64, 0): sail(Direction.up)});
      final offset = sailPlacementOffset(
        level: level,
        state: sail(Direction.up),
        pos: (0, 64, 0),
        hit: (0.9, 64.5, 0.5),
      );
      expect(offset.isSuccessful, isTrue);
      expect(offset.pos, (1, 64, 0));
      // The new sail keeps the clicked sail's facing.
      expect(offset.transform(const BState(white)), sail(Direction.up));
    });

    test('the host cursor is block-relative; the hit is converted to world coordinates', () {
      // The host reports `e.cursor` as 0..1 inside the clicked block, while Java orders the
      // directions by `BlockHitResult.getLocation()`, an absolute point. A raw cursor lets the
      // block's position dominate the ordering and always picks the same side.
      expect(
        sailHitLocation((3, 64, -2), (0.5, 0.25, 0.5)),
        (3.5, 64.25, -1.5),
      );

      final pos = (1000, 64, -2000);
      final offset = sailPlacementOffset(
        level: world({pos: sail(Direction.up)}),
        state: sail(Direction.up),
        pos: pos,
        hit: sailHitLocation(pos, (0.98, 0.5, 0.5)),
      );
      // A click near the east face grows the row east, wherever the row is in the world.
      expect(offset.pos, (1001, 64, -2000));
    });

    test('the click orders the in-plane neighbours, the closest face first', () {
      // `orderedByDistanceExceptAxis`: each unit vector is compared with the hit relative to the
      // block centre. A sail facing up lies in the x/z plane, so only those four remain.
      List<Direction> order((double, double, double) hit) =>
          orderedByDistanceExceptAxis((0, 64, 0), hit, Axis.y);

      expect(order((0.5, 64.5, 0.02)), [
        Direction.north,
        Direction.west,
        Direction.east,
        Direction.south,
      ]);
      expect(order((0.5, 64.5, 0.98)), [
        Direction.south,
        Direction.west,
        Direction.east,
        Direction.north,
      ]);
      expect(order((0.02, 64.5, 0.5)), [
        Direction.west,
        Direction.north,
        Direction.south,
        Direction.east,
      ]);
      expect(order((0.98, 64.5, 0.5)), [
        Direction.east,
        Direction.north,
        Direction.south,
        Direction.west,
      ]);
      // Dead centre: all four tie, and `Iterate.directions` order (north, south, west, east,
      // the y axis filtered out) decides, like Java's stable sort.
      expect(order((0.5, 64.5, 0.5)), [
        Direction.north,
        Direction.south,
        Direction.west,
        Direction.east,
      ]);
    });

    test('a row extends into air on the far side of the click when the near side is taken', () {
      final level = world({
        (0, 64, 0): sail(Direction.up),
        // The row continues south, the side the player clicked.
        (0, 64, 1): sail(Direction.up),
        (1, 64, 0): const BState('minecraft:stone'),
        (-1, 64, 0): const BState('minecraft:stone'),
      });
      // South is a sail, east and west are stone, so the next closest replaceable neighbour is
      // north, away from the click: the sail is added to the end of the row, not to the face.
      final offset = sailPlacementOffset(
        level: level,
        state: sail(Direction.up),
        pos: (0, 64, 0),
        hit: sailHitLocation((0, 64, 0), (0.5, 0.5, 0.98)),
      );
      expect(offset.pos, (0, 64, -1));
    });

    test('a water cell counts as replaceable, like vanilla water', () {
      // `Blocks.WATER` is registered `.replaceable()`, so `canBeReplaced()` is true there; an
      // air-only test would miss a row that stops at the edge of a pond.
      final level = MapBlockGetter(
        blocks: {
          (0, 64, 0): sail(Direction.up),
          (1, 64, 0): const BState('minecraft:water'),
        },
        water: {(1, 64, 0)},
      );
      final offset = sailPlacementOffset(
        level: level,
        state: sail(Direction.up),
        pos: (0, 64, 0),
        hit: sailHitLocation((0, 64, 0), (0.98, 0.5, 0.5)),
      );
      expect(offset.pos, (1, 64, 0));
    });

    test('never extends along the facing axis', () {
      final level = world({(0, 64, 0): sail(Direction.east)});
      // The click is on the east side, but a sail facing east lies in the y/z plane: the row
      // grows south (the closest of the other four neighbours) instead.
      final offset = sailPlacementOffset(
        level: level,
        state: sail(Direction.east),
        pos: (0, 64, 0),
        hit: (0.5, 64.5, 0.9),
      );
      expect(offset.pos, (0, 64, 1));
      expect(offset.transform(const BState(white)), sail(Direction.east));
    });

    test('takes the next replaceable neighbour and fails when none is', () {
      final level = world({
        (0, 64, 0): sail(Direction.up),
        (1, 64, 0): const BState('minecraft:stone'),
      });
      final offset = sailPlacementOffset(
        level: level,
        state: sail(Direction.up),
        pos: (0, 64, 0),
        hit: (0.9, 64.5, 0.5),
      );
      expect(offset.isSuccessful, isTrue);
      expect(offset.pos, (0, 64, -1));

      // Every neighbour in the canvas plane is taken.
      final blocked = world({
        (0, 64, 0): sail(Direction.up),
        (1, 64, 0): const BState('minecraft:stone'),
        (-1, 64, 0): const BState('minecraft:stone'),
        (0, 64, 1): const BState('minecraft:stone'),
        (0, 64, -1): const BState('minecraft:stone'),
      });
      expect(
        sailPlacementOffset(
          level: blocked,
          state: sail(Direction.up),
          pos: (0, 64, 0),
          hit: (0.9, 64.5, 0.5),
        ).isSuccessful,
        isFalse,
      );
    });

    test('a state without a facing property counts as north', () {
      final offset = sailPlacementOffset(
        level: world(),
        state: const BState(white),
        pos: (0, 64, 0),
        hit: (0.5, 64.9, 0.5),
      );
      // The z axis is excluded, so the closest neighbour is the one above.
      expect(offset.pos, (0, 65, 0));
      expect(
        offset.transform(const BState(white)),
        const BState(white, {'facing': 'north'}),
      );
    });

    test('the row grows in the plane of the canvas for every facing', () {
      // The clicked sail, the click point and the expected neighbour: the facing axis is always
      // excluded, so a row only ever grows inside the canvas.
      final cases = <(Direction, (double, double, double), Pos)>[
        (Direction.up, (0.5, 64.5, 0.9), (0, 64, 1)),
        (Direction.down, (0.5, 64.5, 0.9), (0, 64, 1)),
        (Direction.north, (0.9, 64.5, 0.5), (1, 64, 0)),
        (Direction.south, (0.9, 64.5, 0.5), (1, 64, 0)),
        (Direction.east, (0.5, 64.9, 0.5), (0, 65, 0)),
        (Direction.west, (0.5, 64.1, 0.5), (0, 63, 0)),
      ];
      for (final (facing, hit, expected) in cases) {
        final offset = sailPlacementOffset(
          level: world({(0, 64, 0): sail(facing)}),
          state: sail(facing),
          pos: (0, 64, 0),
          hit: hit,
        );
        expect(offset.pos, expected, reason: 'row of a $facing sail');
        expect(
          offset.transform(const BState(white)),
          sail(facing),
          reason: 'the new sail keeps the clicked $facing sail\'s facing',
        );
      }
    });

    test('the facing axis is never chosen, even when the click is on it', () {
      // Facing up and clicking the top face: the four in-plane neighbours all tie at the same
      // distance, so the first of `Iterate.directions` (north) wins; the block above is ignored.
      final offset = sailPlacementOffset(
        level: world({(0, 64, 0): sail(Direction.up)}),
        state: sail(Direction.up),
        pos: (0, 64, 0),
        hit: (0.5, 64.9, 0.5),
      );
      expect(offset.pos, (0, 64, -1));
    });

    test('the item default does not override the clicked facing', () {
      // `PlacementOffset.success(..., s -> s.setValue(FACING, clicked))`: the transform sets the
      // property even when the item's state already carries another value.
      final offset = sailPlacementOffset(
        level: world({(0, 64, 0): sail(Direction.east)}),
        state: sail(Direction.east),
        pos: (0, 64, 0),
        hit: (0.5, 64.9, 0.5),
      );
      expect(
        offset.transform(const BState(white, {'facing': 'north'})),
        sail(Direction.east),
      );
    });
  });

  group('sail row placement from a click', () {
    // `sailBlockBehavior` calls `sailRowPlacement`, the `useItemOn` branch: the clicked sail's
    // state comes from the world (`useItemOn`'s `state` argument). The event's `stateIndex` is
    // the index of the state within the block (`docs/block-callbacks.md`), not a state id, so a
    // sail's `0..5` resolved as an id is a vanilla state with no `facing`: the row then grows as
    // if the sail faced north and the new sail is placed facing north.
    const pos = (0, 64, 0);

    test('an up-facing row grows inside the canvas and keeps the facing', () {
      // The canvas of an up sail is the plate y in [5/16, 10/16]; the click lands on its top
      // surface (cursor y = 5/16), on the south half. The row is the x/z plane, so the next
      // sail goes south, not down out of the canvas.
      final offset = sailRowPlacement(
        level: world({pos: sail(Direction.up)}),
        pos: pos,
        cursor: (0.5, 5 / 16, 0.9),
      );
      expect(offset.pos, (0, 64, 1));
      expect(offset.transform(const BState(white)), sail(Direction.up));
    });

    test('the clicked sail decides the plane and the facing for every facing', () {
      // Each case is a click on the canvas surface, towards one in-plane neighbour: the plate's
      // thickness axis is the facing axis, so the cursor component on it is the surface.
      final cases = <(Direction, (double, double, double), Pos)>[
        (Direction.up, (0.1, 5 / 16, 0.5), (-1, 64, 0)),
        (Direction.up, (0.5, 5 / 16, 0.9), (0, 64, 1)),
        (Direction.down, (0.1, 6 / 16, 0.5), (-1, 64, 0)),
        (Direction.down, (0.5, 6 / 16, 0.1), (0, 64, -1)),
        (Direction.north, (0.9, 0.5, 5 / 16), (1, 64, 0)),
        (Direction.north, (0.5, 0.9, 5 / 16), (0, 65, 0)),
        (Direction.south, (0.9, 0.5, 5 / 16), (1, 64, 0)),
        (Direction.south, (0.5, 0.1, 5 / 16), (0, 63, 0)),
        (Direction.east, (5 / 16, 0.5, 0.9), (0, 64, 1)),
        (Direction.east, (5 / 16, 0.9, 0.5), (0, 65, 0)),
        (Direction.west, (6 / 16, 0.5, 0.9), (0, 64, 1)),
        (Direction.west, (6 / 16, 0.1, 0.5), (0, 63, 0)),
      ];
      for (final (facing, cursor, expected) in cases) {
        final offset = sailRowPlacement(
          level: world({pos: sail(facing)}),
          pos: pos,
          cursor: cursor,
        );
        expect(offset.pos, expected, reason: '$facing row, cursor $cursor');
        expect(
          offset.transform(const BState(white)),
          sail(facing),
          reason: 'the new sail keeps the clicked $facing sail\'s facing',
        );
      }
    });

    test('the click is world-relative, not the raw cursor', () {
      // The host reports the cursor inside the clicked block; the helpers compare it with the
      // block centre, so the row follows the click wherever the sail is in the world.
      const far = (1000, 64, -2000);
      final offset = sailRowPlacement(
        level: world({far: sail(Direction.up)}),
        pos: far,
        cursor: (0.98, 5 / 16, 0.5),
      );
      expect(offset.pos, (1001, 64, -2000));
      expect(offset.transform(const BState(white)), sail(Direction.up));
    });
  });

  group('sail keys and dyes', () {
    test('the frame, the white sail and the sixteen dyed sails are sail blocks', () {
      expect(isSailKey(frame), isTrue);
      expect(isSailKey(white), isTrue);
      for (final color in sailColors) {
        expect(isSailKey(dyedSail(color)), isTrue, reason: color);
      }
      expect(isSailKey('create:sail'), isFalse);
      expect(isSailKey('minecraft:white_wool'), isFalse);
    });

    test('a dyed sail knows its colour, the frame and the white sail do not', () {
      expect(sailColor('create:red_sail'), 'red');
      expect(sailColor('create:light_blue_sail'), 'light_blue');
      // `AllBlocks.SAIL` is `DYED_SAILS.get(DyeColor.WHITE)`, so the white canvas is white.
      expect(sailColor(white), 'white');
      expect(sailColor(frame), isNull);
    });

    test('only the sixteen vanilla dye items name a colour', () {
      for (final color in sailColors) {
        expect(dyeColorOfItem('minecraft:${color}_dye'), color);
      }
      expect(dyeColorOfItem('minecraft:bone_meal'), isNull);
      expect(dyeColorOfItem('create:red_dye'), isNull);
      expect(dyeColorOfItem('minecraft:red_dye_sack'), isNull);
    });
  });

  group('sail shapes', () {
    // `AllShapes.SAIL = shape(0, 5, 0, 16, 10, 16).forDirectional()` and
    // `SAIL_FRAME = shape(0, 5, 0, 16, 9, 16).forDirectional()`: the authored box faces up and
    // `VoxelShaper` rotates it about the block centre. The plate is not symmetric about the
    // centre, so the two sides of an axis differ by one pixel (`up` 5..10 vs `down` 6..11).
    test('the canvas is a five-pixel plate perpendicular to the facing', () {
      expectBoxes(sailCanvasBoxes(Direction.up), [
        const BlockBox(0, 5 / 16, 0, 1, 10 / 16, 1),
      ]);
      expectBoxes(sailCanvasBoxes(Direction.down), [
        const BlockBox(0, 6 / 16, 0, 1, 11 / 16, 1),
      ]);
      expectBoxes(sailCanvasBoxes(Direction.north), [
        const BlockBox(0, 0, 5 / 16, 1, 1, 10 / 16),
      ]);
      expectBoxes(sailCanvasBoxes(Direction.south), [
        const BlockBox(0, 0, 5 / 16, 1, 1, 10 / 16),
      ]);
      expectBoxes(sailCanvasBoxes(Direction.east), [
        const BlockBox(5 / 16, 0, 0, 10 / 16, 1, 1),
      ]);
      expectBoxes(sailCanvasBoxes(Direction.west), [
        const BlockBox(6 / 16, 0, 0, 11 / 16, 1, 1),
      ]);
    });

    test('the frame plate is one pixel thinner than the canvas', () {
      expectBoxes(sailFrameBoxes(Direction.up), [
        const BlockBox(0, 5 / 16, 0, 1, 9 / 16, 1),
      ]);
      expectBoxes(sailFrameBoxes(Direction.down), [
        const BlockBox(0, 7 / 16, 0, 1, 11 / 16, 1),
      ]);
      expectBoxes(sailFrameBoxes(Direction.north), [
        const BlockBox(0, 0, 5 / 16, 1, 1, 9 / 16),
      ]);
      expectBoxes(sailFrameBoxes(Direction.south), [
        const BlockBox(0, 0, 5 / 16, 1, 1, 9 / 16),
      ]);
      expectBoxes(sailFrameBoxes(Direction.east), [
        const BlockBox(5 / 16, 0, 0, 9 / 16, 1, 1),
      ]);
      expectBoxes(sailFrameBoxes(Direction.west), [
        const BlockBox(7 / 16, 0, 0, 11 / 16, 1, 1),
      ]);
    });

    test('the frame collision is the open border, the canvas collision is solid', () {
      // `SAIL_FRAME_COLLISION = shape(0, 5, 0, 16, 9, 16).erase(2, 0, 2, 14, 16, 14)`: the plate
      // minus its middle, so four two-pixel bars remain.
      expectBoxes(sailFrameCollisionBoxes(Direction.up), [
        const BlockBox(0, 5 / 16, 0, 1, 9 / 16, 2 / 16),
        const BlockBox(0, 5 / 16, 14 / 16, 1, 9 / 16, 1),
        const BlockBox(0, 5 / 16, 2 / 16, 2 / 16, 9 / 16, 14 / 16),
        const BlockBox(14 / 16, 5 / 16, 2 / 16, 1, 9 / 16, 14 / 16),
      ]);
      expectBoxes(sailFrameCollisionBoxes(Direction.north), [
        const BlockBox(0, 14 / 16, 5 / 16, 1, 1, 9 / 16),
        const BlockBox(0, 0, 5 / 16, 1, 2 / 16, 9 / 16),
        const BlockBox(14 / 16, 2 / 16, 5 / 16, 1, 14 / 16, 9 / 16),
        const BlockBox(0, 2 / 16, 5 / 16, 2 / 16, 14 / 16, 9 / 16),
      ]);
      expectBoxes(sailFrameCollisionBoxes(Direction.east), [
        const BlockBox(5 / 16, 14 / 16, 0, 9 / 16, 1, 1),
        const BlockBox(5 / 16, 0, 0, 9 / 16, 2 / 16, 1),
        const BlockBox(5 / 16, 2 / 16, 14 / 16, 9 / 16, 14 / 16, 1),
        const BlockBox(5 / 16, 2 / 16, 0, 9 / 16, 14 / 16, 2 / 16),
      ]);
      // Every canvas state is solid in the plane of its facing, so a canvas can be walked on.
      for (final facing in Direction.values) {
        expect(sailCanvasBoxes(facing), hasLength(1));
      }
    });

    test('every plate spans the block in its plane and is thin along the facing', () {
      for (final facing in Direction.values) {
        for (final (boxes, thick) in [
          (sailCanvasBoxes(facing), 5 / 16),
          (sailFrameBoxes(facing), 4 / 16),
        ]) {
          final box = boxes.single;
          expect(thickness(box, facing.axis), thick, reason: '$facing');
          for (final other in facing.axis.others) {
            expect(spans(box, other), isTrue, reason: '$facing along $other');
          }
        }
      }
    });

    test('the frame border is open in the middle', () {
      for (final facing in Direction.values) {
        final ring = sailFrameCollisionBoxes(facing);
        expect(ring, hasLength(4), reason: '$facing');
        // The centre of the block is not inside any bar.
        final centre = 8 / 16;
        final coversCentre = ring.any(
          (b) =>
              b.minX <= centre &&
              b.maxX >= centre &&
              b.minY <= centre &&
              b.maxY >= centre &&
              b.minZ <= centre &&
              b.maxZ >= centre,
        );
        expect(coversCentre, isFalse, reason: '$facing');
      }
    });
  });
}
