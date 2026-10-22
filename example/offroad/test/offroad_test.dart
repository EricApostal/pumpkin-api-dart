// The Offroad model on the pure Dart VM: the tire codec, the sync payload's
// bytes, the borehead bearing's speed and stalling state machine, the mining
// manager, the wheel mount's suspension numbers, the rock cutting wheel's
// rotation rule and the config reader.
//
// Everything here is exercised without the host: `package:offroad/offroad.dart`
// has no `pumpkin_api` import.
import 'dart:math' as math;

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/common.dart' show Pos, vec3Zero;
import 'package:create/src/common/direction.dart' show Axis, Direction;
import 'package:create/src/kinetics/geometry.dart' show KPos, KState;
import 'package:create/src/kinetics/network.dart' show KineticNetwork;
import 'package:create/src/kinetics/node.dart'
    show KineticBlockRegistry, KineticLevel, KineticNode, KineticNodeMixin;
import 'package:create/src/kinetics/settings.dart' show KineticsSettings, KineticStressTable;
import 'package:offroad/offroad.dart';
import 'package:offroad/src/plugin/offroad_addon.dart';
import 'package:test/test.dart';

void main() {
  group('tire codec', () {
    test('the addon names the registries its content goes into', () {
      // Not cosmetic. The host numbers what a plugin registers by position
      // (`vanilla count + index`) and writes that id on the wire, so an addon that
      // declares its channels only leaves the client on its *own* order: the
      // registry is dropped from the sync, the host keeps handing out ids, and a
      // client that has the mod resolves each one to a different entry. Naming
      // `minecraft:item` and the rest is what makes the host send them.
      expect(const OffroadAddon().contentVerified, isTrue);
    });

    test('the presets are the Java numbers', () {
      expect(TireLike.smallTire.radius, 12 / 16);
      expect(TireLike.tire.radius, 15.5 / 16);
      expect(TireLike.largeTire.radius, 1 + 4 / 16);
      expect(TireLike.monstrousTire.radius, 2);
      expect(TireLike.rockCuttingWheel.radius, 0.8);
      expect(TireLike.rockCuttingWheel.model, 'offroad:block/rockcutting_wheel/wheel');
      expect(TireLike.mechanicalRoller.offset, (0.0, -0.5, 0.0));
    });

    test('the tire items resolve to their preset', () {
      expect(TireLike.forItem('offroad:small_tire'), TireLike.smallTire);
      expect(TireLike.forItem('offroad:tire'), TireLike.tire);
      expect(TireLike.forItem('offroad:large_tire'), TireLike.largeTire);
      expect(TireLike.forItem('offroad:monstrous_tire'), TireLike.monstrousTire);
      expect(TireLike.forItem('minecraft:stick'), isNull);
    });

    test('the json codec round-trips and keeps the defaults', () {
      for (final tire in [TireLike.smallTire, TireLike.rockCuttingWheel, TireLike.mechanicalRoller]) {
        expect(TireLike.fromMap(tire.toMap()), tire);
      }
      // A value written with only `radius` reads back the codec's defaults.
      final minimal = TireLike.fromMap({'radius': 2.5});
      expect(minimal.radius, 2.5);
      expect(minimal.rotation, (90.0, 0.0, 0.0));
      expect(minimal.offset, vec3Zero);
      expect(minimal.model, isNull);
      expect(minimal.minimumFriction, 0);
    });

    test('the network NBT value round-trips', () {
      for (final tire in [
        TireLike.smallTire,
        TireLike.largeTire,
        TireLike.rockCuttingWheel,
        TireLike.mechanicalRoller,
      ]) {
        final value = tire.toNbtValue();
        expect(TireLike.fromNbtValue(value), tire, reason: '$tire');
      }
    });

    test('the component codec is one network NBT tag', () {
      // `DataComponentType.Builder.persistent(Codec)` derives the network codec
      // with `ByteBufCodecs.fromCodec`.
      expect(tireComponentCodec.ops, hasLength(1));
      expect(tireComponentCodec.ops.single.kind.wireName, 'nbt');
    });
  });

  group('the sync payload', () {
    test('the byte layout is the Java one', () {
      final packet = MultiMiningSyncPacket.serverOutbound(-7);
      packet.add((5, 64, -3), 3.7);
      packet.add((6, 64, -3), 11);

      final bytes = MultiMiningSyncPacket.encode(packet);
      // int id, int count, then long pos + bool invalid (+ byte progress).
      expect(bytes.length, 4 + 4 + 8 + 1 + 1 + 8 + 1);
      expect(MultiMiningSyncPacket.codec.decode(bytes), isNotNull);
    });

    test('the round trip keeps the progress and the invalid marks', () {
      final packet = MultiMiningSyncPacket.serverOutbound(-1);
      packet.add((1, 2, 3), 0.9);
      packet.add((-1, 70, 8), 10);
      packet.add((100, -64, -100), 9.99);

      final decoded = MultiMiningSyncPacket.codec.decode(MultiMiningSyncPacket.encode(packet));
      expect(decoded.breakingId, -1);
      expect(decoded.entries, packet.entries);
      expect(decoded.entries[(1, 2, 3)]!.progressByte, 0);
      expect(decoded.entries[(-1, 70, 8)]!.invalid, isTrue);
      expect(decoded.entries[(100, -64, -100)]!.progressByte, 9);
    });

    test('an empty payload carries only its id', () {
      final packet = MultiMiningSyncPacket.serverOutbound(42);
      expect(MultiMiningSyncPacket.encode(packet).length, 8);
    });

    test('the channel and the version are the Java ones', () {
      expect(MultiMiningSyncPacket.channel, OffroadIds.boreheadSyncBlocksChannel);
      expect(MultiMiningSyncPacket.channel, 'offroad:borehead_sync_blocks');
      expect(offroadChannels, hasLength(1));
      expect(offroadChannels.single.version, OffroadIds.channelVersion);
      expect(offroadChannels.single.serverbound, isFalse);
      expect(offroadChannels.single.optional, isFalse);
    });
  });

  group('the borehead bearing state machine', () {
    BoreheadBearingLogic logic() {
      final l = BoreheadBearingLogic();
      OffroadConfig.reset();
      return l;
    }

    test('the search box matches the Java box SDF', () {
      const radius = 1.5;
      // The block at the origin is inside; six blocks away is outside.
      expect(BoreheadBearingLogic.inSearchBox(vec3Zero, 0, 0, 0, radius), isTrue);
      expect(BoreheadBearingLogic.inSearchBox(vec3Zero, 3, 0, 0, radius), isFalse);
      // The search radius grows with the config.
      final narrow = logic().candidatesFor(vec3Zero).toList();
      final wideLogic = logic();
      OffroadConfig.server.blocks.boreheadBearingSearchRadius = 4;
      final wide = wideLogic.candidatesFor(vec3Zero).toList();
      OffroadConfig.reset();
      expect(narrow, isNotEmpty);
      expect(wide.length, greaterThan(narrow.length));
      // Every candidate is inside the box, and the box is centred on the origin.
      for (final p in wide) {
        expect(BoreheadBearingLogic.inSearchBox(vec3Zero, p.$1, p.$2, p.$3, 4), isTrue);
      }
    });

    test('an uninitialized bearing is inactive, and a stalled one too', () {
      final l = logic();
      expect(l.isActive(speed: 32, removed: false), isFalse);
      l.initializeFromBlocks(2);
      expect(l.isActive(speed: 32, removed: false), isTrue);
      expect(l.isActive(speed: 0, removed: false), isFalse);
      expect(l.isActive(speed: 32, removed: true), isFalse);

      l.setStalled(true);
      expect(l.isStalled, isTrue);
      expect(l.isActive(speed: 32, removed: false), isFalse);
      l.startUnstalling();
      expect(l.stalled, isFalse);
      expect(l.stalledRecoveryTimer, OffroadConfig.server.blocks.boreheadBearingStallRecoveryTicks);
      expect(l.isStalled, isTrue, reason: 'the recovery timer counts down first');

      var sent = 0;
      final ticks = OffroadConfig.server.blocks.boreheadBearingStallRecoveryTicks;
      for (var i = 0; i < ticks; i++) {
        if (l.tickStallTimer()) sent++;
      }
      expect(sent, 1);
      expect(l.isStalled, isFalse);
    });

    test('the rotation speed divides the angular speed and lerps towards it', () {
      final l = logic();
      l.initializeFromBlocks(10);
      OffroadConfig.server.blocks.boreheadBearingRotationDivisor = 4;

      for (var i = 0; i < 2000; i++) {
        l.updateSpeed(isVirtual: false, isClientSide: false, angularSpeed: 64, speed: 64);
      }
      expect(l.rotationSpeed, closeTo(16, 0.01));
      OffroadConfig.reset();
    });

    test('a stalled bearing halves its target speed', () {
      final l = logic();
      l.initializeFromBlocks(10);
      for (var i = 0; i < 2000; i++) {
        l.updateSpeed(isVirtual: false, isClientSide: false, angularSpeed: 64, speed: 64);
      }
      final running = l.rotationSpeed;

      l.setStalled(true);
      for (var i = 0; i < 2000; i++) {
        l.updateSpeed(isVirtual: false, isClientSide: false, angularSpeed: 64, speed: 64);
      }
      expect(l.rotationSpeed, lessThan(running));
    });

    test('without rotation the speed decays to zero and stops lerping', () {
      final l = logic();
      l.initializeFromBlocks(10);
      l.rotationSpeed = 3;
      final step = l.updateSpeed(isVirtual: false, isClientSide: false, angularSpeed: 0, speed: 0);
      expect(step, BoreheadSpeedStep.running);
      l.rotationSpeed = 0.04;
      l.updateSpeed(isVirtual: false, isClientSide: false, angularSpeed: 0, speed: 0);
      expect(l.rotationSpeed, 0);
    });

    test('the mining speed scales with the rotation, the tags and the block count', () {
      final l = logic();
      l.initializeFromBlocks(10);
      l.rotationSpeed = 10;

      final plain = l.breakingSpeed(
        active: true,
        superEffective: false,
        effective: false,
        maxRotationSpeed: 256,
        speed: 64,
      );
      final effective = l.breakingSpeed(
        active: true,
        superEffective: false,
        effective: true,
        maxRotationSpeed: 256,
        speed: 64,
      );
      final superEffective = l.breakingSpeed(
        active: true,
        superEffective: true,
        effective: false,
        maxRotationSpeed: 256,
        speed: 64,
      );
      expect(plain, closeTo(0.5, 1e-9));
      expect(effective, closeTo(1.0, 1e-9));
      expect(superEffective, closeTo(10.0, 1e-9));
      expect(
        l.breakingSpeed(active: false, superEffective: false, effective: false, maxRotationSpeed: 256, speed: 64),
        0,
      );

      // Many blocks at once slow the mining down.
      for (var i = 0; i < 1000; i++) {
        l.visitedPositions.add((i, 0, 0));
      }
      expect(
        l.breakingSpeed(active: true, superEffective: false, effective: false, maxRotationSpeed: 256, speed: 64),
        lessThan(plain),
      );
    });

    test('the mining index is handed out once per rock cutter', () {
      final l = logic();
      l.initializeFromBlocks(2);
      expect(l.requestNewIndex(isRockCuttingWheel: true), 0);
      expect(l.requestNewIndex(isRockCuttingWheel: true), 1);
      expect(l.requestNewIndex(isRockCuttingWheel: true), -1);
      expect(l.requestNewIndex(isRockCuttingWheel: false), -1);

      l.updatePosition(0, (1.0, 2.0, 3.0));
      expect(l.centerMiningPositions.first, (1.0, 2.0, 3.0));
    });

    test('the saved data round-trips on both sides', () {
      final l = logic();
      l.initializeFromBlocks(3);
      l.updatePosition(1, (4.0, 5.0, 6.0));
      l.rotationSpeed = 12.5;
      l.setStalled(true);
      l.stalledRecoveryTimer = 4;

      final server = l.write(clientPacket: false);
      final restored = logic()..read(server, clientPacket: false);
      expect(restored.rotationSpeed, 12.5);
      expect(restored.stalled, isTrue);
      expect(restored.stalledRecoveryTimer, 4);
      expect(restored.initialized, isTrue);
      expect(restored.centerMiningPositions.length, 3);
      expect(restored.centerMiningPositions[1], (4.0, 5.0, 6.0));

      final client = l.write(clientPacket: true);
      final clientCopy = logic()..read(client, clientPacket: true);
      expect(clientCopy.clientRockCutters, 3);
      expect(clientCopy.centerMiningPositions, isEmpty);
    });

    test('the disassembly slowdown only starts once', () {
      final l = logic();
      l.initializeFromBlocks(12);
      l.rotationSpeed = 10;
      l.startDisassemblySlowdown(
        interpolatedAngle: 45,
        rotationSpeed: 10,
        facing: Direction.north,
        contraptionBlocks: {(0, 0, 0): 'offroad:borehead_bearing'},
      );
      expect(l.isSlowingDown, isTrue);
      final timer = l.slowdown.maxTime;
      l.startDisassemblySlowdown(
        interpolatedAngle: 90,
        rotationSpeed: 10,
        facing: Direction.north,
        contraptionBlocks: const {},
      );
      expect(l.slowdown.maxTime, timer, reason: 'the second call is ignored');
    });
  });

  group('the multi-mining manager', () {
    test('two suppliers average their speeds and the progress breaks the block', () async {
      final level = _Level({'minecraft:stone': 1.0});
      final manager = MultiMiningServerManager(() => 7, random: math.Random(1));
      final a = _Supplier(speed: 10, accepts: true);
      final b = _Supplier(speed: 30, accepts: true);

      expect(manager.addOrRefreshPos((0, 0, 0), a), isTrue);
      expect(manager.addOrRefreshPos((0, 0, 0), b), isFalse);
      expect(manager.breakingId, -7);

      var tick = 0;
      while (manager.breakingData.containsKey((0, 0, 0)) && tick < 100) {
        await manager.tick(level);
        tick++;
      }
      expect(tick, lessThan(100), reason: 'the block breaks');
      expect(level.destroyed, [(0, 0, 0)]);
      expect(manager.breakingData, isEmpty);
    });

    test('the drops go to the suppliers, the remainder to the world', () async {
      final level = _Level({'minecraft:stone': 0.1}, drops: [MinedDrop('minecraft:diamond', 5)]);
      final manager = MultiMiningServerManager(() => 1, random: math.Random(2));
      final taker = _Supplier(speed: 100, accepts: true, takes: 2);

      manager.addOrRefreshPos((3, 4, 5), taker);
      for (var i = 0; i < 50 && manager.breakingData.isNotEmpty; i++) {
        await manager.tick(level);
      }
      expect(taker.taken, 2);
      expect(level.popped, ['minecraft:diamondx3']);
    });

    test('a position with no active supplier stops and resets', () async {
      final level = _Level({'minecraft:stone': 1.0});
      final manager = MultiMiningServerManager(() => 1);
      final supplier = _Supplier(speed: 1, accepts: true);

      manager.addOrRefreshPos((0, 0, 0), supplier);
      await manager.tick(level);
      supplier.active = false;

      final packets = await manager.tick(level);
      expect(manager.breakingData, isEmpty);
      // The client is told that the position stopped: Java writes `-1`
      // (`MultiMiningServerManager.java:98`) and `invalid` is only
      // `progress >= 10` (`:235`), so the byte is 0xFF and the client reads it
      // as a negative progress.
      expect(packets, isNotEmpty);
      final entry = packets.first.entries.values.single;
      expect(entry.invalid, isFalse);
      expect(entry.progressByte, 0xFF);
    });

    test('a block that cannot be broken is dropped', () async {
      final level = _Level({'minecraft:bedrock': -1});
      final manager = MultiMiningServerManager(() => 1);
      manager.addOrRefreshPos((0, 0, 0), _Supplier(speed: 10, accepts: true));
      await manager.tick(level);
      expect(manager.breakingData, isEmpty);
      expect(level.destroyed, isEmpty);
    });
  });

  group('the wheel mount state machine', () {
    test('fudgeFriction gives friction to a slippery surface', () {
      expect(WheelMountLogic.fudgeFriction(0), closeTo(0.1, 1e-9));
      expect(WheelMountLogic.fudgeFriction(0.5), closeTo(0.55, 1e-9));
      expect(WheelMountLogic.fudgeFriction(1), 1);
      expect(WheelMountLogic.fudgeFriction(2), 2);
    });

    test('the steering yaw turns by a quarter of 30/45 of a radian', () {
      expect(WheelMountLogic.computeYaw(0), 0);
      expect(WheelMountLogic.computeYaw(15), -math.pi / 4 * (30 / 45));
      expect(WheelMountLogic.computeYaw(-15), math.pi / 4 * (30 / 45));
      expect(WheelMountLogic.steeringSignal(left: 7, right: 3), 4);
    });

    test('the extension is clamped and reports the lift', () {
      final logic = WheelMountLogic();
      // A cast that misses: 5 down, no hit.
      expect(logic.computeMaxExtension(tire: TireLike.tire, cast: WheelMountTerrainCast.miss, terrainFriction: 1), 0.65);
      expect(logic.liftedUp, isTrue);

      const cast = WheelMountTerrainCast(maxExtension: 1.0, minInteractingBlock: (0, 0, 0));
      expect(logic.computeMaxExtension(tire: TireLike.tire, cast: cast, terrainFriction: 0.5), closeTo(0.031, 0.01));
      expect(logic.liftedUp, isFalse);
      expect(logic.touchingFriction, closeTo(0.55, 1e-9));
    });

    test('a swap hands back what was mounted and consumes the new wheel', () {
      final logic = WheelMountLogic();
      var swap = logic.swapStacks(incomingItemKey: 'offroad:tire', incomingTire: TireLike.tire, hasInfiniteMaterials: false);
      expect(swap.switched, isTrue);
      expect(swap.returned, isNull);
      expect(swap.inserted, 'offroad:tire');
      expect(swap.consumed, isTrue);
      expect(logic.heldTire, TireLike.tire);

      swap = logic.swapStacks(
        incomingItemKey: 'offroad:small_tire',
        incomingTire: TireLike.smallTire,
        hasInfiniteMaterials: false,
      );
      expect(swap.returned, (itemKey: 'offroad:tire', count: 1));
      expect(logic.heldTire, TireLike.smallTire);

      // An item without the tire component is refused.
      swap = logic.swapStacks(incomingItemKey: 'minecraft:stick', incomingTire: null, hasInfiniteMaterials: false);
      expect(swap.switched, isFalse);
      expect(logic.heldTire, TireLike.smallTire);
    });

    test('an empty mount takes no wheel and an empty hand empties it', () {
      final logic = WheelMountLogic();
      var swap = logic.swapStacks(incomingItemKey: null, incomingTire: null, hasInfiniteMaterials: false);
      expect(swap.switched, isTrue);
      expect(swap.inserted, isNull);
      expect(swap.consumed, isFalse);

      logic.swapStacks(incomingItemKey: 'offroad:tire', incomingTire: TireLike.tire, hasInfiniteMaterials: false);
      swap = logic.swapStacks(incomingItemKey: null, incomingTire: null, hasInfiniteMaterials: false);
      expect(swap.returned, (itemKey: 'offroad:tire', count: 1));
      expect(logic.hasWheel, isFalse);
    });

    test('the suspension pushes along the terrain normal and damps along the wheel axes', () {
      final logic = WheelMountLogic()
        ..heldTire = TireLike.tire
        ..heldItemKey = 'offroad:tire'
        ..suspensionStrength = 10;

      final impulse = logic.computeImpulse(
        normalMass: 10,
        timeStep: 1 / 20,
        localVelocityY: -1,
        localVelocity: (0.0, -1.0, 0.0),
        normalD: (1.0, 0.0, 0.0),
        sideD: (0.0, 0.0, 1.0),
        rayHitNormal: (0.0, 1.0, 0.0),
        kineticSpeed: 20,
        brakeSignal: 0,
      );
      // Gravity pulls the body down, so the spring pushes it up.
      expect(impulse.force.$2, greaterThan(0));
      // A driven wheel pushes along its forward axis.
      expect(impulse.force.$1, greaterThan(0));
      expect(impulse.dampingForce, greaterThan(0));
      expect(impulse.brakingFrictionStrength, closeTo(0.075, 1e-9));
      expect(impulse.springLength, greaterThanOrEqualTo(0));

      // Braking turns the push into a braking force.
      final braked = logic.computeImpulse(
        normalMass: 10,
        timeStep: 1 / 20,
        localVelocityY: -1,
        localVelocity: (0.0, -1.0, 0.0),
        normalD: (1.0, 0.0, 0.0),
        sideD: (0.0, 0.0, 1.0),
        rayHitNormal: (0.0, 1.0, 0.0),
        kineticSpeed: 20,
        brakeSignal: 15,
      );
      expect(braked.brakingFrictionStrength, closeTo(0.375, 1e-9));
      expect(braked.force.$1, lessThan(impulse.force.$1));
    });

    test('the kinematic axis mirror flips on X', () {
      expect(WheelMountLogic.physicsKineticSpeed(speed: 32, axis: Axis.x), 32);
      expect(WheelMountLogic.physicsKineticSpeed(speed: 32, axis: Axis.z), -32);
      expect(WheelMountLogic.clientKineticSpeed(speed: 32, axis: Axis.x), -32);
      expect(WheelMountLogic.clientKineticSpeed(speed: 32, axis: Axis.z), 32);
      expect(WheelMountLogic.sidewaysNormal(Axis.x), (0, 0, 1));
      expect(WheelMountLogic.sidewaysNormal(Axis.z), (1, 0, 0));
    });

    test('the yaw chases the steering signal', () {
      final logic = WheelMountLogic();
      logic.tickChasingYaw(15);
      expect(logic.chasingYaw, closeTo(0.4 * WheelMountLogic.computeYaw(15), 1e-9));
      logic.tickChasingYaw(15);
      expect(logic.lastChasingYaw, isNot(0));
    });

    test('the client tick spins the wheel by the distance it travelled', () {
      final logic = WheelMountLogic()
        ..heldTire = TireLike.tire
        ..liftedUp = false;

      logic.tickClient(kineticSpeed: 30, brakeSignal: 0, translation: 1.0, hasSubLevel: false, maxExtension: 0.5);
      final free = logic.angularVelocity;

      logic.tickClient(kineticSpeed: 30, brakeSignal: 0, translation: 1.0, hasSubLevel: true, maxExtension: 0.5);
      expect(logic.angularVelocity, isNot(free));
      // Two pi radians per circumference: a tire of radius 15.5/16 rolling one
      // block turns about 1.03 turns.
      expect(logic.angularVelocity.abs(), closeTo(2 * math.pi * (1 / (2 * math.pi * TireLike.tire.radius)), 0.2));
    });

    test('the client read restores the steering signals only', () {
      final logic = WheelMountLogic();
      logic.read({'SteeringSignalStrength': 5, 'SteeringSignalStrengthLeft': 7, 'SteeringSignalStrengthRight': 2}, clientPacket: true);
      expect(logic.clientSteeringSignal, 5);
      expect(logic.clientSteeringSignalLeft, 7);
      expect(logic.clientSteeringSignalRight, 2);
      // A server-side read ignores the client fields.
      final server = WheelMountLogic()..read({'SteeringSignalStrength': 5}, clientPacket: false);
      expect(server.clientSteeringSignal, 0);
      expect(logic.write(clientPacket: true)['SteeringSignalStrength'], 0);
    });

    test('the render box grows with the wheel', () {
      expect(WheelMountLogic.renderBoundingBoxSize(null), 0);
      expect(WheelMountLogic.renderBoundingBoxSize(TireLike.monstrousTire), 3);
    });
  });

  group('the rock cutting wheel rotation rule', () {
    test('a wheel on the bearing axis rolls along the rotation', () {
      // localDir is horizontal and not vertical, so `facingUp` decides the
      // rotation axis: with `axisAlongFirst` false and a non-zero `stepX` it is
      // the Y axis, and a wheel whose X is non-zero rolls along the rotation.
      // On the centre line (y == 0) the roll compares the position against the
      // bearing speed.
      expect(
        RockCuttingWheelRotation.reverseRotation(
          bearingAxis: Axis.x,
          bearingSpeed: 10,
          localDir: Direction.east,
          axisAlongFirst: false,
          localPos: (4, 0, 0),
        ),
        isFalse,
      );
      expect(
        RockCuttingWheelRotation.reverseRotation(
          bearingAxis: Axis.x,
          bearingSpeed: -10,
          localDir: Direction.east,
          axisAlongFirst: false,
          localPos: (4, 0, 0),
        ),
        isTrue,
        reason: 'the bearing turns the other way',
      );
      // Off the centre line it rolls along the rotation, and the speed is not read.
      for (final speed in [10.0, -10.0]) {
        expect(
          RockCuttingWheelRotation.reverseRotation(
            bearingAxis: Axis.x,
            bearingSpeed: speed,
            localDir: Direction.east,
            axisAlongFirst: false,
            localPos: (4, 1, 0),
          ),
          isTrue,
          reason: 'speed $speed',
        );
      }
    });

    test('an outwards wheel never reverses (the Java TODO)', () {
      expect(
        RockCuttingWheelRotation.reverseRotation(
          bearingAxis: Axis.x,
          bearingSpeed: -10,
          localDir: Direction.up,
          axisAlongFirst: false,
          localPos: (0, 1, 0),
        ),
        isFalse,
      );
    });

    test('the search origin is one block along the facing', () {
      expect(RockCuttingWheelRotation.searchOrigin((1, 2, 3), Direction.north), (1.5, 2.5, 2.5));
      expect(RockCuttingWheelRotation.searchOrigin((1, 2, 3), Direction.up), (1.5, 3.5, 3.5));
    });
  });

  group('the directional axis placement', () {
    // `AbstractDirectionalAxisBlock.getStateForPlacement` (`:32-53`): the host's placement
    // rules turn the clicked face into `facing` (`PlacementRule.clickedFace('facing')`,
    // `getFacingForPlacement` = `context.getClickedFace()`, `:97-100`), and this is the
    // `axis_along_first` that goes with it — `sneaking != alongFirst`, which is why the
    // host had to place both blocks in the default state before: no placement rule source
    // combines the clicked face's axis with the player's look.
    test("the horizontal look direction is Java's `Direction.fromYRot`", () {
      expect(horizontalLookDirection(0), Direction.south);
      expect(horizontalLookDirection(90), Direction.west);
      expect(horizontalLookDirection(180), Direction.north);
      expect(horizontalLookDirection(270), Direction.east);
      expect(horizontalLookDirection(-90), Direction.east);
      expect(horizontalLookDirection(359), Direction.south);
    });

    test('a horizontal click takes the axis of the clicked face', () {
      // `alongFirst = faceAxis == Z`: a north or south face is along Z, an east or west
      // face is not. A plain click on a north face therefore gives `axis_along_first =
      // true`, which is *not* the default state (`false`) the port used to place.
      for (final sneaking in [false, true]) {
        for (final facing in [Direction.north, Direction.south]) {
          expect(
            axisAlongFirstForPlacement(
              facing: facing,
              horizontalLook: Direction.east,
              sneaking: sneaking,
            ),
            !sneaking,
            reason: '$facing, sneaking $sneaking',
          );
        }
        for (final facing in [Direction.east, Direction.west]) {
          expect(
            axisAlongFirstForPlacement(
              facing: facing,
              horizontalLook: Direction.north,
              sneaking: sneaking,
            ),
            sneaking,
            reason: '$facing, sneaking $sneaking',
          );
        }
      }
      expect(
        axisAlongFirstForPlacement(
          facing: Direction.north,
          horizontalLook: Direction.east,
          sneaking: false,
        ),
        isTrue,
      );
    });

    test("a vertical click takes the axis of the player's look", () {
      // `getAxisAlignmentForPlacement` (`:50-53`):
      // `context.getHorizontalDirection().getAxis() == Z` — a player looking along Z
      // (`north`/`south`) is the `alongFirst` case, so a plain click on a top or bottom
      // face then gives `axis_along_first = true`.
      for (final facing in [Direction.up, Direction.down]) {
        for (final look in [Direction.north, Direction.south]) {
          expect(
            axisAlongFirstForPlacement(facing: facing, horizontalLook: look, sneaking: false),
            isTrue,
            reason: '$facing, looking $look',
          );
          expect(
            axisAlongFirstForPlacement(facing: facing, horizontalLook: look, sneaking: true),
            isFalse,
          );
        }
        for (final look in [Direction.east, Direction.west]) {
          expect(
            axisAlongFirstForPlacement(facing: facing, horizontalLook: look, sneaking: false),
            isFalse,
            reason: '$facing, looking $look',
          );
          expect(
            axisAlongFirstForPlacement(facing: facing, horizontalLook: look, sneaking: true),
            isTrue,
          );
        }
      }
    });
  });

  group('the rock cutting wheel assembly rules', () {
    // `RockCuttingWheelBlock.java:12-33`: the wheel attaches towards every direction but
    // its own face and does not support what its face points at, so a contraption never
    // drags the block in front of a wheel into the structure.
    test('the wheel faces exactly one direction', () {
      for (final facing in Direction.values) {
        final state = BState(OffroadIds.rockCuttingWheel, {'facing': facing.serializedName});
        for (final direction in Direction.values) {
          expect(
            rockCuttingWheelFacesDirection(state, direction),
            direction == facing,
            reason: 'facing $facing, asked $direction',
          );
        }
      }
    });

    test('another block is not a wheel', () {
      const other = BState('minecraft:stone');
      expect(isRockCuttingWheel(other), isFalse);
      expect(rockCuttingWheelFacesDirection(other, Direction.north), isFalse);
      expect(rockCuttingWheelFacing(other), Direction.north, reason: 'the default of a state without a facing');
    });
  });

  group('the wheel mount stress', () {
    // Java's `WheelMountBlockEntity` does not override `calculateStressApplied`, so the
    // applied stress is the plain impact of `OffroadStress.setImpact(16.0)`
    // (`OffroadBlocks.java:97`) and the network multiplies it by the member's speed
    // (`KineticNetwork.getActualStressOf`) — hence `16·|speed|`.
    //
    // The port used to override it with `impact * |speed| / 16`, which the network then
    // scaled *again*: `16·speed²/16`, right at 16 RPM and four times too high at 64.
    test('the applied stress does not depend on the speed', () {
      final level = _FakeKineticLevel();
      level.stress.register(OffroadIds.wheelMount, impact: OffroadConfig.wheelMountImpact);
      final node = _FakeKineticNode(level, const KPos(0, 0, 0), const KState(OffroadIds.wheelMount));

      node.setSpeed(16);
      expect(node.calculateStressApplied(), 16);
      node.setSpeed(64);
      expect(node.calculateStressApplied(), 16, reason: 'the impact is the impact at any speed');
    });

    test('the network draws 16 per RPM at every speed', () {
      final level = _FakeKineticLevel();
      level.stress.register(OffroadIds.wheelMount, impact: OffroadConfig.wheelMountImpact);
      final node = _FakeKineticNode(level, const KPos(0, 0, 0), const KState(OffroadIds.wheelMount));
      final network = KineticNetwork(level, 1)..members[node] = node.calculateStressApplied();

      for (final speed in [16.0, 48.0, 64.0, -64.0]) {
        node.setSpeed(speed);
        expect(network.getActualStressOf(node), 16 * speed.abs(), reason: 'at $speed RPM');
      }
    });
  });

  group('the config', () {
    test('the defaults are the Java ones', () {
      final config = OffroadServerConfig();
      expect(config.blocks.boreheadBearingSearchRadius, 1.5);
      expect(config.blocks.boreheadBearingStallRecoveryTicks, 10);
      expect(config.blocks.boreheadBearingStallingEnabled, isTrue);
      expect(config.blocks.boreheadBearingRotationDivisor, 4);
      expect(OffroadConfig.boreheadBearingImpact, 8);
      expect(OffroadConfig.wheelMountImpact, 16);
      expect(OffroadStress.defaultCapacity, 0);
    });

    test('a config document is clamped and round-trips', () {
      final config = OffroadServerConfig.fromMap({
        'blocks': {
          'borehead_bearing_search_radius': 99,
          'borehead_bearing_stall_recovery_ticks': -4,
          'borehead_bearing_stalling_enabled': false,
          'borehead_bearing_rotation_divisor': 0,
        },
        'kinetics': {
          'stress': {
            'impact': {'borehead_bearing': 12.5},
          },
        },
      });
      expect(config.blocks.boreheadBearingSearchRadius, 10, reason: 'clamped to the max');
      expect(config.blocks.boreheadBearingStallRecoveryTicks, 0, reason: 'clamped to the min');
      expect(config.blocks.boreheadBearingStallingEnabled, isFalse);
      expect(config.blocks.boreheadBearingRotationDivisor, 1, reason: 'clamped to the min');
      expect(config.kinetics.stress.impactOf('offroad:borehead_bearing'), 12.5);
      expect(OffroadServerConfig.fromMap(config.toMap()).toMap(), config.toMap());
    });

    test('the block ids and their order are the Java ones', () {
      expect(OffroadIds.blocks, ['offroad:borehead_bearing', 'offroad:rockcutting_wheel', 'offroad:wheel_mount']);
      expect(OffroadIds.items, [
        'offroad:borehead_bearing',
        'offroad:rockcutting_wheel',
        'offroad:wheel_mount',
        'offroad:small_tire',
        'offroad:tire',
        'offroad:large_tire',
        'offroad:monstrous_tire',
      ]);
      expect(OffroadIds.blockEntityTypes, [
        'offroad:wheel_mount',
        'offroad:borehead_bearing',
        'offroad:rockcutting_wheel',
      ]);
      expect(OffroadIds.entityTypes, ['offroad:borehead_contraption_entity']);
      expect(OffroadIds.dataComponents, ['offroad:tire']);
      expect(OffroadIds.contraptionTypes, ['offroad:borehead_contraption']);
      expect(OffroadIds.items, hasLength(7));
      expect(tirePlacementErrorKeyOf, 'item.offroad.tire.placement_error');
    });

    test('the contraption refuses to assemble without wheels or storage', () {
      final contraption = BoreheadBearingContraption(Direction.north);
      expect(contraption.typeId, 'offroad:borehead_contraption');
      expect(contraption.rockCuttingWheelAmount, 0);
    });
  });
}

/// The translation key of the tire placement message, without the plugin-side
/// `TireItem` file (which pulls in `pumpkin_api`).
const String tirePlacementErrorKeyOf = 'item.offroad.tire.placement_error';

/// A [MultiMiningLevel] over a map of block keys.
final class _Level implements MultiMiningLevel {
  _Level(this.blocks, {this.drops = const []});

  final Map<String, double> blocks;
  final List<MinedDrop> drops;
  final List<Pos> destroyed = [];
  final List<String> popped = [];

  @override
  double hardnessAt(Pos pos) => blocks[blockKeyAt(pos)] ?? 0;

  @override
  String blockKeyAt(Pos pos) => blocks.keys.first;

  @override
  bool isBreakableAt(Pos pos) {
    final hardness = hardnessAt(pos);
    return hardness != -1 && blocks.isNotEmpty;
  }

  @override
  Future<List<MinedDrop>> destroyBlock(Pos pos) async {
    destroyed.add(pos);
    return drops;
  }

  @override
  Future<void> popResource(Pos pos, MinedDrop drop) async => popped.add('${drop.itemKey}x${drop.count}');
}

/// A [MultiMiningSupplier] the tests drive.
final class _Supplier implements MultiMiningSupplier {
  _Supplier({required this.speed, required this.accepts, this.takes = 0});

  final double speed;
  final bool accepts;
  final int takes;
  int taken = 0;
  bool active = true;

  @override
  double breakingSpeed(Pos pos, String blockKey) => speed;

  @override
  bool get isActive => active;

  @override
  Pos? get location => (0, 0, 0);

  @override
  int acceptItem(String itemKey, int count) {
    if (!accepts) return 0;
    final n = takes == 0 ? count : math.min(takes - taken, count);
    taken += n;
    return n;
  }
}

/// A [KineticLevel] with nothing in it but the stress table, for the stress test
/// (`create`'s own kinetic tests use one like this).
final class _FakeKineticLevel extends KineticLevel {
  @override
  final settings = const KineticsSettings();

  @override
  final blocks = KineticBlockRegistry();

  @override
  final KineticStressTable stress = KineticStressTable(const KineticsSettings());

  /// Unused: the stress test never looks a neighbour up.
  @override
  KineticNode? nodeAt(KPos pos) => null;

  @override
  KState stateAt(KPos pos) => KState.air;

  @override
  bool isLoaded(KPos pos) => true;

  @override
  void destroyBlock(KPos pos) {}
}

/// A kinetic node that carries the behaviour of `KineticBlockEntity`'s shared part
/// (`KineticNodeMixin`), so `calculateStressApplied` is the one the wheel mount inherits:
/// the plain impact of its block key.
final class _FakeKineticNode with KineticNodeMixin {
  @override
  final KPos kpos;

  @override
  final _FakeKineticLevel level;

  @override
  final KState blockState;

  _FakeKineticNode(this.level, this.kpos, this.blockState);

  @override
  void sendData() {}

  @override
  void markChanged() {}
}

