import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/redstone/lamp_logic.dart';
import 'package:create/src/redstone/nixie/nixie_logic.dart';
import 'package:create/src/redstone/rail_logic.dart';
import 'package:create/src/redstone/support/placement.dart';
import 'package:create/src/redstone/support/shapes.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

class FakeRailEnv implements RailEnv {
  final Map<Pos, BState> blocks = {};
  final Map<Pos, int> powered = {};

  @override
  BState stateAt(Pos pos) => blocks[pos] ?? BState.air;

  @override
  Future<int> bestNeighborSignal(Pos pos) async => powered[pos] ?? 0;
}

BState rail(String shape, {bool backwards = false, int power = 0}) =>
    BState(controllerRailKey, {'shape': shape, 'backwards': '$backwards', 'power': '$power'});

class FakePlaceWorld implements PlaceWorld {
  final Set<Pos> sturdy = {};
  final Set<Pos> detect = {};

  @override
  bool isFaceSturdy(Pos pos, Direction face) => sturdy.contains(pos);
  @override
  bool canBeReplaced(Pos pos) => false;
  @override
  bool canDetect(Pos pos) => detect.contains(pos);
}

void main() {
  group('rose quartz lamp', () {
    test('the cluster is every connected lamp within 16 blocks, breadth first', () {
      final lamps = {(1, 0, 0), (2, 0, 0), (3, 0, 0), (0, 1, 0), (30, 0, 0), (0, 0, 20)};
      final found = roseQuartzCluster((0, 0, 0), lamps.contains);
      expect(found.toSet(), {(1, 0, 0), (2, 0, 0), (3, 0, 0), (0, 1, 0)});
      expect(found.indexOf((1, 0, 0)), lessThan(found.indexOf((2, 0, 0))));
      expect(found.indexOf((2, 0, 0)), lessThan(found.indexOf((3, 0, 0))));
    });

    test('the cluster stops at 16 blocks manhattan from the start', () {
      final lamps = {for (var x = 1; x <= 30; x++) (x, 0, 0)};
      final found = roseQuartzCluster((0, 0, 0), lamps.contains);
      expect(found.length, 16);
    });

    test('output towards a normal reader, another lamp and a comparator', () {
      bool isLamp(Pos p) => p.x >= 0 && p.x <= 3 && p.y == 0 && p.z == 0;
      bool powering(Pos p) => p == (3, 0, 0);
      int sig(LampReader k, {bool own = true}) => roseQuartzSignal(
        pos: (0, 0, 0),
        side: Direction.east,
        powering: own,
        readerKind: k,
        isLamp: isLamp,
        isPowering: powering,
      );
      expect(sig(LampReader.other), 15);
      expect(sig(LampReader.other, own: false), 0);
      expect(sig(LampReader.lamp), 0);
      // The comparator reads the distance to the powered lamp along the column: 15 - 3? the
      // column walks from the lamp itself, powering at index 3 -> power 15 - 3 = 12.
      expect(sig(LampReader.comparator), 12);
    });

    test('neighbour change decisions', () {
      expect(roseQuartzOnNeighborChanged(powered: true, neighbourSignal: true), LampAction.nothing);
      expect(roseQuartzOnNeighborChanged(powered: false, neighbourSignal: false), LampAction.nothing);
      expect(roseQuartzOnNeighborChanged(powered: true, neighbourSignal: false), LampAction.switchOff);
      expect(roseQuartzOnNeighborChanged(powered: false, neighbourSignal: true), LampAction.activate);
    });

    test('the tick moves ACTIVATE into POWERING', () {
      expect(roseQuartzTick(activate: true, powering: false), (activate: false, powering: true));
      expect(roseQuartzTick(activate: false, powering: true), (activate: false, powering: false));
      expect(roseQuartzTick(activate: false, powering: false), isNull);
    });
  });

  group('redstone contact and analog lever', () {
    test('contacts pair when they face each other', () {
      expect(hasValidContact('create:redstone_contact', Direction.south, Direction.north), isTrue);
      expect(hasValidContact('create:elevator_contact', Direction.south, Direction.north), isTrue);
      expect(hasValidContact('create:redstone_contact', Direction.north, Direction.north), isFalse);
      expect(hasValidContact('minecraft:stone', Direction.south, Direction.north), isFalse);
      expect(hasValidContact(null, null, Direction.north), isFalse);
    });

    test('contact output and wire connection', () {
      // facing up; the face towards the paired contact (up) gives no power
      expect(redstoneContactSignal(powered: true, facing: Direction.up, side: Direction.down), 0);
      expect(redstoneContactSignal(powered: true, facing: Direction.up, side: Direction.up), 15);
      expect(redstoneContactSignal(powered: false, facing: Direction.up, side: Direction.up), 0);
      expect(redstoneContactConnects(facing: Direction.up, side: Direction.down), isFalse);
      expect(redstoneContactConnects(facing: Direction.up, side: Direction.north), isTrue);
      expect(redstoneContactConnects(facing: Direction.up, side: null), isFalse);
    });

    test('analog lever steps and clamps', () {
      expect(analogLeverStep(0, back: false), (state: 1, changed: true));
      expect(analogLeverStep(15, back: false), (state: 15, changed: false));
      expect(analogLeverStep(0, back: true), (state: 0, changed: false));
      expect(analogLeverStep(7, back: true), (state: 6, changed: true));
      expect(analogLeverPitch(0), closeTo(0.25 + 5 / 15 * 0.5, 1e-9));
      expect(analogLeverDirectSignal(9, Direction.up, Direction.up), 9);
      expect(analogLeverDirectSignal(9, Direction.up, Direction.down), 0);
      expect(analogLeverConnected('ceiling', Direction.north), Direction.down);
      expect(analogLeverConnected('floor', Direction.north), Direction.up);
      expect(analogLeverConnected('wall', Direction.east), Direction.east);
    });

    test('analog lever: every changeState transition of the 16 states', () {
      // `AnalogLeverBlockEntity.changeState(back)`: a normal click adds one, a sneak click
      // subtracts one, both clamped to 0..15. `changed` is what restarts the 15 tick
      // `ChangeTimer` (`lastChange`), so it must be true exactly when the state moves.
      for (var state = 0; state <= 15; state++) {
        final up = analogLeverStep(state, back: false);
        final down = analogLeverStep(state, back: true);
        expect(up.state, state == 15 ? 15 : state + 1, reason: 'state $state forward');
        expect(up.changed, state != 15, reason: 'state $state forward changed');
        expect(down.state, state == 0 ? 0 : state - 1, reason: 'state $state back');
        expect(down.changed, state != 0, reason: 'state $state back changed');
      }
    });

    test('analog lever walks 0 to 15 and back one step at a time', () {
      var state = 0;
      for (var expected = 1; expected <= 15; expected++) {
        final step = analogLeverStep(state, back: false);
        expect(step, (state: expected, changed: true));
        state = step.state;
      }
      expect(analogLeverStep(state, back: false), (state: 15, changed: false));
      for (var expected = 14; expected >= 0; expected--) {
        final step = analogLeverStep(state, back: true);
        expect(step, (state: expected, changed: true));
        state = step.state;
      }
      expect(analogLeverStep(state, back: true), (state: 0, changed: false));
    });

    test('analog lever pitch rises with the state and stays within the lever click range', () {
      var previous = analogLeverPitch(0);
      expect(previous, closeTo(0.25 + 5 / 15 * 0.5, 1e-9));
      for (var state = 1; state <= 15; state++) {
        final pitch = analogLeverPitch(state);
        expect(pitch, greaterThan(previous));
        expect(pitch, lessThan(1.0));
        previous = pitch;
      }
      expect(analogLeverPitch(15), closeTo(0.25 + 20 / 15 * 0.5, 1e-9));
    });
  });

  group('controller rail', () {
    test('acceleration follows the shape and BACKWARDS', () {
      expect(railAcceleration({'shape': 'north_south', 'backwards': 'false'}), Direction.north);
      expect(railAcceleration({'shape': 'north_south', 'backwards': 'true'}), Direction.south);
      expect(railAcceleration({'shape': 'east_west', 'backwards': 'false'}), Direction.west);
      expect(railAcceleration({'shape': 'east_west', 'backwards': 'true'}), Direction.east);
      // ascending east/south are "reversed slopes": the flag cancels out
      expect(railAcceleration({'shape': 'ascending_east', 'backwards': 'false'}), Direction.west);
      expect(railAcceleration({'shape': 'ascending_east', 'backwards': 'true'}), Direction.east);
      expect(railAcceleration({'shape': 'ascending_south', 'backwards': 'true'}), Direction.south);
    });

    test('a powered neighbour gives the best signal', () async {
      final env = FakeRailEnv()..blocks[(0, 0, 0)] = rail('north_south')..powered[(0, 0, 0)] = 9;
      expect(await calculateRailPower((0, 0, 0), env), 9);
    });

    test('power is interpolated between two powered rails on the line', () async {
      final env = FakeRailEnv();
      for (var z = -4; z <= 4; z++) {
        env.blocks[(0, 0, z)] = rail('north_south'); // pointing north
      }
      env.powered[(0, 0, -4)] = 15; // forward is north (negative z)
      env.powered[(0, 0, 4)] = 3; // behind
      // at z=0: forward distance 4, backwards distance 4 -> (3*4 + 15*4) / 8 = 9
      expect(await calculateRailPower((0, 0, 0), env), 9);
      // at z=-2: forward 2, backwards 6: (3*2 + 15*6) / 8 = 12
      expect(await calculateRailPower((0, 0, -2), env), 12);
    });

    test('a rail too far from power stays unpowered', () async {
      final env = FakeRailEnv();
      for (var z = -12; z <= 12; z++) {
        env.blocks[(0, 0, z)] = rail('north_south');
      }
      env.powered[(0, 0, -12)] = 15;
      env.powered[(0, 0, 12)] = 15;
      expect(await calculateRailPower((0, 0, 0), env), 0);
    });

    test('one powered end within eight blocks powers the rail with that value', () async {
      final env = FakeRailEnv();
      for (var z = -6; z <= 0; z++) {
        env.blocks[(0, 0, z)] = rail('north_south');
      }
      env.powered[(0, 0, -6)] = 11;
      expect(await calculateRailPower((0, 0, 0), env), 11);
    });

    test('findNextRail follows slopes', () {
      final env = FakeRailEnv()
        ..blocks[(0, 0, 0)] = rail('ascending_north')
        ..blocks[(0, 1, -1)] = rail('north_south');
      expect(findNextRail((0, 0, 0), env, reversed: false), (0, 1, -1));
      expect(findNextRail((0, 0, 0), env, reversed: true), isNull);
    });

    test('cart velocity: accelerate along the rail or drift to the centre', () {
      final props = {'shape': 'north_south', 'backwards': 'false', 'power': '15'};
      final go = cartVelocity(props: props, motion: (0, 0, 0), cartPos: (0.5, 0, 0.5), railPos: (0, 0, 0))!;
      expect(go.decelerate, isFalse);
      expect(go.velocity.$3, closeTo(-0.4, 1e-9));
      final half = cartVelocity(props: {...props, 'power': '5'}, motion: (0, 0, -0.1), cartPos: (0.5, 0, 0.5), railPos: (0, 0, 0))!;
      expect(half.velocity.$3, closeTo(-0.4 / 3, 1e-9));
      // moving against the rail: slow down towards the centre
      final slow = cartVelocity(props: props, motion: (0, 0, 0.3), cartPos: (0.9, 0, 0.5), railPos: (0, 0, 0))!;
      expect(slow.decelerate, isTrue);
      expect(slow.velocity.$1, closeTo((0.5 - 0.9) / 16, 1e-9));
      // no power at all on a still cart: drift
      final off = cartVelocity(props: {...props, 'power': '0'}, motion: (0, 0, 0), cartPos: (0.5, 0, 0.5), railPos: (0, 0, 0))!;
      expect(off.decelerate, isTrue);
    });

    test('rotation flips BACKWARDS like Java', () {
      expect(railRotate({'shape': 'north_south', 'backwards': 'false'}, BlockRotation.clockwise180), (shape: 'north_south', backwards: true));
      final cw = railRotate({'shape': 'north_south', 'backwards': 'false'}, BlockRotation.clockwise90);
      expect(cw.shape, 'east_west');
      expect(cw.backwards, isTrue); // east_west points west by default; north turned east
      final ccw = railRotate({'shape': 'north_south', 'backwards': 'false'}, BlockRotation.counterclockwise90);
      expect(ccw.shape, 'east_west');
      expect(ccw.backwards, isFalse);
    });

    test('stability needs support below, and on the high side for slopes', () {
      final support = <Pos>{(0, -1, 0)};
      expect(railIsStable('north_south', support.contains, (0, 0, 0)), isTrue);
      expect(railIsStable('ascending_north', support.contains, (0, 0, 0)), isFalse);
      support.add((0, 0, -1));
      expect(railIsStable('ascending_north', support.contains, (0, 0, 0)), isTrue);
    });
  });

  group('nixie tubes', () {
    ({String key, Map<String, String> properties}) tube(String color, {String face = 'floor', String facing = 'north'}) =>
        (key: nixieBlockKey(color), properties: {'double_face': face, 'facing': facing, 'waterlogged': 'false'});

    test('block keys: orange is the plain nixie tube', () {
      expect(nixieBlockKey('orange'), 'create:nixie_tube');
      expect(nixieBlockKey('light_blue'), 'create:light_blue_nixie_tube');
      expect(nixieBlockKeys.length, 16);
      expect(isNixieKey('create:white_nixie_tube'), isTrue);
      expect(isNixieKey('create:shaft'), isFalse);
    });

    test('rows run along the facing axis, numbered from the left', () {
      // a floor tube facing north extends along z (left is facing.opposite = south)
      final world = {for (var z = 0; z < 4; z++) (0, 0, z): tube(z.isEven ? 'orange' : 'red')};
      world[(0, 0, 5)] = tube('orange');
      final row = walkNixies((0, 0, 2), world.containsKey((0, 0, 0)) ? (p) => world[p] : (p) => null);
      expect(row.map((e) => e.$1.z), [3, 2, 1, 0]);
      expect(row.map((e) => e.$2), [0, 1, 2, 3]);
    });

    test('a different attachment ends the row', () {
      final world = {(0, 0, 0): tube('orange'), (0, 0, 1): tube('orange', face: 'ceiling')};
      expect(walkNixies((0, 0, 0), (p) => world[p]).length, 1);
      expect(walkNixies((5, 5, 5), (p) => world[p]), isEmpty);
    });

    test('wall tubes stack vertically', () {
      expect(leftNixieDirection({'double_face': 'wall', 'facing': 'north'}), Direction.up);
      expect(leftNixieDirection({'double_face': 'wall_reversed', 'facing': 'north'}), Direction.down);
      expect(leftNixieDirection({'double_face': 'floor', 'facing': 'north'}), Direction.south);
      expect(rightNixieDirection({'double_face': 'floor', 'facing': 'north'}), Direction.north);
    });

    test('displayed characters: redstone strength or text', () {
      expect(displayedStrings(nixieIndex: 0, redstoneStrength: 7), ('0', '7'));
      expect(displayedStrings(nixieIndex: 0, redstoneStrength: 12), ('1', '2'));
      expect(displayedStrings(customText: 'HELLO', nixieIndex: 1, redstoneStrength: 0), ('L', 'L'));
      expect(displayedStrings(customText: 'HELLO', nixieIndex: 2, redstoneStrength: 0), ('O', ' '));
      expect(displayedStrings(customText: 'HELLO', nixieIndex: 5, redstoneStrength: 0), (' ', ' '));
    });

    test('dye items', () {
      expect(dyeColorOfItem('minecraft:red_dye'), 'red');
      expect(dyeColorOfItem('minecraft:light_gray_dye'), 'light_gray');
      expect(dyeColorOfItem('minecraft:bone_meal'), isNull);
      expect(dyeColorOfItem('create:red_dye'), isNull);
    });
  });

  group('placement', () {
    PlaceCtx ctx({double yaw = 0, double pitch = 0, bool sneaking = false, Direction? clicked}) =>
        PlaceCtx(pos: (0, 64, 0), yaw: yaw, pitch: pitch, sneaking: sneaking, clickedFace: clicked);

    test('looking directions', () {
      // yaw 0 faces south, 90 west, 180 north, 270 east
      expect(ctx(yaw: 0).horizontalDirection, Direction.south);
      expect(ctx(yaw: 90).horizontalDirection, Direction.west);
      expect(ctx(yaw: 180).horizontalDirection, Direction.north);
      expect(ctx(yaw: 270).horizontalDirection, Direction.east);
      expect(ctx(pitch: 90).nearestLookingDirection, Direction.down);
      expect(ctx(pitch: -90).nearestLookingDirection, Direction.up);
      expect(ctx(yaw: 0).nearestLookingDirection, Direction.south);
    });

    test('a lever on a wall hangs on the block in the look direction', () {
      final world = FakePlaceWorld()..sturdy.add((0, 64, 1)); // south of the lever
      final p = faceAttachedPlacement(ctx(yaw: 0), world)!;
      expect(p, {'face': 'wall', 'facing': 'north'});
    });

    test('a lever looks for another support when the first choice has none', () {
      final world = FakePlaceWorld()..sturdy.add((0, 63, 0)); // below only
      final p = faceAttachedPlacement(ctx(yaw: 0), world)!;
      expect(p['face'], 'floor');
      expect(p['facing'], 'south'); // the player's horizontal direction
      expect(faceAttachedPlacement(ctx(yaw: 0), FakePlaceWorld()), isNull);
    });

    test('a lever on the ceiling', () {
      final world = FakePlaceWorld()..sturdy.add((0, 65, 0));
      expect(faceAttachedPlacement(ctx(pitch: -90), world), {'face': 'ceiling', 'facing': 'south'});
    });

    test('nixie tubes: floor and ceiling turn clockwise, walls follow the view', () {
      final floor = nixiePlacement(ctx(yaw: 0, pitch: 90));
      expect(floor['double_face'], 'floor');
      expect(floor['facing'], Direction.south.clockWise.serializedName);
      final wall = nixiePlacement(ctx(yaw: 0, pitch: 0));
      expect(wall['facing'], 'north');
      expect(['wall', 'wall_reversed'], contains(wall['double_face']));
    });

    test('contact: sneaking or a pair picks the clicked side', () {
      final plain = contactPlacement(ctx(yaw: 0, pitch: -90, clicked: Direction.east), (p, d) => false);
      expect(plain['facing'], 'down'); // nearest looking is up, opposite is down
      final sneak = contactPlacement(ctx(yaw: 0, sneaking: true, clicked: Direction.east), (p, d) => false);
      expect(sneak['facing'], 'west');
      final pair = contactPlacement(ctx(yaw: 0, clicked: Direction.east), (p, d) => d == Direction.west);
      expect(pair['facing'], 'west');
      expect(pair['powered'], 'true');
    });

    test('directed blocks prefer a neighbour they can observe', () {
      final world = FakePlaceWorld()..detect.add((1, 64, 0));
      final p = directedPlacement(ctx(yaw: 270), world.canDetect);
      expect(p, {'target': 'wall', 'facing': 'east'});
    });

    test('directed blocks without a neighbour face away (towards when sneaking)', () {
      expect(directedPlacement(ctx(yaw: 0), (_) => false), {'target': 'wall', 'facing': 'north'});
      expect(directedPlacement(ctx(yaw: 0, sneaking: true), (_) => false), {'target': 'wall', 'facing': 'south'});
    });

    test('directed blocks pointing up or down use the target property', () {
      final down = directedPlacement(ctx(yaw: 180, pitch: 90), (p) => p == (0, 63, 0));
      expect(down, {'target': 'floor', 'facing': 'north'});
      expect(directedTargetDirection('floor', Direction.north), Direction.down);
      expect(directedTargetDirection('ceiling', Direction.north), Direction.up);
      expect(directedTargetDirection('wall', Direction.east), Direction.east);
    });

    test('rails follow the player direction', () {
      expect(railPlacement(ctx(yaw: 0)), {'shape': 'north_south', 'backwards': 'true'});
      expect(railPlacement(ctx(yaw: 180)), {'shape': 'north_south', 'backwards': 'false'});
      expect(railPlacement(ctx(yaw: 270)), {'shape': 'east_west', 'backwards': 'true'});
    });
  });

  group('shapes', () {
    test('a box facing up rotates to every direction and back', () {
      const boxes = [BlockBox(0.25, 0, 0.25, 0.75, 0.5, 0.75)];
      for (final d in Direction.values) {
        final r = rotateBoxes(boxes, Direction.up, d);
        final back = rotateBoxes(r, d, Direction.up);
        expect(back.single.minX, closeTo(0.25, 1e-9), reason: '$d');
        expect(back.single.maxY, closeTo(0.5, 1e-9), reason: '$d');
      }
    });

    test('the up shape pointing north sits against the south side... the base is on the facing side', () {
      const boxes = [BlockBox(0, 0, 0, 1, 0.125, 1)]; // a slab on the floor (facing up)
      final north = rotateBoxes(boxes, Direction.up, Direction.north).single;
      expect(north.minZ, 0.875); // the base is on the side opposite to the facing
      expect(north.maxZ, 1.0);
      final east = rotateBoxes(boxes, Direction.up, Direction.east).single;
      expect(east.maxX, 0.125);
    });

    test('horizontal rotation turns quarter turns', () {
      const boxes = [BlockBox(0, 0, 0, 0.25, 1, 0.5)];
      final east = rotateBoxes(boxes, Direction.south, Direction.west).single; // two turns
      expect(east.minX, 0.5);
      expect(east.maxX, 1.0);
      expect(east.maxZ, 0.25);
    });
  });

  group('analog lever shape', () {
    // `AnalogLeverBlock.SHAPES = Shapes.rotateAttachFace(Block.boxZ(6.0, 8.0, 10.0, 16.0))`:
    // the wall shape is x 5..11, y 8..10, z 10..16, so the floor variant covers y 0..6 and
    // the ceiling variant y 10..16 (a quarter turn about x each, the ceiling also a half
    // turn about y). A shorter box leaves the upper half of a floor lever unclickable.
    BlockBox lever(String face, Direction facing) {
      final shape = leverShapeRules()
          .firstWhere((r) => r.when['face'] == face && r.when['facing'] == facing.serializedName)
          .selectionShape!;
      return (shape as BoxesShape).boxes.single;
    }

    test('a floor lever covers the lower six pixels and the full depth', () {
      final box = lever('floor', Direction.north);
      expect(box.minX, 5 / 16);
      expect(box.minY, 0);
      expect(box.minZ, 4 / 16);
      expect(box.maxX, 11 / 16);
      expect(box.maxY, 6 / 16);
      expect(box.maxZ, 12 / 16);
    });

    test('a ceiling lever hangs from the top six pixels', () {
      final box = lever('ceiling', Direction.north);
      expect(box.minY, 10 / 16);
      expect(box.maxY, 1);
      expect(box.minZ, 4 / 16);
      expect(box.maxZ, 12 / 16);
    });

    test('the floor and ceiling variants are turned for east and west too', () {
      final floor = lever('floor', Direction.east);
      expect(floor.minX, 4 / 16);
      expect(floor.minZ, 5 / 16);
      expect(floor.maxY, 6 / 16);
      final ceiling = lever('ceiling', Direction.west);
      expect(ceiling.minX, 4 / 16);
      expect(ceiling.maxX, 12 / 16);
      expect(ceiling.minY, 10 / 16);
    });
  });
}
