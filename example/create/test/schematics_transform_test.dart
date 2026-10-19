// The rotation/mirror matrix of the schematic placement: `BlockState.rotate`/`mirror` for the
// vanilla conventions and Create's overrides, `StructureTemplate.transform` for positions and
// entity vectors, and the bounds the printer walks.
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/binary_nbt.dart';
import 'package:create/src/common/bounds.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/schematics/item_requirement.dart';
import 'package:create/src/schematics/nbt_processors.dart';
import 'package:create/src/schematics/schematic_printer.dart';
import 'package:create/src/schematics/schematic_world.dart';
import 'package:create/src/schematics/state_transform.dart';
import 'package:test/test.dart';

const _rotations = BlockRotation.values;
const _mirrors = BlockMirror.values;

void main() {
  group('rotate matrix', () {
    test('horizontal facing turns clockwise around Y', () {
      const north = BState('minecraft:furnace', {'facing': 'north'});
      expect(rotateState(north, BlockRotation.clockwise90)['facing'], 'east');
      expect(rotateState(north, BlockRotation.clockwise180)['facing'], 'south');
      expect(
        rotateState(north, BlockRotation.counterclockwise90)['facing'],
        'west',
      );
      expect(rotateState(north, BlockRotation.none)['facing'], 'north');
      // Four quarter turns are the identity.
      var s = north;
      for (var i = 0; i < 4; i++) {
        s = rotateState(s, BlockRotation.clockwise90);
      }
      expect(s, north);
      // Counter-clockwise undoes clockwise.
      expect(
        rotateState(
          rotateState(north, BlockRotation.clockwise90),
          BlockRotation.counterclockwise90,
        ),
        north,
      );
    });

    test('vertical facing is unchanged by every rotation', () {
      for (final r in _rotations) {
        expect(
          rotateState(
            const BState('minecraft:dispenser', {'facing': 'up'}),
            r,
          )['facing'],
          'up',
        );
        expect(
          rotateState(
            const BState('minecraft:dispenser', {'facing': 'down'}),
            r,
          )['facing'],
          'down',
        );
      }
    });

    test('axis only swaps on a quarter turn', () {
      const x = BState('minecraft:oak_log', {'axis': 'x'});
      const z = BState('minecraft:oak_log', {'axis': 'z'});
      const y = BState('minecraft:oak_log', {'axis': 'y'});
      expect(rotateState(x, BlockRotation.clockwise90)['axis'], 'z');
      expect(rotateState(z, BlockRotation.clockwise90)['axis'], 'x');
      expect(rotateState(x, BlockRotation.counterclockwise90)['axis'], 'z');
      expect(rotateState(x, BlockRotation.clockwise180)['axis'], 'x');
      expect(rotateState(y, BlockRotation.clockwise90)['axis'], 'y');
    });

    test('16-step rotation adds a quarter, a half or three quarters', () {
      const sign = BState('minecraft:oak_sign', {'rotation': '0'});
      expect(rotateState(sign, BlockRotation.clockwise90)['rotation'], '4');
      expect(rotateState(sign, BlockRotation.clockwise180)['rotation'], '8');
      expect(
        rotateState(sign, BlockRotation.counterclockwise90)['rotation'],
        '12',
      );
      // Wraps.
      expect(
        rotateState(
          const BState('minecraft:oak_sign', {'rotation': '15'}),
          BlockRotation.clockwise90,
        )['rotation'],
        '3',
      );
    });

    test('side booleans move with the sides', () {
      const fence = BState('minecraft:oak_fence', {
        'north': 'true',
        'east': 'false',
        'south': 'false',
        'west': 'false',
      });
      expect(rotateState(fence, BlockRotation.clockwise90)['east'], 'true');
      expect(rotateState(fence, BlockRotation.clockwise90)['north'], 'false');
      expect(
        rotateState(fence, BlockRotation.counterclockwise90)['west'],
        'true',
      );
      expect(rotateState(fence, BlockRotation.clockwise180)['south'], 'true');
      expect(
        mirrorState(fence, BlockMirror.leftRight)['south'],
        'true',
      );
      expect(mirrorState(fence, BlockMirror.frontBack)['north'], 'true');
      expect(mirrorState(fence, BlockMirror.frontBack)['east'], 'false');
    });

    test('rails rotate and mirror their shape', () {
      String rot(String shape, BlockRotation r) => rotateState(
        BState('minecraft:rail', {'shape': shape}),
        r,
      )['shape']!;
      String mir(String shape, BlockMirror m) => mirrorState(
        BState('minecraft:rail', {'shape': shape}),
        m,
      )['shape']!;

      expect(rot('north_south', BlockRotation.clockwise90), 'east_west');
      expect(rot('east_west', BlockRotation.clockwise90), 'north_south');
      expect(
        rot('ascending_north', BlockRotation.clockwise90),
        'ascending_east',
      );
      expect(
        rot('ascending_east', BlockRotation.counterclockwise90),
        'ascending_north',
      );
      expect(rot('south_east', BlockRotation.clockwise180), 'north_west');
      expect(rot('south_east', BlockRotation.clockwise90), 'south_west');
      expect(mir('south_east', BlockMirror.leftRight), 'north_east');
      expect(mir('south_east', BlockMirror.frontBack), 'south_west');
      expect(mir('north_south', BlockMirror.leftRight), 'north_south');
      expect(mir('ascending_north', BlockMirror.leftRight), 'ascending_south');
      expect(mir('ascending_north', BlockMirror.frontBack), 'ascending_north');
      // Rotating four times is the identity for every shape.
      for (final shape in const [
        'north_south',
        'east_west',
        'ascending_east',
        'ascending_west',
        'ascending_north',
        'ascending_south',
        'south_east',
        'south_west',
        'north_west',
        'north_east',
      ]) {
        var s = shape;
        for (var i = 0; i < 4; i++) {
          s = rot(s, BlockRotation.clockwise90);
        }
        expect(s, shape);
        expect(mir(mir(shape, BlockMirror.leftRight), BlockMirror.leftRight), shape);
        expect(mir(mir(shape, BlockMirror.frontBack), BlockMirror.frontBack), shape);
      }
    });

    test('stairs mirror their corners per axis', () {
      const stairs = BState('minecraft:oak_stairs', {
        'facing': 'north',
        'half': 'bottom',
        'shape': 'inner_left',
      });
      // LEFT_RIGHT on a Z-facing stair turns the whole block and swaps the corner.
      final lr = mirrorState(stairs, BlockMirror.leftRight);
      expect(lr['facing'], 'south');
      expect(lr['shape'], 'inner_right');
      // FRONT_BACK does not touch a Z-facing stair at all.
      expect(mirrorState(stairs, BlockMirror.frontBack), stairs);
      // A X-facing stair: FRONT_BACK turns it, but inner corners are symmetric along X.
      const eastInner = BState('minecraft:oak_stairs', {
        'facing': 'east',
        'half': 'bottom',
        'shape': 'inner_left',
      });
      final fbInner = mirrorState(eastInner, BlockMirror.frontBack);
      expect(fbInner['facing'], 'west');
      expect(fbInner['shape'], 'inner_left');
      const eastOuter = BState('minecraft:oak_stairs', {
        'facing': 'east',
        'half': 'bottom',
        'shape': 'outer_left',
      });
      final fbOuter = mirrorState(eastOuter, BlockMirror.frontBack);
      expect(fbOuter['facing'], 'west');
      expect(fbOuter['shape'], 'outer_right');
      // LEFT_RIGHT leaves a X-facing stair alone.
      expect(mirrorState(eastOuter, BlockMirror.leftRight), eastOuter);
      // A straight stair turns without a shape change.
      const straight = BState('minecraft:oak_stairs', {
        'facing': 'north',
        'half': 'bottom',
        'shape': 'straight',
      });
      final lrStraight = mirrorState(straight, BlockMirror.leftRight);
      expect(lrStraight['facing'], 'south');
      expect(lrStraight['shape'], 'straight');
    });

    test('doors swap their hinge only when mirrored across their axis', () {
      const door = BState('minecraft:oak_door', {
        'facing': 'east',
        'hinge': 'left',
        'half': 'lower',
      });
      final fb = mirrorState(door, BlockMirror.frontBack);
      expect(fb['facing'], 'west');
      expect(fb['hinge'], 'right');
      // EAST is on the X axis: LEFT_RIGHT (invert Z) leaves the facing, but `DoorBlock.mirror`
      // swaps the hinge for every mirror.
      final lrDoor = mirrorState(door, BlockMirror.leftRight);
      expect(lrDoor['facing'], 'east');
      expect(lrDoor['hinge'], 'right');
    });

    test('chests swap their half on any mirror', () {
      const chest = BState('minecraft:chest', {
        'facing': 'north',
        'type': 'left',
      });
      for (final m in const [BlockMirror.leftRight, BlockMirror.frontBack]) {
        expect(mirrorState(chest, m)['type'], 'right');
      }
      expect(
        mirrorState(
          const BState('minecraft:chest', {'facing': 'north', 'type': 'single'}),
          BlockMirror.leftRight,
        )['type'],
        'single',
      );
    });

    test('crafter/jigsaw orientation mirrors both the front and the top', () {
      const northUp = BState('minecraft:crafter', {'orientation': 'north_up'});
      expect(
        rotateState(northUp, BlockRotation.clockwise90)['orientation'],
        'east_up',
      );
      expect(
        mirrorState(northUp, BlockMirror.leftRight)['orientation'],
        'south_up',
      );
      expect(
        mirrorState(northUp, BlockMirror.frontBack)['orientation'],
        'north_up',
      );
      // A vertical front: only the horizontal top turns.
      const downEast = BState('minecraft:jigsaw', {'orientation': 'down_east'});
      expect(
        rotateState(downEast, BlockRotation.clockwise90)['orientation'],
        'down_south',
      );
      // LEFT_RIGHT inverts Z: EAST lies on X and stays.
      expect(
        mirrorState(downEast, BlockMirror.leftRight)['orientation'],
        'down_east',
      );
      // FRONT_BACK inverts X: east -> west.
      expect(
        mirrorState(downEast, BlockMirror.frontBack)['orientation'],
        'down_west',
      );
    });

    test('axis_along_first flips on every quarter turn', () {
      const deployer = BState('create:deployer', {
        'facing': 'north',
        'axis_along_first': 'true',
      });
      final cw = rotateState(deployer, BlockRotation.clockwise90);
      expect(cw['facing'], 'east');
      expect(cw['axis_along_first'], 'false');
      final ccw = rotateState(deployer, BlockRotation.counterclockwise90);
      expect(ccw['facing'], 'west');
      expect(ccw['axis_along_first'], 'false');
      final half = rotateState(deployer, BlockRotation.clockwise180);
      expect(half['facing'], 'south');
      expect(half['axis_along_first'], 'true');
      // A FRONT_BACK mirror does not turn a Z-facing block, so the flag stays.
      expect(
        mirrorState(deployer, BlockMirror.frontBack)['axis_along_first'],
        'true',
      );
      // LEFT_RIGHT turns it 180 degrees; only *odd* quarter turns flip the flag, so it stays.
      expect(
        mirrorState(deployer, BlockMirror.leftRight)['axis_along_first'],
        'true',
      );
    });

    test('a vertical belt keeps its ends when the facing does not turn', () {
      const belt = BState('create:belt', {
        'facing': 'up',
        'slope': 'vertical',
        'part': 'start',
      });
      for (final r in _rotations) {
        expect(rotateState(belt, r)['part'], 'start');
      }
      // Horizontal belts rotate their facing like any horizontal block.
      const horizontal = BState('create:belt', {
        'facing': 'east',
        'slope': 'horizontal',
        'part': 'start',
      });
      expect(
        rotateState(horizontal, BlockRotation.clockwise90)['facing'],
        'south',
      );
    });

    test('track shapes use TrackShape.rotate/mirror', () {
      String rot(String shape, BlockRotation r) => rotateState(
        BState('create:track', {'shape': shape}),
        r,
      )['shape']!;
      String mir(String shape, BlockMirror m) => mirrorState(
        BState('create:track', {'shape': shape}),
        m,
      )['shape']!;

      expect(rot('xo', BlockRotation.clockwise90), 'zo');
      expect(rot('zo', BlockRotation.clockwise90), 'xo');
      expect(rot('pd', BlockRotation.clockwise90), 'nd');
      expect(rot('an', BlockRotation.clockwise90), 'ae');
      expect(rot('ae', BlockRotation.clockwise90), 'as');
      expect(rot('as', BlockRotation.clockwise90), 'aw');
      expect(rot('aw', BlockRotation.clockwise90), 'an');
      expect(rot('cr_pdx', BlockRotation.clockwise90), 'cr_ndz');
      expect(rot('pd', BlockRotation.clockwise180), 'pd');
      expect(mir('pd', BlockMirror.leftRight), 'nd');
      expect(mir('an', BlockMirror.leftRight), 'as');
      expect(mir('ae', BlockMirror.leftRight), 'ae');
      expect(mir('ae', BlockMirror.frontBack), 'aw');
      expect(mir('cr_pdx', BlockMirror.leftRight), 'cr_ndx');
      // Four quarter turns return the shape.
      for (final shape in const [
        'zo',
        'xo',
        'pd',
        'nd',
        'an',
        'as',
        'ae',
        'aw',
        'cr_o',
        'cr_d',
        'cr_pdx',
        'cr_ndx',
        'cr_pdz',
        'cr_ndz',
      ]) {
        var s = shape;
        for (var i = 0; i < 4; i++) {
          s = rot(s, BlockRotation.clockwise90);
        }
        expect(s, shape);
      }
    });

    test('mirror then rotate is the placement order', () {
      const furnace = BState('minecraft:furnace', {'facing': 'north'});
      expect(
        transformState(
          furnace,
          BlockMirror.leftRight,
          BlockRotation.clockwise90,
        )['facing'],
        'west',
      );
      // The same as mirroring first and rotating the result.
      expect(
        transformState(furnace, BlockMirror.none, BlockRotation.none),
        furnace,
      );
      // Every combination is a bijection: rotating back and mirroring back restores the state.
      for (final m in _mirrors) {
        for (final r in _rotations) {
          final t = transformState(furnace, m, r);
          // Undo the rotation first, then the mirror.
          final back = mirrorState(
            rotateState(t, BlockRotation.values[(4 - r.index) % 4]),
            m,
          );
          expect(back, furnace);
        }
      }
    });
  });

  group('position transform', () {
    test('transformPos matches StructureTemplate.transform', () {
      const p = (2, 5, 3);
      // CW90: (x, z) -> (-z, x)
      expect(transformPos(p, BlockMirror.none, BlockRotation.clockwise90, posZero), (-3, 5, 2));
      // CCW90: (x, z) -> (z, -x)
      expect(
        transformPos(p, BlockMirror.none, BlockRotation.counterclockwise90, posZero),
        (3, 5, -2),
      );
      expect(transformPos(p, BlockMirror.none, BlockRotation.clockwise180, posZero), (-2, 5, -3));
      // LEFT_RIGHT inverts Z first.
      expect(transformPos(p, BlockMirror.leftRight, BlockRotation.none, posZero), (2, 5, -3));
      expect(
        transformPos(p, BlockMirror.leftRight, BlockRotation.clockwise90, posZero),
        (3, 5, 2),
      );
      // FRONT_BACK inverts X first.
      expect(transformPos(p, BlockMirror.frontBack, BlockRotation.none, posZero), (-2, 5, 3));
      expect(
        transformPos(p, BlockMirror.frontBack, BlockRotation.clockwise90, posZero),
        (-3, 5, -2),
      );
      // A pivot other than the origin offsets the result (the schematic pivot is always zero).
      expect(transformPos(p, BlockMirror.none, BlockRotation.clockwise180, (4, 0, 6)), (6, 5, 9));
    });

    test('transformVec mirrors around the block edge', () {
      const v = (0.25, 2.0, 0.75);
      // A left-right mirror maps x -> 1 - x.
      final lr = transformVec(v, BlockMirror.leftRight, BlockRotation.none, posZero);
      expect(lr.$1, closeTo(0.25, 1e-9));
      expect(lr.$3, closeTo(0.25, 1e-9));
      final fb = transformVec(v, BlockMirror.frontBack, BlockRotation.none, posZero);
      expect(fb.$1, closeTo(0.75, 1e-9));
      expect(fb.$3, closeTo(0.75, 1e-9));
      final cw = transformVec(v, BlockMirror.none, BlockRotation.clockwise90, posZero);
      expect(cw.$1, closeTo(1.0 - 0.75, 1e-9));
      expect(cw.$3, closeTo(0.25, 1e-9));
      final ccw = transformVec(v, BlockMirror.none, BlockRotation.counterclockwise90, posZero);
      expect(ccw.$1, closeTo(0.75, 1e-9));
      expect(ccw.$3, closeTo(1.0 - 0.25, 1e-9));
    });

    test('the transformed bounds swap their horizontal spans on a quarter turn', () {
      final template = TemplateData(
        (4, 2, 2),
        [
          for (var x = 0; x < 4; x++)
            for (var y = 0; y < 2; y++)
              for (var z = 0; z < 2; z++)
                TemplateBlock((x, y, z), const BState('minecraft:stone')),
        ],
      );
      for (final m in _mirrors) {
        for (final r in _rotations) {
          final w = SchematicWorld.fromTemplate(
            template,
            anchor: (10, 64, 10),
            rotation: r,
            mirror: m,
          );
          final quarter =
              r == BlockRotation.clockwise90 ||
              r == BlockRotation.counterclockwise90;
          expect(w.bounds.xSpan, quarter ? 2 : 4, reason: '$m/$r x');
          expect(w.bounds.zSpan, quarter ? 4 : 2, reason: '$m/$r z');
          expect(w.bounds.ySpan, 2, reason: '$m/$r y');
          // Every source block is inside the bounds.
          expect(w.allPositions.length, 16, reason: '$m/$r');
          for (final p in w.allPositions) {
            expect(w.bounds.isInside(p), isTrue, reason: '$p outside for $m/$r');
          }
        }
      }
    });

    test('the entity rotation is mirrored and then turned', () {
      List<int> entityNbt(double yaw) => BinaryNbt.write(
        NbtValue.compound({
          'id': const NbtValue.string('minecraft:armor_stand'),
          'Pos': NbtValue.list([
            const NbtValue.double64(0.5),
            const NbtValue.double64(0.0),
            const NbtValue.double64(0.5),
          ]),
          'Rotation': NbtValue.list([
            NbtValue.float(yaw),
            const NbtValue.float(0),
          ]),
        }),
      );
      double yawOf(SchematicWorld w) {
        final parsed = BinaryNbt.read(w.entities.single.nbt)!;
        return ((parsed.root.asCompound['Rotation']!.value as List<NbtValue>)[0]
                    .value as num)
            .toDouble();
      }

      final template = TemplateData(
        (2, 1, 2),
        const [],
        [TemplateEntity((0.5, 0.0, 0.5), (0, 0, 0), entityNbt(90))],
      );
      SchematicWorld world(BlockMirror m, BlockRotation r) =>
          SchematicWorld.fromTemplate(
            template,
            anchor: posZero,
            rotation: r,
            mirror: m,
          );
      // LEFT_RIGHT: 180 - 90 = 90, then + 90 for a clockwise turn.
      expect(yawOf(world(BlockMirror.leftRight, BlockRotation.clockwise90)), 180);
      // FRONT_BACK: -90, then + 180.
      expect(yawOf(world(BlockMirror.frontBack, BlockRotation.clockwise180)), 90);
      // No mirror: 90 + 270.
      expect(yawOf(world(BlockMirror.none, BlockRotation.counterclockwise90)), 360);
      // The absolute position is the anchor plus the transformed relative position.
      final at = SchematicWorld.fromTemplate(
        template,
        anchor: (10, 64, 10),
        rotation: BlockRotation.clockwise90,
      ).entities.single;
      expect(at.relativePos.$1, closeTo(0.5, 1e-9));
      expect(at.relativePos.$3, closeTo(0.5, 1e-9));
      expect(at.relativeBlockPos, (0, 0, 0));
    });

    test('spawning an entity rewrites Pos and block_pos', () {
      final nbt = BinaryNbt.write(
        NbtValue.compound({
          'id': const NbtValue.string('minecraft:armor_stand'),
          'block_pos': NbtValue.list([
            const NbtValue.int32(1),
            const NbtValue.int32(2),
            const NbtValue.int32(3),
          ]),
          'UUID': const NbtValue.long(7),
        }),
      );
      final e = SchematicEntity((0, 0, 0), (0, 0, 0), nbt);
      final out = BinaryNbt.read(
        e.withPosition((10.5, 64.0, 11.5), blockPos: (10, 64, 11)),
      )!;
      final root = out.root.asCompound;
      expect(root.containsKey('UUID'), isFalse);
      final pos = (root['Pos']!.value as List<NbtValue>)
          .map((v) => (v.value as num).toDouble())
          .toList();
      expect(pos, [10.5, 64.0, 11.5]);
      final bp = (root['block_pos']!.value as List<NbtValue>)
          .map((v) => v.value as int)
          .toList();
      expect(bp, [10, 64, 11]);
    });
  });

  group('entity item sanitizing', () {
    test('an item frame loses unsafe components but keeps safe ones', () {
      final nbt = BinaryNbt.write(
        NbtValue.compound({
          'id': const NbtValue.string('minecraft:item_frame'),
          'Item': NbtValue.compound({
            'id': const NbtValue.string('minecraft:stone'),
            'count': const NbtValue.int32(1),
            'components': NbtValue.compound({
              'minecraft:custom_name': NbtValue.compound({
                'text': const NbtValue.string('kept'),
              }),
              'minecraft:enchantments': NbtValue.emptyCompound(),
              'minecraft:custom_data': NbtValue.emptyCompound(),
            }),
          }),
        }),
      );
      final root = BinaryNbt.read(nbt)!.root.asCompound;
      sanitizeEntityItems(root);
      final components =
          root['Item']!.asCompound['components']!.asCompound;
      expect(components.keys.toSet(), {
        'minecraft:custom_name',
        'minecraft:enchantments',
      });
    });

    test('armor stand equipment is sanitized per slot', () {
      final root = BinaryNbt.read(
        BinaryNbt.write(
          NbtValue.compound({
            'id': const NbtValue.string('minecraft:armor_stand'),
            'equipment': NbtValue.compound({
              'head': NbtValue.compound({
                'id': const NbtValue.string('minecraft:iron_helmet'),
                'count': const NbtValue.int32(1),
                'components': NbtValue.compound({
                  'minecraft:custom_data': NbtValue.emptyCompound(),
                  'minecraft:damage': const NbtValue.int32(3),
                }),
              }),
            }),
          }),
        ),
      )!.root.asCompound;
      sanitizeEntityItems(root);
      final head = root['equipment']!.asCompound['head']!.asCompound;
      expect(
        head['components']!.asCompound.keys.toSet(),
        {'minecraft:damage'},
      );
    });
  });

  group('printer walk', () {
    test('visits exactly the bounds, x then z then y', () {
      final world = SchematicWorld(posZero);
      for (var x = 0; x < 3; x++) {
        for (var z = 0; z < 2; z++) {
          for (var y = 0; y < 2; y++) {
            world.setBlock((x, y, z), const SchematicBlock(BState('minecraft:stone')));
          }
        }
      }
      expect(world.bounds, BlockBounds.fromCorners((0, 0, 0), (2, 1, 1)));
      final printer = SchematicPrinter()..load(world);
      final order = <Pos>[];
      while (printer.advanceCurrentPos()) {
        order.add(printer.currentPos!);
      }
      expect(order.length, 12);
      expect(order.toSet().length, 12);
      for (final p in order) {
        expect(world.bounds.isInside(p), isTrue, reason: '$p is outside');
      }
      // x fastest, then z, then y.
      expect(order.take(4).toList(), const [
        (0, 0, 0),
        (1, 0, 0),
        (2, 0, 0),
        (0, 0, 1),
      ]);
      expect(order[4], (1, 0, 1));
      expect(order[6], (0, 1, 0));
      expect(order.last, (2, 1, 1));
    });

    test('setZeroAge resets growth, cauldrons and pistons', () {
      expect(
        SchematicPrinter.setZeroAge(
          const BState('minecraft:wheat', {'age': '7'}),
        )['age'],
        '0',
      );
      expect(
        SchematicPrinter.setZeroAge(
          const BState('minecraft:water_cauldron', {'level': '3'}),
        ),
        const BState('minecraft:cauldron'),
      );
      expect(
        SchematicPrinter.setZeroAge(
          const BState('minecraft:composter', {'level': '8'}),
        )['level'],
        '0',
      );
      expect(
        SchematicPrinter.setZeroAge(
          const BState('minecraft:sticky_piston', {'extended': 'true'}),
        )['extended'],
        'false',
      );
    });
  });

  group('requirements with block entity data', () {
    test('a banner with patterns needs a matching banner item', () {
      final requirements = SchematicRequirements()..itemOfBlock = (k) => k;
      final patterns = NbtValue.list([
        NbtValue.compound({
          'pattern': const NbtValue.string('minecraft:stripe_top'),
          'color': const NbtValue.string('red'),
        }),
      ]);
      final nbt = BinaryNbt.write(
        NbtValue.compound({
          'id': const NbtValue.string('minecraft:banner'),
          'patterns': patterns,
        }),
      );
      final requirement = requirements.ofBlock(
        const BState('minecraft:white_banner', {'rotation': '0'}),
        nbt,
      );
      final stack = requirement.requiredItems.single;
      expect(stack.item, 'minecraft:white_banner');
      expect(stack.count, 1);
      expect(
        stack.matches(
          'minecraft:white_banner',
          otherComponents: {'minecraft:banner_patterns': patterns},
        ),
        isTrue,
      );
      expect(
        stack.matches(
          'minecraft:white_banner',
          otherComponents: {
            'minecraft:banner_patterns': NbtValue.list([]),
          },
        ),
        isFalse,
      );
      // Without patterns any banner matches.
      final plain = requirements.ofBlock(
        const BState('minecraft:white_banner', {'rotation': '0'}),
        null,
      );
      expect(plain.requiredItems.single.strictComponents, isNull);
    });

    test('component equality is structural', () {
      final a = NbtValue.compound({
        'text': const NbtValue.string('x'),
        'extra': NbtValue.list([const NbtValue.int32(1)]),
      });
      final b = NbtValue.compound({
        'text': const NbtValue.string('x'),
        'extra': NbtValue.list([const NbtValue.int32(1)]),
      });
      expect(StackRequirement.componentsMatch(a, b), isTrue);
      expect(
        StackRequirement.componentsMatch(
          a,
          NbtValue.compound({
            'text': const NbtValue.string('x'),
            'extra': NbtValue.list([const NbtValue.int32(2)]),
          }),
        ),
        isFalse,
      );
      expect(StackRequirement.componentsMatch(a, null), isFalse);
    });
  });

}
