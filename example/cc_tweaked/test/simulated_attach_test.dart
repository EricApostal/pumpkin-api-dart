// The attach driver of the Simulated compat: which block sits next to which
// side of a computer, and what `refresh`/`detachAt`/`detachAll` do to a
// computer's sides.
//
// The world and the computer are behind the two interfaces the algorithm asks
// for, so this drives the whole thing with fakes: one stands in for
// `SimulatedHost` (the block entity store of the world), one for `CcService`
// (the peripherals of one computer). The host halves of both are not reachable
// from a VM test (`SimulatedHost`'s implementation imports `sable`, and
// `CcService` needs the host's data folder), but neither has any decision in
// it: it forwards to these interfaces.
import 'package:cc_tweaked/src/compat/simulated_attach.dart';
import 'package:cc_tweaked/src/compat/simulated_peripherals.dart';
import 'package:cc_tweaked/src/machine/peripheral.dart';
import 'package:cc_tweaked/src/machine/side.dart';
import 'package:simulated/src/api/sim_peripheral.dart' as sim;
import 'package:simulated/src/compat/computercraft/peripherals/swivel_bearing_peripheral.dart';
import 'package:test/test.dart';

void main() {
  setUp(CcSimulatedPeripherals.uninstall);
  tearDown(CcSimulatedPeripherals.uninstall);

  group('the side of a block', () {
    test('every side has one neighbour, one step away', () {
      const computer = (4, 5, 6);
      for (final MapEntry(key: side, value: (offset, _)) in SimulatedAttach.neighbours.entries) {
        final block = (computer.$1 + offset.$1, computer.$2 + offset.$2, computer.$3 + offset.$3);
        expect(SimulatedAttach.sideTowards(computer, block), side, reason: side.name);
        expect(SimulatedAttach.neighbourOf(computer, side), block, reason: side.name);
      }
      expect(SimulatedAttach.neighbours, hasLength(6));
    });

    test('a block that is not next to the computer has no side', () {
      expect(SimulatedAttach.sideTowards((0, 0, 0), (0, 0, 0)), isNull);
      expect(SimulatedAttach.sideTowards((0, 0, 0), (1, 1, 0)), isNull);
      expect(SimulatedAttach.sideTowards((0, 0, 0), (2, 0, 0)), isNull);
    });

    test('the direction from the block towards the computer, for all six', () {
      // What the capability getter of the Java side receives, for a computer
      // that faces north (simulated_driver.dart documents the mapping).
      const computer = (0, 0, 0);
      final directions = {
        for (final MapEntry(key: side, value: (_, direction)) in SimulatedAttach.neighbours.entries)
          side: direction,
      };
      expect(directions, {
        ComputerSide.bottom: 'up',
        ComputerSide.top: 'down',
        ComputerSide.back: 'north',
        ComputerSide.front: 'south',
        ComputerSide.right: 'west',
        ComputerSide.left: 'east',
      });
      expect(SimulatedAttach.sideTowards(computer, SimulatedAttach.neighbourOf(computer, ComputerSide.left)),
          ComputerSide.left);
    });
  });

  group('refresh', () {
    test('attaches the peripheral of the block on the side it stands on', () {
      final world = _World()
        ..put('w', SimulatedAttach.neighbourOf((10, 64, 10), ComputerSide.left),
            'simulated:swivel_bearing', _Bearing(angle: 45));
      final target = _Target()..computers.add(7);

      expect(SimulatedAttach.refresh(world, target, 'w', (10, 64, 10), 7), 1);

      final attached = target.attachment(7, ComputerSide.left);
      expect(attached, isNotNull);
      expect(attached!.type, 'swivel_bearing');
      expect(attached.additionalTypes, isEmpty);
      expect(target.sidesWithPeripheral, [ComputerSide.left]);
    });

    test('attaches several sides and counts them', () {
      final world = _World()
        ..put('w', SimulatedAttach.neighbourOf((0, 0, 0), ComputerSide.left), 'simulated:swivel_bearing', _Bearing())
        ..put('w', SimulatedAttach.neighbourOf((0, 0, 0), ComputerSide.top), 'simulated:swivel_bearing', _Bearing());
      final target = _Target()..computers.add(1);

      expect(SimulatedAttach.refresh(world, target, 'w', (0, 0, 0), 1), 2);
      expect(target.sidesWithPeripheral, [ComputerSide.top, ComputerSide.left]);
    });

    test('the direction the registry is asked with follows the side', () {
      // A probe registration sees what `peripheralFor` was called with: the
      // direction from the block towards the computer.
      final probes = <(Object, String?)>[];
      CcSimulatedPeripherals.install();
      CcSimulatedPeripherals.registry.addPeripheral('test:probe', (entity, direction) {
        probes.add((entity, direction));
        return _Probe();
      });
      final entity = Object();
      final world = _World()..put('w', SimulatedAttach.neighbourOf((0, 0, 0), ComputerSide.back), 'test:probe', entity);
      final target = _Target()..computers.add(3);

      SimulatedAttach.refresh(world, target, 'w', (0, 0, 0), 3);

      expect(probes, [(entity, 'north')]);
      expect(target.attachment(3, ComputerSide.back), isNotNull);
    });

    test('a block entity the registry has no peripheral for is left alone', () {
      final world = _World()
        ..put('w', SimulatedAttach.neighbourOf((0, 0, 0), ComputerSide.top), 'simulated:gimbal_sensor', Object());
      final target = _Target()..computers.add(1);

      expect(SimulatedAttach.refresh(world, target, 'w', (0, 0, 0), 1), 0);
      expect(target.attached, isEmpty);
    });

    test('a neighbour whose entity is gone takes the peripheral away', () {
      final world = _World();
      final target = _Target()..computers.add(1);
      // A peripheral of ours, put there by an earlier refresh.
      world.put('w', (0, 1, 0), 'simulated:swivel_bearing', _Bearing());
      SimulatedAttach.refresh(world, target, 'w', (0, 0, 0), 1);
      expect(target.attachment(1, ComputerSide.top), isNotNull);

      world.remove('w', (0, 1, 0));
      expect(SimulatedAttach.refresh(world, target, 'w', (0, 0, 0), 1), 0);
      expect(target.attachment(1, ComputerSide.top), isNull);
      expect(target.detached, [ComputerSide.top]);
    });

    test('a peripheral that is not ours stays on its side', () {
      final world = _World();
      final target = _Target()..computers.add(1);
      final monitor = _Monitor();
      target.attachExternal(1, ComputerSide.top, monitor);

      SimulatedAttach.refresh(world, target, 'w', (0, 0, 0), 1);

      expect(target.attachment(1, ComputerSide.top), same(monitor));
      expect(target.detached, isEmpty);
    });

    test('a computer that is not loaded is not touched', () {
      final world = _World()
        ..put('w', (0, 1, 0), 'simulated:swivel_bearing', _Bearing());
      final target = _Target();

      expect(SimulatedAttach.refresh(world, target, 'w', (0, 0, 0), 1), 0);
      expect(target.attached, isEmpty);
    });

    test('the same block entity on the same side keeps one adapter', () {
      final world = _World()..put('w', (0, 1, 0), 'simulated:swivel_bearing', _Bearing());
      final target = _Target()..computers.add(1);

      SimulatedAttach.refresh(world, target, 'w', (0, 0, 0), 1);
      final first = target.attachment(1, ComputerSide.top);
      SimulatedAttach.refresh(world, target, 'w', (0, 0, 0), 1);

      // `CcSimulatedPeripherals` caches per entity and direction, so the
      // computer's `setPeripheral` sees the same device and does not detach and
      // re-attach (`Peripheral.sameAs`).
      expect(target.attachment(1, ComputerSide.top), same(first));
      expect(target.attachment(1, ComputerSide.top)!.sameAs(first!), isTrue);
    });

    test('a block of a world other than the computer is not a neighbour', () {
      final world = _World()..put('other', (0, 1, 0), 'simulated:swivel_bearing', _Bearing());
      final target = _Target()..computers.add(1);

      expect(SimulatedAttach.refresh(world, target, 'w', (0, 0, 0), 1), 0);
      expect(target.attached, isEmpty);
    });
  });

  group('detach', () {
    test('detachSide takes ours off one side', () {
      final target = _Target()..computers.add(1);
      final adapter = CcSimulatedPeripherals.peripheralFor(_Bearing(), 'simulated:swivel_bearing')!;
      target.attachExternal(1, ComputerSide.left, adapter);

      SimulatedAttach.detachSide(target, 1, ComputerSide.left);

      expect(target.attachment(1, ComputerSide.left), isNull);
      expect(target.detached, [ComputerSide.left]);
    });

    test('detachSide leaves a peripheral of the computer alone', () {
      final target = _Target()..computers.add(1);
      final monitor = _Monitor();
      target.attachExternal(1, ComputerSide.left, monitor);

      SimulatedAttach.detachSide(target, 1, ComputerSide.left);

      expect(target.attachment(1, ComputerSide.left), same(monitor));
      expect(target.detached, isEmpty);
    });

    test('detachAll takes every one of ours off, and only those', () {
      final target = _Target()..computers.add(1);
      target.attachExternal(1, ComputerSide.left, CcSimulatedPeripherals.peripheralFor(_Bearing(), 'simulated:swivel_bearing')!);
      target.attachExternal(1, ComputerSide.top, CcSimulatedPeripherals.peripheralFor(_Bearing(), 'simulated:swivel_bearing')!);
      final monitor = _Monitor();
      target.attachExternal(1, ComputerSide.right, monitor);

      SimulatedAttach.detachAll(target, 1);

      expect(target.sidesWithPeripheral, [ComputerSide.right]);
      expect(target.detached, containsAll([ComputerSide.left, ComputerSide.top]));
    });
  });
}

/// The world: block entities by world and position, like `SimulatedHost`'s
/// store.
final class _World implements PeripheralNeighbours {
  final Map<(String, int, int, int), (String, Object)> blocks = {};

  void put(String world, (int, int, int) pos, String typeKey, Object entity) =>
      blocks[(world, pos.$1, pos.$2, pos.$3)] = (typeKey, entity);

  void remove(String world, (int, int, int) pos) => blocks.remove((world, pos.$1, pos.$2, pos.$3));

  @override
  String? typeAt(String worldId, (int, int, int) pos) => blocks[(worldId, pos.$1, pos.$2, pos.$3)]?.$1;

  @override
  Object? entityAt(String worldId, (int, int, int) pos) => blocks[(worldId, pos.$1, pos.$2, pos.$3)]?.$2;
}

/// One computer's peripherals, like `CcService`'s `attachExternal` and friends.
final class _Target implements ExternalPeripheralTarget {
  final Set<int> computers = {};
  final Map<(int, ComputerSide), Peripheral> attached = {};
  final List<ComputerSide> detached = [];

  @override
  bool hasComputer(int id) => computers.contains(id);

  @override
  Peripheral? peripheral(int id, ComputerSide side) => attached[(id, side)];

  @override
  void attachExternal(int id, ComputerSide side, Peripheral peripheral) => attached[(id, side)] = peripheral;

  @override
  void detachExternal(int id, ComputerSide side) {
    attached.remove((id, side));
    detached.add(side);
  }

  Peripheral? attachment(int id, ComputerSide side) => attached[(id, side)];

  List<ComputerSide> get sidesWithPeripheral =>
      [for (final key in attached.keys) key.$2]..sort((a, b) => a.index.compareTo(b.index));
}

/// A device of the Simulated side that only carries state.
final class _Bearing implements SimSwivelBearingSource {
  _Bearing({this.angle = 0});

  final double angle;

  @override
  double get targetAngleDegrees => angle;
}

/// A peripheral of the computer itself (a monitor), which the compat must not
/// touch.
final class _Monitor implements Peripheral {
  @override
  String get type => 'monitor';

  @override
  Set<String> get additionalTypes => const {};

  @override
  List<String> get methodNames => const [];

  @override
  List<Object?> call(PeripheralAccess computer, String method, List<Object?> args) => const [];

  @override
  void attach(PeripheralAccess computer) {}

  @override
  void detach(PeripheralAccess computer) {}

  @override
  bool sameAs(Peripheral other) => identical(this, other);
}

/// A peripheral of a registration that only records how it was made.
final class _Probe implements sim.SimPeripheral {
  @override
  String get type => 'probe';

  @override
  Set<String> get additionalTypes => const {};

  @override
  List<String> get methodNames => const [];

  @override
  List<Object?> call(sim.SimComputerAccess computer, String method, List<Object?> args) => const [];

  @override
  void attach(sim.SimComputerAccess computer) {}

  @override
  void detach(sim.SimComputerAccess computer) {}

  @override
  bool sameAs(sim.SimPeripheral other) => identical(this, other);
}