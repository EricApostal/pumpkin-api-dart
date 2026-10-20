// The adapter between Simulated's peripherals and this package's.
//
// The registry and the peripherals themselves are tested in `simulated`; this
// checks the seam: types and methods cross unchanged, `attach`/`detach` reach
// the block entity's handler, the same block entity keeps the same adapter
// (`sameAs`), and a peripheral error becomes a Lua error.
import 'package:cc_tweaked/src/compat/simulated_peripherals.dart';
import 'package:cc_tweaked/src/lua/lua.dart' show LuaError;
import 'package:cc_tweaked/src/machine/peripheral.dart';
import 'package:simulated/src/api/sim_peripheral.dart' as sim;
import 'package:simulated/src/compat/computercraft/peripherals/swivel_bearing_peripheral.dart';
import 'package:test/test.dart';

void main() {
  group('SimulatedPeripheral', () {
    test('the type, the additional types and the methods cross unchanged', () {
      final adapter = SimulatedPeripheral(_Device());
      expect(adapter.type, 'swivel_bearing');
      expect(adapter.additionalTypes, {'simulated'});
      expect(adapter.methodNames, ['getTargetAngle', 'getTargetAngleRad']);
    });

    test('a call reaches the device with the same arguments', () {
      final device = _Device();
      final adapter = SimulatedPeripheral(device);
      final computer = _FakeAccess();
      expect(adapter.call(computer, 'getTargetAngle', const []), [45.0]);
      expect(device.lastMethod, 'getTargetAngle');
      expect(device.lastComputer?.computerId, 7);
      expect(device.lastComputer?.attachmentName, 'left');
    });

    test('a peripheral error becomes a Lua error with its message', () {
      final adapter = SimulatedPeripheral(_Device());
      expect(
        () => adapter.call(_FakeAccess(), 'explode', const []),
        throwsA(isA<LuaError>().having((e) => e.value, 'value', contains('no such method explode'))),
      );
    });

    test('attach and detach reach the device', () {
      final device = _Device();
      final adapter = SimulatedPeripheral(device);
      final computer = _FakeAccess();
      adapter.attach(computer);
      expect(device.attached, hasLength(1));
      expect(device.attached.single.attachmentName, 'left');

      adapter.detach(computer);
      expect(device.attached, isEmpty);
    });

    test('the same computer is the same access object for attach and detach', () {
      final device = _Device();
      final adapter = SimulatedPeripheral(device);
      final computer = _FakeAccess();
      adapter.attach(computer);
      final attached = device.attached.single;
      adapter.detach(computer);
      expect(device.detached.single, same(attached));
    });

    test('sameAs follows the device, not the adapter', () {
      // Java's `SimPeripheral.equals` is `iPeripheral == this`, so two
      // peripherals over one block entity are the same device; the driver
      // caches the adapter so a re-attach does not detach and attach again.
      final device = _Device();
      final first = SimulatedPeripheral(device);
      final second = SimulatedPeripheral(device);
      expect(first.sameAs(second), isTrue);
      expect(first.sameAs(SimulatedPeripheral(_Device())), isFalse);
    });
  });

  group('CcSimulatedPeripherals', () {
    setUp(CcSimulatedPeripherals.uninstall);
    tearDown(CcSimulatedPeripherals.uninstall);

    test('a swivel bearing resolves to its peripheral', () {
      final bearing = _Bearing(angle: 30);
      final adapter = CcSimulatedPeripherals.peripheralFor(bearing, 'simulated:swivel_bearing');
      expect(adapter, isNotNull);
      expect(adapter!.type, 'swivel_bearing');
      expect(adapter.call(_FakeAccess(), 'getTargetAngle', const []), [30.0]);
    });

    test('the same block entity on the same side keeps the same adapter', () {
      final bearing = _Bearing();
      final first = CcSimulatedPeripherals.peripheralFor(bearing, 'simulated:swivel_bearing', direction: 'south');
      final second = CcSimulatedPeripherals.peripheralFor(bearing, 'simulated:swivel_bearing', direction: 'south');
      expect(second, same(first));
      expect(first!.sameAs(second!), isTrue);
    });

    test('a block entity of another type gets nothing', () {
      expect(CcSimulatedPeripherals.peripheralFor(Object(), 'simulated:swivel_bearing'), isNull);
      expect(CcSimulatedPeripherals.peripheralFor(_Bearing(), 'simulated:altitude_sensor'), isNull);
    });
  });
}

final class _FakeAccess implements PeripheralAccess {
  @override
  int get computerId => 7;

  @override
  String get attachmentName => 'left';

  final List<(String, List<Object?>)> events = [];

  @override
  void queueEvent(String name, List<Object?> args) => events.add((name, args));
}

/// A device that records what the adapter does to it.
final class _Device implements sim.SimPeripheral {
  final List<sim.SimComputerAccess> attached = [];
  final List<sim.SimComputerAccess> detached = [];

  String? lastMethod;
  sim.SimComputerAccess? lastComputer;

  @override
  String get type => 'swivel_bearing';

  @override
  Set<String> get additionalTypes => const {'simulated'};

  @override
  List<String> get methodNames => const ['getTargetAngle', 'getTargetAngleRad'];

  @override
  List<Object?> call(sim.SimComputerAccess computer, String method, List<Object?> args) {
    lastMethod = method;
    lastComputer = computer;
    if (method == 'explode') throw const sim.SimPeripheralException('no such method explode');
    return const [45.0];
  }

  @override
  void attach(sim.SimComputerAccess computer) => attached.add(computer);

  @override
  void detach(sim.SimComputerAccess computer) {
    detached.add(computer);
    attached.remove(computer);
  }

  @override
  bool sameAs(sim.SimPeripheral other) => identical(this, other);
}

/// A block entity that only has the source interface the peripheral reads.
final class _Bearing implements SimSwivelBearingSource {
  _Bearing({this.angle = 0});

  final double angle;

  @override
  double get targetAngleDegrees => angle;
}
