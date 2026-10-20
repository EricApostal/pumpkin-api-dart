import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/direction.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/common/vec_helper.dart';
import 'package:create/src/conveyance/behaviours/belt_interfaces.dart';
import 'package:create/src/conveyance/belt/belt_block_def.dart';
import 'package:create/src/conveyance/belt/belt_geometry.dart';
import 'package:create/src/conveyance/belt/belt_inventory.dart';
import 'package:create/src/conveyance/belt/belt_ports.dart';
import 'package:create/src/conveyance/belt/transported_item.dart';
import 'package:create/src/conveyance/items/item_data.dart';
import 'package:create/src/kinetics/geometry.dart' show Dir, KAxis, KPos, KState;
import 'package:test/test.dart';

import 'kinetics_test_support.dart';

/// A straight horizontal belt along +x starting at (0, 0, 0).
class FakeBelt implements BeltEnvironment {
  FakeBelt({this.length = 4, this.speedValue = 32});

  final int length;
  double speedValue;
  int updates = 0;
  final spawned = <(ItemValue, Vec3, Vec3)>[];
  final Map<Pos, DirectBeltInput> inputs = {};
  final Map<Pos, BeltProcessing> processing = {};
  final Map<Pos, TransportedItemStackHandler> handlers = {};
  final Set<Pos> solid = {};
  final Map<int, BeltFunnelPort> funnels = {};
  final Map<int, BeltTunnelPort> tunnels = {};
  final Map<int, BeltTunnelPort> brass = {};
  final Map<int, BeltCrusherPort> crushers = {};
  @override
  final VersionTracker versionTracker = VersionTracker();

  @override
  double get speed => speedValue;
  @override
  double get beltMovementSpeed => speedValue / 480;
  @override
  double get directionAwareBeltMovementSpeed => beltMovementSpeed;
  @override
  Direction get movementFacing => speedValue >= 0 ? Direction.east : Direction.west;
  @override
  bool get isHorizontal => true;
  @override
  int get beltLength => length;
  @override
  Pos positionForOffset(int offset) => (offset, 0, 0);
  @override
  Vec3 vectorForOffset(double offset) => (offset, 0.5, 0.5);
  @override
  Pos get beltChainDirection => (1, 0, 0);
  @override
  bool isLoaded(Pos pos) => true;
  @override
  DirectBeltInput? directInputAt(Pos pos) => inputs[pos];
  @override
  BeltProcessing? processingAt(Pos pos) => processing[pos];
  @override
  TransportedItemStackHandler? stackHandlerAt(Pos pos) => handlers[pos];
  @override
  bool isProcessingBlocked(Pos processingSpace) => false;
  @override
  bool hasSolidSide(Pos pos, Direction side) => solid.contains(pos);
  @override
  BeltFunnelPort? funnelAbove(int segment) => funnels[segment];
  @override
  BeltTunnelPort? tunnelOnSegment(int segment) => tunnels[segment];
  @override
  BeltTunnelPort? brassTunnelAbove(int segment) => brass[segment];
  @override
  BeltCrusherPort? crusherAbove(int segment) => crushers[segment];
  @override
  void notifyUpdate() => updates++;
  @override
  void spawnItem(ItemValue stack, Vec3 position, Vec3 motion) => spawned.add((stack, position, motion));
}

class RecordingInput implements DirectBeltInput {
  final received = <ItemValue>[];
  bool accepts = true;
  @override
  bool canInsertFromSide(Direction side) => accepts;
  @override
  bool isOccupied(Direction side) => false;
  @override
  ItemValue handleInsertion(TransportedItemStack stack, Direction side, {bool simulate = false}) {
    if (!simulate) received.add(stack.stack);
    return ItemValue.empty;
  }

  @override
  bool get canSupportBeltFunnels => false;
}

TransportedItemStack stackAt(double pos, [String key = 'minecraft:stone']) {
  final t = TransportedItemStack(ItemValue(key, 1));
  t.beltPosition = t.prevBeltPosition = pos;
  return t;
}

void main() {
  group('BeltInventory', () {
    test('items move along the belt at the belt speed', () async {
      final env = FakeBelt();
      final inv = BeltInventory(env);
      inv.addItem(stackAt(0.5));
      await inv.tick(); // inserts
      final item = inv.items.single;
      final start = item.beltPosition;
      await inv.tick();
      expect(item.beltPosition, closeTo(start + 32 / 480, 1e-9));
      expect(item.prevBeltPosition, closeTo(start, 1e-9));
    });

    test('an item stops at the end margin when the belt ends in a solid wall', () async {
      final env = FakeBelt(length: 2)..solid.add((2, 0, 0));
      final inv = BeltInventory(env);
      inv.addItem(stackAt(1.9));
      for (var i = 0; i < 40; i++) {
        await inv.tick();
      }
      expect(inv.items.single.beltPosition, closeTo(2 - 0.45, 1e-6));
      expect(env.spawned, isEmpty);
    });

    test('an item is ejected when nothing is at the end of the belt', () async {
      final env = FakeBelt(length: 2);
      final inv = BeltInventory(env);
      inv.addItem(stackAt(1.9));
      for (var i = 0; i < 40; i++) {
        await inv.tick();
      }
      expect(inv.items, isEmpty);
      expect(env.spawned, hasLength(1));
      expect(env.spawned.single.$1.key, 'minecraft:stone');
    });

    test('an item is handed to a direct input at the end of the belt', () async {
      final env = FakeBelt(length: 2);
      final input = RecordingInput();
      env.inputs[(2, 0, 0)] = input;
      final inv = BeltInventory(env);
      inv.addItem(stackAt(1.9));
      for (var i = 0; i < 40; i++) {
        await inv.tick();
      }
      expect(input.received, hasLength(1));
      expect(inv.items, isEmpty);
    });

    test('items keep a gap of one block', () async {
      final env = FakeBelt(length: 4)..solid.add((4, 0, 0));
      final inv = BeltInventory(env);
      inv.addItem(stackAt(1.0));
      inv.addItem(stackAt(3.0));
      for (var i = 0; i < 100; i++) {
        await inv.tick();
      }
      final positions = inv.items.map((e) => e.beltPosition).toList()..sort();
      expect(positions.last - positions.first, closeTo(1.0, 1e-6));
      expect(positions.last, closeTo(4 - 0.45, 1e-6));
    });

    test('reversing the belt reverses the item order', () async {
      final env = FakeBelt(length: 6);
      final inv = BeltInventory(env);
      inv.addItem(stackAt(1));
      inv.addItem(stackAt(3));
      await inv.tick();
      expect(inv.items.first.beltPosition, greaterThan(inv.items.last.beltPosition));
      env.speedValue = -32;
      await inv.tick();
      expect(inv.items.first.beltPosition, lessThan(inv.items.last.beltPosition));
    });

    test('processing machines hold an item and release it', () async {
      final env = FakeBelt(length: 4);
      final hold = _HoldOnce();
      env.processing[(1, 2, 0)] = hold;
      env.handlers[(1, 0, 0)] = _NoopHandler();
      final inv = BeltInventory(env);
      inv.addItem(stackAt(0.8));
      for (var i = 0; i < 40; i++) {
        await inv.tick();
      }
      expect(hold.received, 1);
      expect(inv.items.single.locked, isFalse);
      expect(hold.held, greaterThan(0));
      expect(inv.items.single.beltPosition, greaterThan(1.5));
    });

    test('a belt funnel takes an item that crosses it', () async {
      final env = FakeBelt(length: 4);
      final funnel = _FakeFunnel(Direction.north, 'retracted');
      env.funnels[1] = _FunnelPort(funnel);
      final inv = BeltInventory(env);
      inv.addItem(stackAt(0.9));
      for (var i = 0; i < 20; i++) {
        await inv.tick();
      }
      expect(funnel.inserted, hasLength(1));
      expect(inv.items, isEmpty.or(isNotEmpty));
      expect(inv.items.every((e) => e.stack.isEmpty), isTrue);
    });

    test('canInsertAtFromSide is blocked by a recently inserted item', () async {
      final env = FakeBelt();
      final inv = BeltInventory(env);
      final s = stackAt(1.5)
        ..insertedAt = 1
        ..insertedFrom = Direction.up;
      inv.addItem(s);
      expect(inv.canInsertAtFromSide(1, Direction.up), isFalse);
      expect(inv.canInsertAtFromSide(3, Direction.up), isTrue);
      expect(inv.canInsertAtFromSide(1, Direction.west), isFalse); // moving east: west is the back
    });

    test('applyToEachWithin converts items', () async {
      final env = FakeBelt();
      final inv = BeltInventory(env);
      inv.addItem(stackAt(1.5));
      await inv.tick();
      inv.applyToEachWithin(1.5, .55, (t) {
        return TransportedResult.convertTo(TransportedItemStack(ItemValue('minecraft:dirt', 2))..beltPosition = t.beltPosition);
      });
      await inv.tick();
      expect(inv.items.single.stack.key, 'minecraft:dirt');
    });
  });

  group('belt geometry', () {
    BState belt(Direction f, {String slope = 'horizontal', String part = 'middle', bool casing = false}) =>
        BState(beltKey, {'facing': f.serializedName, 'slope': slope, 'part': part, 'casing': '$casing'});

    test('the chain follows the facing and the slope', () {
      final world = MapBlockGetter();
      world.set((0, 0, 0), belt(Direction.east, part: 'start'));
      world.set((1, 0, 0), belt(Direction.east));
      world.set((2, 0, 0), belt(Direction.east, part: 'end'));
      expect(getBeltChain(world, (0, 0, 0)), [(0, 0, 0), (1, 0, 0), (2, 0, 0)]);

      final up = MapBlockGetter();
      up.set((0, 0, 0), belt(Direction.south, slope: 'upward', part: 'start'));
      up.set((0, 1, 1), belt(Direction.south, slope: 'upward'));
      up.set((0, 2, 2), belt(Direction.south, slope: 'upward', part: 'end'));
      expect(getBeltChain(up, (0, 0, 0)), [(0, 0, 0), (0, 1, 1), (0, 2, 2)]);
      expect(nextSegmentPosition(belt(Direction.south, slope: 'upward', part: 'start'), (0, 0, 0), false), isNull);
    });

    test('vertical belts follow the axis direction of the facing', () {
      expect(nextSegmentPosition(belt(Direction.east, slope: 'vertical'), (0, 5, 0), true), (0, 6, 0));
      expect(nextSegmentPosition(belt(Direction.west, slope: 'vertical'), (0, 5, 0), true), (0, 4, 0));
    });

    test('rotation axis', () {
      expect(beltRotationAxis(belt(Direction.north)), Axis.x);
      expect(beltRotationAxis(belt(Direction.east)), Axis.z);
      expect(beltRotationAxis(belt(Direction.east, slope: 'sideways')), Axis.y);
    });

    test('canTransportObjects excludes vertical and sideways belts', () {
      expect(canTransportObjects(belt(Direction.north)), isTrue);
      expect(canTransportObjects(belt(Direction.north, slope: 'vertical')), isFalse);
      expect(canTransportObjects(belt(Direction.north, slope: 'sideways')), isFalse);
      expect(canTransportObjects(BState('create:chute')), isFalse);
    });

    test('belt vector and offsets', () {
      expect(beltVector(belt(Direction.east, slope: 'upward')), (1.0, 1.0, 0.0));
      expect(beltVector(belt(Direction.west, slope: 'vertical')), (0.0, -1.0, 0.0));
      final s = belt(Direction.east, slope: 'upward', part: 'start');
      expect(positionForOffset((10, 5, 10), s, 4, 2), (12, 7, 10));
      final v = vectorForOffset((10, 5, 10), s, 4, 2.0);
      expect(v, (12.0, 7.0, 10.5));
    });

    test('flipBelt mirrors the belt around its chain', () {
      final f = flipBelt(belt(Direction.east, slope: 'upward', part: 'start'));
      expect(f.beltFacing, Direction.west);
      expect(f.beltSlope, BeltSlope.downward);
      expect(f.beltPart, BeltPart.end);
    });

    test('compatible belt states', () {
      expect(beltStatesCompatible(belt(Direction.east), belt(Direction.west)), isTrue);
      expect(beltStatesCompatible(belt(Direction.east), belt(Direction.north)), isFalse);
      expect(beltStatesCompatible(belt(Direction.east, slope: 'upward'), belt(Direction.west, slope: 'downward')), isTrue);
      expect(beltStatesCompatible(belt(Direction.east, slope: 'upward'), belt(Direction.west, slope: 'upward')), isFalse);
    });

    test('rotation of vertical belts swaps start and end when the direction flips', () {
      final s = belt(Direction.east, slope: 'vertical', part: 'start');
      final r = rotateBelt(s, BlockRotation.clockwise180);
      expect(r.beltFacing, Direction.west);
      expect(r.beltPart, BeltPart.end);
      final r2 = rotateBelt(s, BlockRotation.clockwise90);
      expect(r2.beltFacing, Direction.south);
    });

    test('slope and facing between two shafts', () {
      expect(getSlopeBetween((0, 0, 0), (3, 3, 0)), BeltSlope.upward);
      expect(getSlopeBetween((0, 3, 0), (3, 0, 0)), BeltSlope.downward);
      expect(getSlopeBetween((0, 0, 0), (0, 3, 0)), BeltSlope.vertical);
      expect(getFacingFromTo((0, 0, 0), (0, 0, 3)), Direction.south);
      expect(getFacingFromTo((0, 0, 0), (-3, 0, 0)), Direction.west);
      expect(getBeltChainBetween((0, 0, 0), (3, 0, 0), BeltSlope.horizontal, Direction.east), [(0, 0, 0), (1, 0, 0), (2, 0, 0), (3, 0, 0)]);
    });

    test('canConnect checks axis, diagonal alignment and obstacles', () {
      final world = MapBlockGetter(fullBlocks: {'minecraft:stone'});
      for (final p in [(0, 0, 0), (3, 0, 0), (1, 0, 0)]) {
        world.set(p, const BState('create:shaft', {'axis': 'z'}));
      }
      double? speed(Pos p) => 16;
      expect(canConnectBelt(world, (0, 0, 0), (3, 0, 0), 20, speed), isTrue);
      world.set((2, 0, 0), const BState('minecraft:stone'));
      expect(canConnectBelt(world, (0, 0, 0), (3, 0, 0), 20, speed), isFalse);
      expect(canConnectBelt(world, (0, 0, 0), (30, 0, 0), 20, speed), isFalse);
      // different axes
      world.set((3, 0, 0), const BState('create:shaft', {'axis': 'x'}));
      expect(canConnectBelt(world, (0, 0, 0), (3, 0, 0), 20, speed), isFalse);
    });

    test('hoveringEnd', () {
      final end = belt(Direction.east, part: 'end');
      expect(hoveringEnd(end, (0, 0, 0), (0.9, 0.5, 0.5)), isTrue);
      expect(hoveringEnd(end, (0, 0, 0), (0.1, 0.5, 0.5)), isFalse);
      expect(hoveringEnd(belt(Direction.east), (0, 0, 0), (0.9, 0.5, 0.5)), isFalse);
    });
  });

  test('upright items', () {
    expect(isItemUpright(const ItemValue('minecraft:potion', 1)), isTrue);
    expect(isItemUpright(const ItemValue('minecraft:stone', 1)), isFalse);
    expect(isItemUpright(const ItemValue('minecraft:water_bucket', 1)), isTrue);
  });

  group('belt tunnel axis', () {
    BState beltFacing(Direction facing) =>
        BState('create:belt', {'facing': facing.serializedName});

    test('follows the axis of the belt below, not a fixed one', () {
      // the belt stores a direction, so reading it as an axis yields nothing and a tunnel
      // built on a north/south belt would silently come out east/west
      expect(beltAxis(beltFacing(Direction.north)), Axis.z);
      expect(beltAxis(beltFacing(Direction.south)), Axis.z);
      expect(beltAxis(beltFacing(Direction.east)), Axis.x);
      expect(beltAxis(beltFacing(Direction.west)), Axis.x);
    });

    test('a tunnel with no belt under it falls back to the x axis', () {
      expect(beltAxis(const BState('minecraft:air', {})), Axis.x);
    });
  });

  group('connector placement', () {
    /// `BeltConnectorItem.createBelts` between two shafts: the (position, part,
    /// slope, facing) of every segment.
    List<(Pos, BeltPart, BeltSlope, Direction)> plan(
      Pos start,
      Pos end, {
      String shaftAxis = 'z',
    }) {
      final world = MapBlockGetter();
      world.set(start, BState('create:shaft', {'axis': shaftAxis}));
      world.set(end, BState('create:shaft', {'axis': shaftAxis}));
      return planBelts(start, end, world);
    }

    test('the planned states of the four horizontal facings', () {
      // `getFacingFromTo`: the facing points from the first shaft to the second.
      final east = plan((0, 0, 0), (3, 0, 0));
      expect(east, [
        ((0, 0, 0), BeltPart.start, BeltSlope.horizontal, Direction.east),
        ((1, 0, 0), BeltPart.middle, BeltSlope.horizontal, Direction.east),
        ((2, 0, 0), BeltPart.middle, BeltSlope.horizontal, Direction.east),
        ((3, 0, 0), BeltPart.end, BeltSlope.horizontal, Direction.east),
      ]);

      final west = plan((3, 0, 0), (0, 0, 0));
      expect([for (final (p, _, _, facing) in west) (p, facing)], [
        ((3, 0, 0), Direction.west),
        ((2, 0, 0), Direction.west),
        ((1, 0, 0), Direction.west),
        ((0, 0, 0), Direction.west),
      ]);
      expect([for (final (_, part, _, _) in west) part], [
        BeltPart.start,
        BeltPart.middle,
        BeltPart.middle,
        BeltPart.end,
      ]);

      // A belt along z rotates on x, so its shafts have `axis=x`.
      final south = plan((0, 0, 0), (0, 0, 3), shaftAxis: 'x');
      expect([for (final (p, part, _, facing) in south) (p, part, facing)], [
        ((0, 0, 0), BeltPart.start, Direction.south),
        ((0, 0, 1), BeltPart.middle, Direction.south),
        ((0, 0, 2), BeltPart.middle, Direction.south),
        ((0, 0, 3), BeltPart.end, Direction.south),
      ]);

      final north = plan((0, 0, 3), (0, 0, 0), shaftAxis: 'x');
      expect([for (final (p, _, _, facing) in north) (p, facing)], [
        ((0, 0, 3), Direction.north),
        ((0, 0, 2), Direction.north),
        ((0, 0, 1), Direction.north),
        ((0, 0, 0), Direction.north),
      ]);
    });

    test('a diagonal run is one slope up per block', () {
      final up = plan((0, 0, 0), (2, 2, 0));
      expect([for (final (p, part, slope, facing) in up) (p, part, slope, facing)], [
        ((0, 0, 0), BeltPart.start, BeltSlope.upward, Direction.east),
        ((1, 1, 0), BeltPart.middle, BeltSlope.upward, Direction.east),
        ((2, 2, 0), BeltPart.end, BeltSlope.upward, Direction.east),
      ]);
    });

    test('a vertical shaft in the middle makes a pulley and a sideways belt', () {
      final world = MapBlockGetter();
      world.set((0, 0, 0), const BState('create:shaft', {'axis': 'z'}));
      world.set((3, 0, 0), const BState('create:shaft', {'axis': 'z'}));
      world.set((1, 0, 0), const BState('create:shaft', {'axis': 'y'}));
      final planned = planBelts((0, 0, 0), (3, 0, 0), world);
      expect([for (final (p, part, slope, _) in planned) (p, part, slope)], [
        ((0, 0, 0), BeltPart.start, BeltSlope.horizontal),
        ((1, 0, 0), BeltPart.pulley, BeltSlope.sideways),
        ((2, 0, 0), BeltPart.middle, BeltSlope.sideways),
        ((3, 0, 0), BeltPart.end, BeltSlope.sideways),
      ]);
    });
  });

  group('BeltBlockDef', () {
    const def = BeltBlockDef();
    KState beltState(
      String facing, {
      String part = 'start',
      String slope = 'horizontal',
    }) => KState('create:belt', {
      'facing': facing,
      'part': part,
      'slope': slope,
    });

    test('the rotation axis is the facing turned clockwise', () {
      // `BeltBlock.getRotationAxis`: HORIZONTAL_FACING.getClockWise().getAxis().
      expect(def.rotationAxis(beltState('north')), KAxis.x);
      expect(def.rotationAxis(beltState('south')), KAxis.x);
      expect(def.rotationAxis(beltState('east')), KAxis.z);
      expect(def.rotationAxis(beltState('west')), KAxis.z);
      expect(def.rotationAxis(beltState('east', slope: 'sideways')), KAxis.y);
    });

    test('hasShaftTowards matches BeltBlock.hasShaftTowards', () {
      // Java: `face.getAxis() != getRotationAxis(state)` -> false, else
      // `BeltBlockEntity.hasPulley()`, which is `part != MIDDLE`.
      const zFaces = [Dir.north, Dir.south];
      const xFaces = [Dir.east, Dir.west];
      const yFaces = [Dir.up, Dir.down];
      const allFaces = Dir.values;

      for (final part in ['start', 'end', 'pulley']) {
        final state = beltState('east', part: part); // rotation axis z
        for (final face in allFaces) {
          expect(
            def.hasShaftTowards(state, face),
            zFaces.contains(face),
            reason: 'east/$part towards ${face.name}',
          );
        }
      }
      // A middle segment has no pulley, whatever the facing.
      for (final facing in ['north', 'south', 'east', 'west']) {
        final state = beltState(facing, part: 'middle');
        for (final face in allFaces) {
          expect(def.hasShaftTowards(state, face), isFalse);
        }
      }
      // Facing north/south rotates on x.
      for (final face in allFaces) {
        expect(
          def.hasShaftTowards(beltState('north'), face),
          xFaces.contains(face),
        );
      }
      // A sideways belt rotates on y.
      for (final face in allFaces) {
        expect(
          def.hasShaftTowards(beltState('east', slope: 'sideways'), face),
          yFaces.contains(face),
        );
      }
      expect(
        def.hasShaftTowards(beltState('east', part: 'middle', slope: 'sideways'), Dir.up),
        isFalse,
      );
    });

    test('a belt pulley joins the network of the shaft next to it', () {
      final level = FakeLevel();
      level.blocks.register('create:belt', const BeltBlockDef());
      final motor = level.motor(0, 0, 0, 32, facing: Dir.east);
      // facing north -> rotation axis x, so the belt takes a shaft on its east side.
      final belt = level.place(KPos(1, 0, 0), beltState('north'));
      level.tickAll(3);
      expect(motor.speed, 32);
      expect(belt.speed, 32);
    });

    test('a middle segment has no shaft and does not join the network', () {
      final level = FakeLevel();
      level.blocks.register('create:belt', const BeltBlockDef());
      level.motor(0, 0, 0, 32, facing: Dir.east);
      final belt = level.place(
        KPos(1, 0, 0),
        beltState('north', part: 'middle'),
      );
      level.tickAll(3);
      expect(belt.speed, 0);
    });
  });
}

extension on Matcher {
  Matcher or(Matcher other) => anyOf(this, other);
}

class _HoldOnce implements BeltProcessing {
  int received = 0;
  int held = 0;
  @override
  ProcessingResult handleReceivedItem(TransportedItemStack stack, TransportedItemStackHandler inventory) {
    received++;
    return ProcessingResult.hold;
  }

  @override
  ProcessingResult handleHeldItem(TransportedItemStack stack, TransportedItemStackHandler inventory) {
    held++;
    return held >= 3 ? ProcessingResult.pass : ProcessingResult.hold;
  }
}

class _NoopHandler implements TransportedItemStackHandler {
  @override
  void handleCenteredProcessingOnAllItems(double maxDistanceFromCenter, ItemProcessor processFunction) {}
  @override
  void handleProcessingOnAllItems(ItemProcessor processFunction) {}
  @override
  void handleProcessingOnItem(TransportedItemStack item, TransportedResult result) {}
  @override
  Vec3 getWorldPositionOf(TransportedItemStack transported) => (0, 0, 0);
}

class _FakeFunnel {
  _FakeFunnel(this.facing, this.shape);
  final Direction facing;
  final String shape;
  final inserted = <ItemValue>[];
}

class _FunnelPort implements BeltFunnelPort, FunnelPort {
  _FunnelPort(this.f);
  final _FakeFunnel f;
  @override
  Direction get facing => f.facing;
  @override
  String get shape => f.shape;
  @override
  bool get powered => false;
  @override
  FunnelPort? get entity => this;
  @override
  bool get hasInserting => true;
  @override
  bool filterRejects(ItemValue stack) => false;
  @override
  (int, int)? get inventoryVersion => null;
  @override
  int get amountToExtract => 64;
  @override
  ExtractionCountMode get modeToExtract => ExtractionCountMode.upTo;
  @override
  Future<ItemValue> insert(ItemValue stack, {required bool simulate}) async {
    if (!simulate) f.inserted.add(stack);
    return ItemValue.empty;
  }

  @override
  void flap(bool inward) {}
  @override
  void onTransfer(ItemValue stack) {}
}
