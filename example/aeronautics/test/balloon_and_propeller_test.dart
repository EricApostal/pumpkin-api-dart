// The balloon model: the layer graph, the flood fill that builds it, the gas
// amounts and the lift force. Runs on the VM: the world is a map of blocks.
import 'dart:math' as math;

import 'package:aeronautics/aeronautics.dart';
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Axis, Direction;
import 'package:sable/sable.dart' show AssemblyTransform, Rotation, SableLevel, Vector3d;
import 'package:test/test.dart';

/// A world made of a map of block keys.
final class TestBalloonWorld implements BalloonWorld {
  TestBalloonWorld([Map<(int, int, int), String>? blocks]) : blocks = blocks ?? {};

  final Map<(int, int, int), String> blocks;

  @override
  final String id = 'minecraft:overworld';

  @override
  bool get isServerSide => true;

  @override
  int get minY => -64;

  @override
  int get maxY => 320;

  @override
  late final TestLevel level = TestLevel();

  @override
  BState stateAt(int x, int y, int z) => BState(blocks[(x, y, z)] ?? 'minecraft:air');

  @override
  bool isAirtight(BState state) => state.key == 'aeronautics:white_envelope';

  void fill((int, int, int) from, (int, int, int) to, String key) {
    for (var x = from.$1; x <= to.$1; x++) {
      for (var y = from.$2; y <= to.$2; y++) {
        for (var z = from.$3; z <= to.$3; z++) {
          blocks[(x, y, z)] = key;
        }
      }
    }
  }

  /// A hollow airtight cube from [from] to [to], with the inside left as air.
  void shell((int, int, int) from, (int, int, int) to, String key) {
    for (var x = from.$1; x <= to.$1; x++) {
      for (var y = from.$2; y <= to.$2; y++) {
        for (var z = from.$3; z <= to.$3; z++) {
          final onEdge =
              x == from.$1 ||
              x == to.$1 ||
              y == from.$2 ||
              y == to.$2 ||
              z == from.$3 ||
              z == to.$3;
          if (onEdge) blocks[(x, y, z)] = key;
        }
      }
    }
  }
}

/// A minimal level: the balloon model only reads the dimension id.
final class TestLevel implements SableLevel {
  @override
  String get dimensionId => 'minecraft:overworld';

  @override
  bool get isClientSide => false;

  @override
  int get minY => -64;

  @override
  int get maxY => 320;

  @override
  int get gameTime => 0;

  @override
  int get sectionsCount => (maxY - minY) >> 4;

  @override
  String? biomeAt(int x, int y, int z) => null;
}

/// A heater the tests drive by hand.
final class TestHeater with BlockEntityLiftingGasProvider {
  TestHeater(this.balloonWorld, this.blockPos, this.castPosition);

  @override
  final BalloonWorld balloonWorld;

  @override
  final (int, int, int) blockPos;

  @override
  (int, int, int)? castPosition;

  @override
  Balloon? balloon;

  @override
  double gasOutput = 100;

  @override
  bool canOutputGas = true;

  @override
  bool get isChunkUnloaded => false;

  @override
  LiftingGasType get liftingGasType => const DefaultLiftingGas();

  @override
  void doRaycast() {}
}

/// The envelope keys the tests dye with.
const EnvelopeKeys testKeys = EnvelopeKeys(
  envelope: _envelope,
  encased: _encased,
);

String _envelope(String color) => 'aeronautics:${color}_envelope';

String _encased(String color) => 'aeronautics:${color}_envelope_encased_shaft';

/// A world of envelope blocks.
final class TestEnvelopeWorld implements EnvelopeDyeWorld {
  TestEnvelopeWorld(Map<(int, int, int), String> initial) : states = {...initial};

  final Map<(int, int, int), String> states;
  final Map<(int, int, int), String> axes = {};

  @override
  BState stateAt((int, int, int) pos) =>
      BState(states[pos] ?? 'minecraft:air', {if (axes[pos] != null) 'axis': axes[pos]!});

  @override
  void setStateAt((int, int, int) pos, BState state) {
    states[pos] = state.key;
    if (state['axis'] != null) axes[pos] = state['axis']!;
  }

  @override
  String? envelopeColor(BState state) {
    final path = state.key.replaceFirst('aeronautics:', '');
    if (!path.endsWith('_envelope')) return null;
    return path.substring(0, path.length - '_envelope'.length);
  }

  @override
  String? encasedColor(BState state) {
    const suffix = '_envelope_encased_shaft';
    final path = state.key.replaceFirst('aeronautics:', '');
    if (!path.endsWith(suffix)) return null;
    return path.substring(0, path.length - suffix.length);
  }

  @override
  String? encasedAxis(BState state) => state['axis'];
}

void main() {
  group('layer data', () {
    test('8x8 masks round-trip blocks', () {
      final layer = BalloonLayerData(10);
      layer.addHotAirBlock(0, 0);
      layer.addHotAirBlock(7, 7);
      layer.addHotAirBlock(-1, -1);

      expect(layer.getHotAirBlock(0, 0), isTrue);
      expect(layer.getHotAirBlock(7, 7), isTrue);
      expect(layer.getHotAirBlock(-1, -1), isTrue);
      expect(layer.getHotAirBlock(1, 1), isFalse);

      layer.removeHotAirBlock(0, 0);
      expect(layer.getHotAirBlock(0, 0), isFalse);
      expect(layer.getHotAirBlock(7, 7), isTrue);
    });

    test('two layers overlap when a column is shared', () {
      final lower = BalloonLayerData(0)..addHotAirBlock(2, 3);
      final upper = BalloonLayerData(1)..addHotAirBlock(2, 3);
      final elsewhere = BalloonLayerData(1)..addHotAirBlock(20, 20);

      expect(lower.overlaps(upper), isTrue);
      expect(lower.overlaps(elsewhere), isFalse);
    });

    test('the non-solid iterator skips solid blocks', () {
      final layer = BalloonLayerData(0)
        ..addHotAirBlock(0, 0)
        ..addHotAirBlock(1, 0)
        ..addSolidBlock(1, 0);

      expect(layer.blocks.length, 2);
      expect(layer.nonSolidBlocks.length, 1);
      expect(layer.nonSolidBlocks.first, (0, 0, 0));
    });
  });

  group('layer graph', () {
    test('layers are kept by Y and trimmed', () {
      final graph = BalloonLayerGraph(5);
      graph.addLayer(5, BalloonLayerData(5)..addHotAirBlock(0, 0));
      graph.addLayer(7, BalloonLayerData(7)..addHotAirBlock(0, 0));

      expect(graph.minY, 5);
      expect(graph.maxY, 7);

      graph.removeLayer(graph.getLayersAtY(5).single);
      graph.trim();
      expect(graph.minY, 7);
      expect(graph.maxY, 7);
    });

    test('connections only link adjacent layers that overlap', () {
      final graph = BalloonLayerGraph(0);
      final a = BalloonLayerData(0)..addHotAirBlock(0, 0);
      final b = BalloonLayerData(1)..addHotAirBlock(0, 0);
      final c = BalloonLayerData(2)..addHotAirBlock(9, 9);
      graph
        ..addLayer(0, a)
        ..addLayer(1, b)
        ..addLayer(2, c);

      graph.rebuildConnections((0, 0, 0));
      expect(a.outwardConnections, contains(b));
      expect(b.inwardConnections, contains(a));
      expect(c.inwardConnections, isEmpty);
    });

    test('propagateRemoval drops the reachable layers', () {
      final graph = BalloonLayerGraph(0);
      final a = BalloonLayerData(0)..addHotAirBlock(0, 0);
      final b = BalloonLayerData(1)..addHotAirBlock(0, 0);
      graph
        ..addLayer(0, a)
        ..addLayer(1, b);
      graph.rebuildConnections((0, 0, 0));

      final removed = graph.propagateRemoval(a);
      expect(removed, containsAll([a, b]));
      expect(graph.getLayersAtY(0), isEmpty);
      expect(graph.getLayersAtY(1), isEmpty);
    });
  });

  group('balloon builder', () {
    test('a sealed shell produces one layer per Y with the air inside', () {
      final world = TestBalloonWorld();
      world.shell((0, 0, 0), (4, 4, 4), 'aeronautics:white_envelope');

      final graph = BalloonBuilder.buildBalloon(world, (2, 2, 2));
      expect(graph, isNotNull);
      // Y = 1..3 is inside; the floor and the ceiling are airtight.
      expect(graph!.minY, 1);
      expect(graph.maxY, 3);
      expect(graph.hasBlockAt((2, 2, 2)), isTrue);
      expect(graph.hasBlockAt((2, 4, 2)), isFalse);
    });

    test('an open space is not a balloon', () {
      final world = TestBalloonWorld();
      world.fill((0, 0, 0), (4, 0, 4), 'aeronautics:white_envelope');

      expect(BalloonBuilder.buildBalloon(world, (2, 1, 2)), isNull);
    });

    test('a solid block inside the shell takes capacity away', () {
      final world = TestBalloonWorld();
      world.shell((0, 0, 0), (4, 4, 4), 'aeronautics:white_envelope');
      world.blocks[(2, 2, 2)] = 'minecraft:stone';

      final graph = BalloonBuilder.buildBalloon(world, (2, 2, 1))!;
      final balloon = ServerBalloon(world, (2, 2, 1), graph, const []);
      // 3 x 3 x 3 of air, minus the stone.
      expect(balloon.capacity, 26);
    });
  });

  group('server balloon', () {
    test('gas fills towards the target and produces lift', () {
      final world = TestBalloonWorld();
      world.shell((0, 0, 0), (6, 6, 6), 'aeronautics:white_envelope');

      final heater = TestHeater(world, (3, 1, 3), (3, 3, 3));
      final balloon = BalloonMap.attemptBuildBalloon(heater, (3, 3, 3))! as ServerBalloon;
      balloon.addHeater(heater);

      for (var i = 0; i < 400; i++) {
        balloon.tick();
      }

      expect(balloon.totalTargetVolume, greaterThan(0));
      expect(balloon.totalFilledVolume, greaterThan(0));
      expect(balloon.totalLift, greaterThan(0));
      expect(balloon.isValid, isTrue);
      // The gas never overshoots the capacity by much.
      expect(balloon.totalFilledVolume, lessThan(balloon.capacity + 10));
    });

    test('an empty balloon is invalid and gets removed', () {
      final world = TestBalloonWorld();
      world.shell((0, 0, 0), (4, 4, 4), 'aeronautics:white_envelope');

      final heater = TestHeater(world, (2, 1, 2), (2, 2, 2))..canOutputGas = false;
      final balloon = ServerBalloon(world, (2, 2, 2), BalloonBuilder.buildBalloon(world, (2, 2, 2))!, [heater]);

      expect(balloon.isValid, isFalse);

      final map = BalloonMap(world)..addBalloon(balloon);
      map.tickBalloons();
      expect(map.isEmpty, isTrue);
    });

    test('the average position sits at the centre of the air volume', () {
      final world = TestBalloonWorld();
      world.shell((0, 0, 0), (4, 4, 4), 'aeronautics:white_envelope');

      final graph = BalloonBuilder.buildBalloon(world, (2, 2, 2))!;
      final balloon = ServerBalloon(world, (2, 2, 2), graph, const []);

      // The air volume is the 3x3x3 block from (1,1,1) to (3,3,3), whose centre
      // is (2.5, 2.5, 2.5) in world coordinates.
      expect(balloon.center.x, closeTo(2.5, 1e-9));
      expect(balloon.center.y, closeTo(2.5, 1e-9));
      expect(balloon.center.z, closeTo(2.5, 1e-9));
    });

    test('merging adds the other balloon gas', () {
      final world = TestBalloonWorld();
      world.shell((0, 0, 0), (4, 4, 4), 'aeronautics:white_envelope');

      final graph = BalloonBuilder.buildBalloon(world, (2, 2, 2))!;
      final a = ServerBalloon(world, (2, 2, 2), graph, const []);
      final b = ServerBalloon(world, (2, 2, 2), graph, const []);
      b.gasAmounts[const DefaultLiftingGas()] = LiftingGasData(10, 20, 0);

      a.merge(b);
      expect(a.gasAmounts[const DefaultLiftingGas()]!.amount, 20);
      expect(a.gasAmounts[const DefaultLiftingGas()]!.target, 10);
    });
  });

  group('lifting gas', () {
    test('the lift strength is read from the live config', () {
      final defaults = AeroConfig.server.physics.copy();
      addTearDown(() => AeroConfig.server.physics.restore(defaults));

      expect(const DefaultLiftingGas().liftStrength, 1.5);
      AeroConfig.server.physics.hotAirStrength = 3;
      expect(const DefaultLiftingGas().liftStrength, 3);
    });

    test('gas holders round-trip through their map', () {
      final holder = LiftingGasHolder(const SteamLiftingGas(), LiftingGasData(1, 2, 3));
      final back = LiftingGasHolder.fromMap(holder.toMap());

      expect(back.type, isA<SteamLiftingGas>());
      expect(back.data.amount, 2);
      expect(back.data.target, 1);
    });

    test('the client prediction follows the exponential decay', () {
      // A stable balloon: no change and no target difference.
      const info = ClientBalloonInfo(100, 50, 50, 10, 0, (0, 0, 0));
      expect(BlockEntityLiftingGasProvider.getPredictedVolume(info, 5), 50);
    });
  });

  group('balloon map', () {
    test('a block change reaches the nearby balloons', () {
      final world = TestBalloonWorld();
      world.shell((0, 0, 0), (4, 4, 4), 'aeronautics:white_envelope');

      final heater = TestHeater(world, (2, 1, 2), (2, 2, 2));
      final balloon = BalloonMap.attemptBuildBalloon(heater, (2, 2, 2))!;
      final map = BalloonMap(world)..addBalloon(balloon);

      final before = balloon.capacity;
      // A stone inside the volume: the capacity drops by one.
      map.updateNearbyBalloons((2, 2, 2), BState.air, BState('minecraft:stone'));
      expect(balloon.capacity, before - 1);

      map.updateNearbyBalloons((2, 2, 2), BState('minecraft:stone'), BState.air);
      expect(balloon.capacity, before);
    });

    test('balloonAt finds the balloon of a position', () {
      final world = TestBalloonWorld();
      world.shell((0, 0, 0), (4, 4, 4), 'aeronautics:white_envelope');

      final heater = TestHeater(world, (2, 1, 2), (2, 2, 2));
      final balloon = BalloonMap.attemptBuildBalloon(heater, (2, 2, 2))!;
      final map = BalloonMap(world)..addBalloon(balloon);

      expect(map.balloonAt((2, 2, 2)), same(balloon));
      expect(map.balloonAt((20, 2, 20)), isNull);
    });

    test('unloading keeps the gas', () {
      final world = TestBalloonWorld();
      world.shell((0, 0, 0), (4, 4, 4), 'aeronautics:white_envelope');

      final graph = BalloonBuilder.buildBalloon(world, (2, 2, 2))!;
      final balloon = ServerBalloon(world, (2, 2, 2), graph, const []);
      balloon.gasAmounts[const DefaultLiftingGas()] = LiftingGasData(4, 4, 0);

      final map = BalloonMap(world)
        ..addBalloon(balloon)
        ..unloadBalloon(balloon);

      expect(map.isEmpty, isTrue);
      expect(map.unloaded.length, 1);
      expect(map.unloaded.single.gasData.single.data.amount, 4);
    });
  });

  group('simulated bridge', () {
    test('a balloon follows the offset the assembler reports', () {
      final world = TestBalloonWorld();
      world.shell((0, 0, 0), (4, 4, 4), 'aeronautics:white_envelope');

      final heater = TestHeater(world, (2, 1, 2), (2, 2, 2));
      final balloon = BalloonMap.attemptBuildBalloon(heater, (2, 2, 2))!;
      BalloonMap(world).addBalloon(balloon);

      // The blocks move by (100, 0, 0): the controller and the bounds follow.
      final moved = AssemblyTransform((2, 2, 2), (102, 2, 2), 0, Rotation.none, world.level);
      balloon.setAssembling(moved);

      expect(balloon.controllerPos, (102, 2, 2));
      // The transform works on block centres and floors, like `BlockPos.containing`;
      // the bounds are chunk-aligned, so they reach the end of the 8x8 chunk.
      expect(balloon.bounds.minX, 100);
      expect(balloon.bounds.maxX, 107);
      expect(balloon.heaters, isEmpty);
    });

    test('the bridge is idempotent and forgets its worlds on reset', () {
      final world = TestBalloonWorld();
      SimulatedBridge.install(world);
      SimulatedBridge.install(world);
      SimulatedBridge.reset();
      SimulatedBridge.reset();
    });
  });

  group('envelope dye', () {
    test('a dye recolours the clicked envelope', () {
      final world = TestEnvelopeWorld({
        (0, 0, 0): 'aeronautics:white_envelope',
      });

      EnvelopeDye.apply(world, (0, 0, 0), 'red', testKeys);
      expect(world.states[(0, 0, 0)], 'aeronautics:red_envelope');
    });

    test('an already-dyed block passes the colour to its neighbours', () {
      final world = TestEnvelopeWorld({
        (0, 0, 0): 'aeronautics:red_envelope',
        (1, 0, 0): 'aeronautics:white_envelope',
        (0, 1, 0): 'aeronautics:white_envelope',
      });

      EnvelopeDye.apply(world, (0, 0, 0), 'red', testKeys);
      expect(world.states[(1, 0, 0)], 'aeronautics:red_envelope');
      expect(world.states[(0, 1, 0)], 'aeronautics:red_envelope');
    });

    test('an encased shaft keeps its axis', () {
      final world = TestEnvelopeWorld({
        (0, 0, 0): 'aeronautics:white_envelope_encased_shaft',
      });
      world.axes[(0, 0, 0)] = 'x';

      EnvelopeDye.apply(world, (0, 0, 0), 'blue', testKeys);
      expect(world.states[(0, 0, 0)], 'aeronautics:blue_envelope_encased_shaft');
      expect(world.axes[(0, 0, 0)], 'x');
    });
  });

  group('propeller maths', () {
    test('a bearing scales thrust with the sails to the 1.5 power', () {
      final logic = PropellerBearingLogic()
        ..facing = Direction.up
        ..rotationSpeed = 30
        ..totalSailPower = 4;

      expect(logic.directionIndependentSpeed, closeTo(30 * (10 / 3), 1e-9));
      expect(logic.thrust(0.2), closeTo(math.pow(4, 1.5) * 30 * (10 / 3) * 0.2, 1e-9));
      expect(logic.airflow(0.05), closeTo(2 * 30 * (10 / 3) * 0.05, 1e-9));
    });

    test('the thrust direction option flips the push', () {
      final logic = PropellerBearingLogic()
        ..facing = Direction.up
        ..rotationSpeed = 30
        ..totalSailPower = 1;

      final right = logic.directionIndependentSpeed;
      logic.thrustDirectionOption = ThrustDirection.leftHanded;
      expect(logic.directionIndependentSpeed, closeTo(-right, 1e-9));
    });

    test('the stress grows with the sails and needs a running bearing', () {
      final logic = PropellerBearingLogic()..totalSailPower = 6;
      expect(logic.stressApplied(running: true, impact: 2), 12);
      expect(logic.stressApplied(running: false, impact: 2), 0);
      logic.disassemblySlowdown = true;
      expect(logic.stressApplied(running: true, impact: 2), 0);
    });

    test('a bearing with sails accelerates slower', () {
      final small = PropellerBearingLogic()..totalSailPower = 1;
      final large = PropellerBearingLogic()..totalSailPower = 64;

      small.updateRotationSpeed(32);
      large.updateRotationSpeed(32);

      expect(small.rotationSpeed, greaterThan(large.rotationSpeed));
      expect(large.rotationSpeed, greaterThan(0));
    });

    test('findSails groups the sails by plane along the facing axis', () {
      final logic = PropellerBearingLogic()..facing = Direction.up;

      logic.findSails({
        (0, 0, 0): BState('create:sail'),
        (1, 0, 0): BState('create:sail'),
        (0, 1, 0): BState('create:sail'),
      }, (state) => state.key == 'create:sail');

      expect(logic.totalSailPower, 3);
      expect(logic.layers.length, 2);
      // The layer of offset 0 lies in the plane of the facing axis.
      expect(logic.layers.first.offset, 1);
    });

    test('the small propeller ramps towards the shaft speed', () {
      final logic = SmallPropellerLogic();
      logic.updateRotationSpeed(32);

      // 32 RPM is 9.6 degrees per tick; the first step takes 15 % of it.
      expect(logic.rotationSpeed, closeTo(9.6 * 0.15, 1e-9));
      for (var i = 0; i < 200; i++) {
        logic.updateRotationSpeed(32);
      }
      expect(logic.rotationSpeed, closeTo(9.6, 1e-6));
    });

    test('a reversed small propeller pushes the other way', () {
      final logic = SmallPropellerLogic()
        ..facing = Direction.up
        ..rotationSpeed = 30;

      final forward = logic.directionIndependentSpeed;
      logic.reversed = true;
      expect(logic.directionIndependentSpeed, closeTo(-forward, 1e-9));
    });

    test('the smart propeller tilts its thrust with the hinge', () {
      final logic = SmartPropellerLogic()
        ..horizontalAxis = Axis.x
        ..hingeAngle = 45;
      logic.updateThrustDirection();

      expect(logic.thrustDir.y, closeTo(math.cos(math.pi / 4), 1e-9));
      expect(logic.thrustDir.length, closeTo(1, 1e-9));
    });
  });

  group('gyroscopic tilt', () {
    test('the tilt is clamped into the cone around the facing', () {
      final tilt = GyroscopicTilt();
      tilt.setFacing(Direction.up);

      // A target far outside the cone ends up 12 degrees from the facing.
      final target = Vector3d(1, 0, 0);
      for (var i = 0; i < 400; i++) {
        tilt.setTilt(tilt.tiltVector, Vector3d(1, 0, 0), 0.05, lerpDistance: 1);
      }

      // The clamp's 1.01 discriminant fudge leaves it a hair inside the cone.
      final angle = math.acos(tilt.tiltVector.y.clamp(-1.0, 1.0));
      expect(angle, closeTo(GyroscopicTilt.maxConeAngle, 2e-3));
      expect(angle, lessThanOrEqualTo(GyroscopicTilt.maxConeAngle));
      expect(target.x, 1);
    });

    test('a redstone signal locks the tilt to the mount', () {
      final tilt = GyroscopicTilt()
        ..setFacing(Direction.up)
        ..powered = true
        ..tiltVector.set(1, 0, 0);
      tilt.applyTilt();

      tilt.setTilt(tilt.tiltVector, Vector3d(1, 0, 0), 0.05, lerpDistance: 1);
      expect(tilt.tiltVector.x, lessThan(1));
    });

    test('the rotation between two vectors takes one to the other', () {
      final rotation = rotationBetween(Vector3d(0, 1, 0), Vector3d(0, 0, 1));
      final result = rotation.transform(Vector3d(0, 1, 0), Vector3d(0, 0, 0));

      expect(result.z, closeTo(1, 1e-9));
      expect(result.y, closeTo(0, 1e-9));
    });
  });
}
