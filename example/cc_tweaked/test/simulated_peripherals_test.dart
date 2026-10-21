// The adapter between Simulated's peripherals and this package's.
//
// The registry and the peripherals themselves are tested in `simulated`; this
// checks the seam: types and methods cross unchanged, `attach`/`detach` reach
// the block entity's handler, the same block entity keeps the same adapter
// (`sameAs`), and a peripheral error becomes a Lua error. The last group goes
// one step further out: the `peripheral` table the machine installs for a
// computer, run by a real Lua VM, so the calls here are the ones a program
// makes. The driver that finds the blocks around a computer is tested in
// `simulated_attach_test.dart`.
import 'package:cc_tweaked/src/compat/simulated_peripherals.dart';
import 'package:cc_tweaked/src/lua/lua.dart' show LuaError, LuaVm, installStandardLibrary;
import 'package:cc_tweaked/src/machine/api/peripheral_api.dart';
import 'package:cc_tweaked/src/machine/peripheral.dart';
import 'package:cc_tweaked/src/machine/side.dart';
import 'package:simulated/src/api/sim_peripheral.dart' as sim;
import 'package:simulated/src/compat/computercraft/attached_computer_handler.dart';
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

  // The contract the computer mod itself sees: the `peripheral` table the
  // machine installs for a computer (`buildPeripheralApi`, exactly what
  // `Computer._createMachine` puts in the globals) over the adapter, run by a
  // real Lua VM.
  //
  // The computer itself is not constructible here (`machine/computer.dart`
  // reaches `dart:_wasm` through the native Lua machine, and `CcService` needs
  // the host's data folder). [_Computer] is the same shape of the two things
  // the table asks for: `PeripheralLookup.attached(side)` and the
  // `PeripheralAccess` a computer hands a peripheral.
  group('what a computer sees', () {
    setUp(CcSimulatedPeripherals.uninstall);
    tearDown(CcSimulatedPeripherals.uninstall);

    late _Computer computer;
    late _Device device;
    late LuaVm vm;
    late int computerId;

    setUp(() {
      computerId = 0;
      device = _Device();
      computer = _Computer(() => ++computerId);
      vm = LuaVm();
      installStandardLibrary(vm);
      vm.globals.setString('peripheral', buildPeripheralApi(computer));
    });

    /// A `peripheral.<name>(...)` call, as the Lua program makes it.
    List<Object?> call(String source) => vm.call(vm.load(source, '=prog'), const []);

    test('a peripheral of a Simulated block is present on its side', () {
      computer.attach(ComputerSide.left, SimulatedPeripheral(device));

      expect(call("return peripheral.isPresent('left')"), [true]);
      expect(call("return peripheral.isPresent('right')"), [false]);
      expect(call("return peripheral.getType('left')"), ['swivel_bearing', 'simulated']);
      expect(call("return peripheral.getType('right')"), [null]);
    });

    test('hasType accepts the main and the additional types', () {
      computer.attach(ComputerSide.left, SimulatedPeripheral(device));

      expect(call("return peripheral.hasType('left', 'swivel_bearing')"), [true]);
      expect(call("return peripheral.hasType('left', 'simulated')"), [true]);
      expect(call("return peripheral.hasType('left', 'monitor')"), [false]);
      expect(call("return peripheral.hasType('right', 'swivel_bearing')"), [null]);
    });

    test('getMethods lists the device methods, in order', () {
      computer.attach(ComputerSide.left, SimulatedPeripheral(device));

      expect(
        call('''
          local methods = peripheral.getMethods("left")
          return #methods, methods[1], methods[2]
        '''),
        [2.0, 'getTargetAngle', 'getTargetAngleRad'],
      );
    });

    test('call reaches the device with the computer access of that side', () {
      computer.attach(ComputerSide.left, SimulatedPeripheral(device));

      expect(call("return peripheral.call('left', 'getTargetAngle')"), [45.0]);
      // The device sees the computer it is attached to, under the side's name:
      // that is what `IComputerAccess` is for (`getID`, `getAttachmentName`).
      expect(device.lastComputer?.computerId, computerId);
      expect(device.lastComputer?.attachmentName, 'left');
    });

    test('arguments cross unchanged and several values come back', () {
      computer.attach(ComputerSide.left, SimulatedPeripheral(device));

      expect(call("return peripheral.call('left', 'getTargetAngleRad', 2, 'x')"), [45.0]);
      expect(device.lastArgs, [2.0, 'x']);
    });

    test('a method the device does not have fails the Lua call', () {
      computer.attach(ComputerSide.left, SimulatedPeripheral(device));

      expect(
        () => call("return peripheral.call('left', 'explode')"),
        throwsA(isA<LuaError>().having((e) => '${e.value}', 'message', contains('no such method explode'))),
      );
    });

    test('a failed call is what pcall sees, with the side and the method', () {
      computer.attach(ComputerSide.left, SimulatedPeripheral(device));

      expect(
        call('''
          local ok, err = pcall(peripheral.call, "left", "explode")
          return ok, err
        ''').first,
        false,
      );
      expect(call('''
          local ok, err = pcall(peripheral.call, "left", "explode")
          return err
        ''').first, contains('no such method explode'));
    });

    test('calling a side without a peripheral is a Lua error', () {
      expect(
        () => call("return peripheral.call('left', 'getTargetAngle')"),
        throwsA(isA<LuaError>().having((e) => '${e.value}', 'message', contains('No peripheral attached'))),
      );
    });

    test('attach hands the device the access of that side', () {
      final adapter = SimulatedPeripheral(device);
      computer.attach(ComputerSide.left, adapter);
      expect(device.attached, hasLength(1));
      expect(device.attached.single.attachmentName, 'left');

      computer.detach(ComputerSide.left);
      expect(device.attached, isEmpty);
      expect(device.detached, hasLength(1));
      expect(call("return peripheral.isPresent('left')"), [false]);
    });

    test('an event of the block entity reaches the computer', () {
      // The event direction of the Java side: the block entity broadcasts
      // through its `AttachedComputerHandler`, which holds the access the
      // adapter gave it (`LinkedTypewriterBlockEntity.computerHandler`).
      final handler = AttachedComputerHandler();
      device.onAttach = handler.attach;
      device.onDetach = handler.detach;
      final adapter = SimulatedPeripheral(device);
      computer.attach(ComputerSide.left, adapter);

      handler.queueEvent('key', const [1, 2]);

      expect(computer.events, hasLength(1));
      expect(computer.events.single.$1, 'key');
      expect(computer.events.single.$2, const [1, 2]);
      // And only while the computer has the peripheral.
      computer.detach(ComputerSide.left);
      handler.queueEvent('key', const [3]);
      expect(computer.events, hasLength(1));
    });

    test('the peripheral is found by wrap through the same table', () {
      computer.attach(ComputerSide.left, SimulatedPeripheral(device));

      // `peripheral.wrap` is ROM Lua over `getMethods`/`call`; the two calls it
      // makes are the ones above.
      expect(call('''
          local methods = peripheral.getMethods("left")
          local names = {}
          for i = 1, #methods do names[i] = methods[i] end
          local first = peripheral.call("left", "getTargetAngle")
          return table.concat(names, ","), first
        '''), ['getTargetAngle,getTargetAngleRad', 45.0]);
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

  /// What the block entity does with the access it is given: the linked
  /// typewriter keeps it in its `AttachedComputerHandler`.
  void Function(sim.SimComputerAccess)? onAttach;
  void Function(sim.SimComputerAccess)? onDetach;

  String? lastMethod;
  sim.SimComputerAccess? lastComputer;
  List<Object?> lastArgs = const [];

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
    lastArgs = args;
    if (method == 'explode') throw const sim.SimPeripheralException('no such method explode');
    return const [45.0];
  }

  @override
  void attach(sim.SimComputerAccess computer) {
    attached.add(computer);
    onAttach?.call(computer);
  }

  @override
  void detach(sim.SimComputerAccess computer) {
    detached.add(computer);
    attached.remove(computer);
    onDetach?.call(computer);
  }

  @override
  bool sameAs(sim.SimPeripheral other) => identical(this, other);
}

/// The two things the `peripheral` table asks of a computer:
/// `PeripheralLookup.attached(side)`, and the access a peripheral is handed
/// when it is attached (`Computer._SideAccess`).
final class _Computer implements PeripheralLookup {
  _Computer(this._nextId);

  final int Function() _nextId;
  final Map<ComputerSide, (Peripheral, PeripheralAccess)> _sides = {};
  final List<(String, List<Object?>)> events = [];

  @override
  (Peripheral, PeripheralAccess)? attached(ComputerSide side) => _sides[side];

  /// `Computer.setPeripheral` for a computer that is on: the peripheral is
  /// attached with the access of its side.
  void attach(ComputerSide side, Peripheral peripheral) {
    final access = _Access(this, side, _nextId());
    _sides[side] = (peripheral, access);
    peripheral.attach(access);
  }

  /// `Computer.setPeripheral(side, null)`: detach, then drop.
  void detach(ComputerSide side) {
    final existing = _sides.remove(side);
    existing?.$1.detach(existing.$2);
  }
}

/// `Computer._SideAccess`: what a peripheral sees of the computer it is on.
final class _Access implements PeripheralAccess {
  final _Computer _computer;
  final ComputerSide _side;

  _Access(this._computer, this._side, this.computerId);

  @override
  final int computerId;

  @override
  String get attachmentName => _side.luaName;

  @override
  void queueEvent(String name, List<Object?> args) => _computer.events.add((name, args));
}

/// A block entity that only has the source interface the peripheral reads.
final class _Bearing implements SimSwivelBearingSource {
  _Bearing({this.angle = 0});

  final double angle;

  @override
  double get targetAngleDegrees => angle;
}
