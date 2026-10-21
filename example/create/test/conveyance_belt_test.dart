import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/direction.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/common/vec_helper.dart';
import 'package:create/src/conveyance/behaviours/belt_interfaces.dart';
import 'package:create/src/conveyance/behaviours/item_forms.dart';
import 'package:create/src/conveyance/belt/belt_block_def.dart';
import 'package:create/src/conveyance/belt/belt_geometry.dart';
import 'package:create/src/conveyance/shapes.dart' show BeltShapes;
import 'package:create/src/conveyance/belt/belt_handlers.dart';
import 'package:create/src/conveyance/belt/belt_inventory.dart';
import 'package:create/src/conveyance/belt/belt_ports.dart';
import 'package:create/src/conveyance/belt/transported_item.dart';
import 'package:create/src/conveyance/items/item_data.dart';
import 'package:create/src/processing/common/stack.dart';
import 'package:create/src/processing/transport/transported_stack.dart' as pt;
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;
import 'package:create/src/kinetics/geometry.dart' show Dir, KAxis, KPos, KState;
import 'package:test/test.dart';

import 'kinetics_test_support.dart';

/// A straight horizontal belt along +x starting at (0, 0, 0).
class FakeBelt implements BeltEnvironment {
  FakeBelt({this.length = 4, this.speedValue = 32, this.horizontal = true});

  final int length;
  double speedValue;
  bool horizontal;
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
  bool get isHorizontal => horizontal;
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
  _registrationTests();
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

    test('a tick that moves an item marks the belt for a client update', () async {
      final env = FakeBelt();
      final inv = BeltInventory(env);
      inv.addItem(stackAt(0.5));
      await inv.tick(); // inserts and moves
      final afterFirstTick = env.updates;
      await inv.tick();
      expect(
        env.updates,
        greaterThan(afterFirstTick),
        reason:
            'the client cannot move the item itself, so every tick that '
            'moved it has to push a new update tag (Java only gets away '
            'without this because its client ticks the inventory too)',
      );
    });

    test('a held item is not pushed every tick', () async {
      final env = FakeBelt();
      final inv = BeltInventory(env);
      inv.addItem(stackAt(0.5));
      await inv.tick();
      final item = inv.items.single;
      item.locked = true; // held by a processing machine without a handler
      await inv.tick();
      final held = env.updates;
      await inv.tick();
      expect(env.updates, held, reason: 'a held item does not move');
      final fields = transportedItemPositionFields(item);
      expect(fields['Pos'], fields['PrevPos'], reason: 'and interpolates to itself');
    });

    test('a moved item serializes with a distinct Pos and PrevPos', () async {
      final env = FakeBelt();
      final inv = BeltInventory(env);
      inv.addItem(stackAt(0.5));
      await inv.tick();
      await inv.tick();

      // The values the update tag carries (`transportedItemToNbt`); the client lerps
      // PrevPos -> Pos, so equal values would render the item still.
      final fields = transportedItemPositionFields(inv.items.single);
      expect(fields['Pos'], closeTo(0.5 + 2 * 32 / 480, 1e-6));
      expect(fields['PrevPos'], closeTo(0.5 + 32 / 480, 1e-6));
      expect(fields['Pos'], isNot(fields['PrevPos']));
    });

    test('two samples ten ticks apart read the way the client lerps them', () async {
      // The animation ticket's decisive check, at the level of the update tag: sample the
      // serialized fields, run ten ticks, sample again. An item that does not move serializes
      // the same `Pos` twice; an item the client cannot interpolate serializes `PrevPos == Pos`
      // (`BeltRenderer.renderItem` lerps `PrevPos` -> `Pos`).
      final env = FakeBelt();
      final inv = BeltInventory(env);
      inv.addItem(stackAt(0.5));
      await inv.tick(); // inserts, and moves the item one step

      final before = transportedItemPositionFields(inv.items.single);
      final updatesBefore = env.updates;
      for (var i = 0; i < 10; i++) {
        await inv.tick();
      }
      final after = transportedItemPositionFields(inv.items.single);
      const step = 32 / 480;
      final beforePos = before['Pos']!;
      final afterPos = after['Pos']!;
      final afterPrevPos = after['PrevPos']!;

      expect(afterPos, closeTo(0.5 + 11 * step, 1e-6));
      expect(beforePos, closeTo(0.5 + step, 1e-6));
      expect(afterPos, greaterThan(beforePos), reason: 'the item has to move');
      expect(
        afterPrevPos,
        isNot(afterPos),
        reason: 'equal values render the item still',
      );
      expect(
        afterPrevPos,
        closeTo(beforePos + 9 * step, 1e-6),
        reason: 'PrevPos is the previous tick\'s Pos: the pair the client lerps',
      );
      expect(
        env.updates,
        updatesBefore + 10,
        reason: 'ten moving ticks push ten tags, or the client keeps the old pair',
      );
    });

    test('a re-centering item serializes with a distinct Offset and PrevOffset', () async {
      final env = FakeBelt();
      final inv = BeltInventory(env);
      final item = stackAt(0.5)
        ..angle = 0 // target side offset -1/6
        ..sideOffset = .1
        ..prevSideOffset = .1;
      inv.addItem(item);
      await inv.tick();

      final fields = transportedItemPositionFields(inv.items.single);
      expect(fields['PrevOffset'], closeTo(.1, 1e-6));
      expect(fields['Offset'], isNot(fields['PrevOffset']));
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

    test('a machine above the belt sees the live item, so its result applies', () async {
      // `BeltPressingCallbacks.whenItemHeld` calls
      // `handler.handleProcessingOnItem(transported, TransportedResult...)` with the object the
      // belt handed it, and `TransportedItemStackHandlerBehaviour.handleProcessingOnItem` matches
      // it by identity (`TransportedItemStackHandlerBehaviour.java:102-108`). Across the bridge
      // that only holds when the conversion keeps one form per item (`item_forms.dart`);
      // otherwise the result is dropped and the item on the belt never changes.
      final env = FakeBelt(length: 4);
      final inv = BeltInventory(env);
      final handler = _InventoryHandler(inv, 1);
      inv.addItem(stackAt(1.5));
      await inv.tick();
      final item = inv.items.single;

      // What `ProcessingBeltAdapter.handleHeldItem` does around the machine callback.
      final processing = toProcessing(item);
      live(() {
        ProcessingHandlerView(handler).handleProcessingOnItem(
          processing,
          pt.TransportedResult.convertTo(
            pt.TransportedItemStack(const PStack('minecraft:iron_plate', 1))
              ..beltPosition = item.beltPosition,
          ),
        );
      });
      copyBack(processing, item);
      await inv.tick();

      expect(
        inv.items.map((e) => e.stack.key),
        contains('minecraft:iron_plate'),
        reason: 'the machine result has to reach the belt, not be dropped by the identity test',
      );
      expect(inv.items.every((e) => e.stack.key != 'minecraft:stone'), isTrue);
    });

    test('a processing state written in place survives a result that does nothing', () {
      // `FanProcessing.applyProcessingTransported` sets `processedBy` / `processingTime` on the
      // item and returns `doNothing()`; `DepotBehaviour.applyToAllItems` (Java passes the live
      // `heldItem`, `DepotBehaviour.java:401`) has to keep that state, so the form is written back
      // before the "result changes nothing" check.
      final t = TransportedItemStack(ItemValue('minecraft:wet_sponge', 1));
      final processing = toProcessing(t);
      final stackBefore = processing.stack;
      final result = live(() {
        processing.processedBy = 'create:splashing';
        processing.processingTime += 25;
        return pt.TransportedResult.doNothing();
      });
      copyBack(processing, t);

      expect(result.didntChangeFrom(stackBefore), isTrue, reason: 'a fan result does nothing');
      expect(t.processedBy, 'create:splashing');
      expect(t.processingTime, 25);
    });

    test('a fan over a depot finishes its timer on the live item', () {
      // CV-02: `DepotBehaviour.applyToAllItems` runs the fan callback on the live `heldItem`
      // (`DepotBehaviour.java:394-403`). The fan's timer lives on the item
      // (`FanProcessing.applyProcessingTransported` restarts it whenever `processedBy` does not
      // match), so an item the depot only kept as a conversion copy would be re-timed on every
      // tick and never finish.
      final held = TransportedItemStack(ItemValue('minecraft:wet_sponge', 1))
        ..beltPosition = .5;
      pt.TransportedResult? finished;
      for (var tick = 0; tick < 400 && finished == null; tick++) {
        // The body of `DepotBehaviour.applyToAllItems` around its callback.
        final processing = toProcessing(held);
        final stackBefore = processing.stack;
        final result = live(() => _fanTick(processing));
        copyBack(processing, held);
        if (result.didntChangeFrom(stackBefore)) continue;
        finished = result;
      }

      expect(
        finished,
        isNotNull,
        reason: 'the fan has to finish: the timer must survive the bridge',
      );
      expect(finished!.outputs.single.stack.key, 'minecraft:sponge');
    });

    test('the bridge keeps one processing form per belt item', () {
      final t = TransportedItemStack(ItemValue('minecraft:stone', 1));
      final first = toProcessing(t);
      expect(identical(toProcessing(t), first), isTrue);
      t.stack = ItemValue('minecraft:iron_ingot', 2);
      final again = toProcessing(t);
      expect(identical(again, first), isTrue);
      expect(again.stack.key, 'minecraft:iron_ingot');
      expect(again.stack.count, 2);
    });

    test('a sloped belt does not take the tunnel of a neighbouring horizontal one', () async {
      // `BeltTunnelInteractionHandler.getTunnelOnSegment` returns null unless the belt's slope is
      // horizontal (`BeltTunnelInteractionHandler.java:138-144`).
      final sloped = FakeBelt(length: 4)..horizontal = false;
      final slopedTunnel = _TunnelPort();
      sloped.tunnels[1] = slopedTunnel;
      final slopedInv = BeltInventory(sloped);
      slopedInv.addItem(stackAt(0.9));
      for (var i = 0; i < 20; i++) {
        await slopedInv.tick();
      }
      expect(slopedTunnel.flaps, isEmpty);

      final flat = FakeBelt(length: 4);
      final flatTunnel = _TunnelPort();
      flat.tunnels[1] = flatTunnel;
      final flatInv = BeltInventory(flat);
      flatInv.addItem(stackAt(0.9));
      for (var i = 0; i < 20; i++) {
        await flatInv.tick();
      }
      expect(flatTunnel.flaps, isNotEmpty);
    });
  });

  group('tunnel insertion', () {
    // `BeltBlockEntity.tryInsertingFromSide` (`BeltBlockEntity.java:497-515`): an insert that
    // reaches a belt with a distributing brass tunnel above it goes to the tunnel, not the belt.
    ItemValue ingot() => ItemValue('minecraft:iron_ingot', 1);

    test('a distributing brass tunnel takes the inserted stack', () {
      final belt = FakeBelt(length: 4);
      final tunnel = _TunnelPort(
        isBrass: true,
        hasDistributionBehaviour: true,
      );
      belt.tunnels[1] = tunnel;

      final took = tunnelTakesInsertion(
        belt,
        1,
        Direction.north,
        ingot(),
        simulate: false,
      );

      expect(took, isTrue);
      expect(tunnel.distributed.single.$1.key, 'minecraft:iron_ingot');
      expect(
        tunnel.distributed.single.$2,
        Direction.south,
        reason: 'the stack entered from the side it was inserted at',
      );
      expect(tunnel.flaps, [(Direction.south, true)]);
    });

    test('a simulation takes the stack without touching the tunnel', () {
      final belt = FakeBelt(length: 4);
      final tunnel = _TunnelPort(
        isBrass: true,
        hasDistributionBehaviour: true,
      );
      belt.tunnels[1] = tunnel;

      expect(
        tunnelTakesInsertion(belt, 1, Direction.north, ingot(), simulate: true),
        isTrue,
      );
      expect(tunnel.distributed, isEmpty);
      expect(tunnel.flaps, isEmpty);
    });

    test('a tunnel that cannot distribute leaves the stack to the belt', () {
      final belt = FakeBelt(length: 4);
      // An andesite tunnel, a brass one without a distribution behaviour, one already holding a
      // stack and one whose filter rejects the stack all let it ride on.
      final cases = {
        'andesite': _TunnelPort(
          isBrass: false,
          hasDistributionBehaviour: true,
        ),
        'no distribution': _TunnelPort(
          isBrass: true,
          hasDistributionBehaviour: false,
        ),
        'busy': _TunnelPort(
          isBrass: true,
          hasDistributionBehaviour: true,
          distributing: true,
        ),
        'filtered': _TunnelPort(
          isBrass: true,
          hasDistributionBehaviour: true,
          accepts: false,
        ),
      };
      for (final MapEntry(key: name, value: tunnel) in cases.entries) {
        belt.tunnels[1] = tunnel;
        expect(
          tunnelTakesInsertion(
            belt,
            1,
            Direction.north,
            ingot(),
            simulate: false,
          ),
          isFalse,
          reason: name,
        );
        expect(tunnel.distributed, isEmpty, reason: name);
        expect(tunnel.flaps, isEmpty, reason: name);
      }

      belt.tunnels.clear();
      expect(
        tunnelTakesInsertion(
          belt,
          1,
          Direction.north,
          ingot(),
          simulate: false,
        ),
        isFalse,
        reason: 'no tunnel above the segment',
      );
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

  group('belt chain resolution', () {
    /// The world a connector leaves behind: the states of [beltCreationStates] written at their
    /// positions (the shafts it replaced are gone).
    MapBlockGetter createdBelt(Pos start, Pos end) {
      final shafts = MapBlockGetter();
      shafts.set(start, const BState('create:shaft', {'axis': 'z'}));
      shafts.set(end, const BState('create:shaft', {'axis': 'z'}));
      final world = MapBlockGetter();
      for (final (at, state) in beltCreationStates(start, end, shafts)) {
        world.set(at, state);
      }
      return world;
    }

    test('two shafts make one belt: every segment resolves to the same controller', () {
      const start = (0, 0, 0);
      const end = (3, 0, 0);
      final world = createdBelt(start, end);
      const chain = [(0, 0, 0), (1, 0, 0), (2, 0, 0), (3, 0, 0)];

      for (final at in chain) {
        final resolved = resolveBeltChain(world, at);
        expect(resolved.status, BeltChainStatus.ok, reason: 'from $at');
        expect(resolved.controller, start, reason: 'from $at');
        expect(resolved.chain, chain, reason: 'from $at');
      }

      // The parts run start / middle / end along the chain the controller sees.
      expect(
        [for (final at in chain) world.stateAt(at).beltPart],
        [BeltPart.start, BeltPart.middle, BeltPart.middle, BeltPart.end],
      );

      // The controller's inventory spans the whole run: offset i of a belt of this length is
      // exactly segment i.
      final controllerState = world.stateAt(start);
      for (var i = 0; i < chain.length; i++) {
        expect(positionForOffset(start, controllerState, chain.length, i), chain[i]);
      }
    });

    test('the run has exactly one start and one end, so initBelt walks it once', () {
      // `initBelt` finds the controller by walking back while `nextSegmentPosition` says there is
      // a segment, and it stops at `part == start` (`BeltBlock.java:426-438`). Two starts would
      // split the run into two controllers; no start would make the walk leave the run.
      final world = createdBelt((0, 0, 0), (3, 0, 0));
      final parts = [for (final at in [(0, 0, 0), (1, 0, 0), (2, 0, 0), (3, 0, 0)]) world.stateAt(at).beltPart];
      expect(parts.where((p) => p == BeltPart.start).length, 1);
      expect(parts.where((p) => p == BeltPart.end).length, 1);
      expect(parts.first, BeltPart.start);
      expect(parts.last, BeltPart.end);
      // A segment placed with no controller at all (`controller == null`) is its own controller:
      // `controllerPos` falls back to the segment's own position, which is what a run without
      // `initBelt` looks like, one belt per block.
      expect(getBeltChain(world, (0, 0, 0)).length, 4);
    });

    test('the whole run is planned before anything is written', () {
      final shafts = MapBlockGetter()
        ..set((0, 0, 0), const BState('create:shaft', {'axis': 'z'}))
        ..set((2, 2, 0), const BState('create:shaft', {'axis': 'z'}));
      final batch = beltCreationStates((0, 0, 0), (2, 2, 0), shafts);
      expect([
        for (final (at, state) in batch)
          (at, state.beltPart, state.beltSlope, state.beltFacing, state.flag('waterlogged')),
      ], [
        ((0, 0, 0), BeltPart.start, BeltSlope.upward, Direction.east, false),
        ((1, 1, 0), BeltPart.middle, BeltSlope.upward, Direction.east, false),
        ((2, 2, 0), BeltPart.end, BeltSlope.upward, Direction.east, false),
      ]);
    });

    test('a vertical run resolves the same way', () {
      final world = MapBlockGetter();
      world.set((0, 0, 0), const BState('create:shaft', {'axis': 'z'}));
      world.set((0, 3, 0), const BState('create:shaft', {'axis': 'z'}));
      final states = MapBlockGetter();
      for (final (at, state) in beltCreationStates((0, 0, 0), (0, 3, 0), world)) {
        states.set(at, state);
      }
      final resolved = resolveBeltChain(states, (0, 3, 0));
      expect(resolved.status, BeltChainStatus.ok);
      expect(resolved.controller, (0, 0, 0));
      expect(resolved.chain, [(0, 0, 0), (0, 1, 0), (0, 2, 0), (0, 3, 0)]);
    });

    test('a missing segment breaks the chain instead of making separate belts', () {
      final world = createdBelt((0, 0, 0), (3, 0, 0));
      world.set((2, 0, 0), BState.air);
      // Walking back from the end runs into the hole: Java destroys the block it started at.
      final fromEnd = resolveBeltChain(world, (3, 0, 0));
      expect(fromEnd.status, BeltChainStatus.broken);
      expect(fromEnd.controller, (3, 0, 0));
    });

    test('a lone segment is not a belt', () {
      final world = MapBlockGetter()
        ..set((0, 0, 0), const BState(beltKey, {
          'casing': 'false',
          'facing': 'east',
          'part': 'start',
          'slope': 'horizontal',
          'waterlogged': 'false',
        }));
      final resolved = resolveBeltChain(world, (0, 0, 0));
      expect(resolved.status, BeltChainStatus.broken);
      expect(resolved.controller, (0, 0, 0));
    });

    test('a chain that leaves the loaded area is left alone', () {
      final world = createdBelt((0, 0, 0), (3, 0, 0));
      final unloaded = _UnloadedBlockGetter(world, const {(2, 0, 0)});
      expect(resolveBeltChain(unloaded, (3, 0, 0)).status, BeltChainStatus.unloaded);
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

/// The belt's own [TransportedItemStackHandler]: what `BeltBlockEntity` exposes to the machines
/// above it (`handleCenteredProcessingOnAllItems` -> `BeltInventory.applyToEachWithin`).
class _InventoryHandler implements TransportedItemStackHandler {
  _InventoryHandler(this.inv, this.segment);

  final BeltInventory inv;
  final int segment;

  @override
  void handleCenteredProcessingOnAllItems(double maxDistanceFromCenter, ItemProcessor processFunction) =>
      inv.applyToEachWithin(segment + .5, maxDistanceFromCenter, processFunction);

  @override
  void handleProcessingOnAllItems(ItemProcessor processFunction) =>
      handleCenteredProcessingOnAllItems(.51, processFunction);

  @override
  void handleProcessingOnItem(TransportedItemStack item, TransportedResult result) =>
      handleCenteredProcessingOnAllItems(.51, (t) => identical(t, item) ? result : null);

  @override
  Vec3 getWorldPositionOf(TransportedItemStack transported) => (0, 0, 0);
}

/// `FanProcessing.applyProcessingTransported`'s shape: the timer is the item's own
/// `processedBy` / `processingTime`, restarted whenever the type does not match, and the result is
/// the washed stack once it runs out. (`fan_processing.dart` is a wasm-only module, so the test
/// spells the fan's behaviour out instead of importing it.)
pt.TransportedResult _fanTick(pt.TransportedItemStack t) {
  const type = 'create:splashing';
  if (t.processedBy != type) {
    t.processedBy = type;
    t.processingTime = 150;
    return pt.TransportedResult.doNothing();
  }
  if (t.processingTime-- > 0) return pt.TransportedResult.doNothing();
  return pt.TransportedResult.convertTo(
    pt.TransportedItemStack(const PStack('minecraft:sponge', 1))
      ..beltPosition = t.beltPosition,
  );
}

/// A belt tunnel above a segment that records what the belt does with it.
class _TunnelPort implements BeltTunnelPort {
  _TunnelPort({
    this.isBrass = false,
    this.hasDistributionBehaviour = false,
    this.distributing = false,
    this.accepts = true,
  });

  final flaps = <(Direction, bool)>[];
  final distributed = <(ItemValue, Direction?)>[];

  @override
  final bool isBrass;

  @override
  final bool hasDistributionBehaviour;

  /// Whether the tunnel already holds a stack (`getStackToDistribute` is not empty).
  final bool distributing;

  /// What `testFlapFilter` answers.
  final bool accepts;

  @override
  Pos get position => (1, 1, 0);

  @override
  bool get canTakeItems => true;

  @override
  ItemValue getStackToDistribute() =>
      distributing ? ItemValue('minecraft:stone', 1) : ItemValue.empty;

  @override
  bool testFlapFilter(Direction side, ItemValue stack) => accepts;

  @override
  bool canInsert(Direction side, ItemValue stack) => true;

  @override
  void setStackToDistribute(ItemValue stack, Direction? enteredFrom) =>
      distributed.add((stack, enteredFrom));

  @override
  bool get isAndesiteJunction => false;

  @override
  Axis get horizontalAxis => Axis.x;

  @override
  bool hasFlap(Direction side) => false;

  @override
  void flap(Direction side, bool inward) => flaps.add((side, inward));

  @override
  void itemReceived(int amount) {}
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

/// A [BlockGetter] over a [MapBlockGetter] that reports some positions as unloaded (a chain
/// crossing a chunk border).
class _UnloadedBlockGetter extends BlockGetter {
  _UnloadedBlockGetter(this.inner, this.unloaded);

  final MapBlockGetter inner;
  final Set<Pos> unloaded;

  @override
  BState stateAt(Pos p) => inner.stateAt(p);

  @override
  bool isLoaded(Pos p) => !unloaded.contains(p) && inner.isLoaded(p);

  @override
  bool isFaceSturdy(Pos p, Direction face) => inner.isFaceSturdy(p, face);

  @override
  List<BlockBox> collisionBoxes(Pos p) => inner.collisionBoxes(p);

  @override
  bool supportShapeEmpty(Pos p) => inner.supportShapeEmpty(p);

  @override
  bool canBeReplaced(Pos p) => inner.canBeReplaced(p);

  @override
  bool hasTag(Pos p, String tag) => inner.hasTag(p, tag);

  @override
  bool isWater(Pos p) => inner.isWater(p);

}

// -- Registration -----------------------------------------------------------------------------

bool _isFullCube(BlockBox b) =>
    b.minX <= 0 && b.minY <= 0 && b.minZ <= 0 && b.maxX >= 1 && b.maxY >= 1 && b.maxZ >= 1;

void _registrationTests() {
  test('the belt registers a shape that is not a full cube', () {
    // `BeltBlock.getShape`/`getCollisionShape` are `BeltShapes`, never a full cube, and the host
    // derives a state's light opacity from the *collision* shape a block registers
    // (`derive_state_data`: `opacity = can_occlude && full_cube ? 15 : 0`). Registering the
    // manifest default (a full cube) made every belt occlude light like stone: its own cell lost
    // its sky light, and a client only sees that after a relog, when it loads the chunk's light
    // data instead of relighting the block itself.
    for (final shape in {
      'registeredShape': BeltShapes.registeredShape,
      'registeredCollision': BeltShapes.registeredCollision,
    }.entries) {
      expect(shape.value, isNotEmpty, reason: '${shape.key} is empty');
      expect(
        shape.value.any(_isFullCube),
        isFalse,
        reason: '${shape.key} is a full cube, which makes the belt occlude light',
      );
    }
  });
}
