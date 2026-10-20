// The CC: Tweaked compat: every peripheral called directly (no computer
// needed), the attach/detach handler, and the registry the host looks
// peripherals up in.
//
// The block entities these peripherals hang off are not all ported yet, so the
// tests use sources that stand in for them: the peripheral only ever talks to
// the source interface, which is the contract the block entity implements.
// The compat libraries are imported one by one: the barrel also exports the
// content, whose `create` imports reach `wasm_components`' embedder code, which
// only compiles for wasm. These files are pure.
import 'package:simulated/src/api/sim_peripheral.dart';
import 'package:simulated/src/compat/computercraft/attached_computer_handler.dart';
import 'package:simulated/src/compat/computercraft/computer_craft_peripherals.dart';
import 'package:simulated/src/compat/computercraft/peripherals/altitude_sensor_peripheral.dart';
import 'package:simulated/src/compat/computercraft/peripherals/directional_link_peripheral.dart';
import 'package:simulated/src/compat/computercraft/peripherals/docking_connector_peripheral.dart';
import 'package:simulated/src/compat/computercraft/peripherals/gimbal_sensor_peripheral.dart';
import 'package:simulated/src/compat/computercraft/peripherals/linked_typewriter_peripheral.dart';
import 'package:simulated/src/compat/computercraft/peripherals/modulating_link_peripheral.dart';
import 'package:simulated/src/compat/computercraft/peripherals/name_plate_peripheral.dart';
import 'package:simulated/src/compat/computercraft/peripherals/nav_table_peripheral.dart';
import 'package:simulated/src/compat/computercraft/peripherals/optical_sensor_peripheral.dart';
import 'package:simulated/src/compat/computercraft/peripherals/swivel_bearing_peripheral.dart';
import 'package:simulated/src/compat/computercraft/peripherals/torsion_spring_peripheral.dart';
import 'package:simulated/src/compat/computercraft/peripherals/velocity_sensor_peripheral.dart';
import 'package:simulated/src/compat/computercraft/sim_block_entity_types.dart';
import 'package:simulated/src/compat/computercraft/sim_peripheral_registry.dart';
import 'package:simulated/src/compat/computercraft/wired/docking_connector_wired_element.dart';
import 'package:simulated/src/compat/computercraft/wired/noop_docking_connector_wired_element.dart';
import 'package:test/test.dart';

void main() {
  group('peripheral types', () {
    test('every peripheral has the Java type and methods', () {
      final peripherals = <String, (SimPeripheral, List<String>)>{
        'altitude_sensor': (AltitudeSensorPeripheral(_Altitude()), ['getHeight', 'getAirPressure']),
        'velocity_sensor': (VelocitySensorPeripheral(_Velocity()), ['getVelocity']),
        'optical_sensor': (
          OpticalSensorPeripheral(_Optical()),
          ['hasHit', 'getDistance', 'getBlock', 'getRange', 'setRange'],
        ),
        'gimbal_sensor': (GimbalSensorPeripheral(_Gimbal()), ['getAngles', 'getAnglesRad']),
        'navigation_table': (NavTablePeripheral(_NavTable()), ['getRelativeAngle', 'getRelativeAngleRad']),
        'swivel_bearing': (SwivelBearingPeripheral(_Swivel()), ['getTargetAngle', 'getTargetAngleRad']),
        'torsion_spring': (
          TorsionSpringPeripheral(_TorsionSpring()),
          ['setLimit', 'getAngle', 'getAngleRad', 'getLimit', 'isRunning'],
        ),
        'directional_link': (DirectionalLinkPeripheral(_Directional()), ['getClosestAngle', 'getClosestAngleRad']),
        'modulating_link': (ModulatingLinkPeripheral(_Modulating()), ['getClosestDistance']),
        'name_plate': (NamePlatePeripheral(_NamePlate()), ['setName', 'getName']),
        'linked_typewriter': (LinkedTypewriterPeripheral(_Typewriter()), ['getPressedKeyCodes']),
        'docking_connector': (DockingConnectorPeripheral(_Docking()), ['getConnectedName']),
      };

      for (final MapEntry(key: type, value: (peripheral, methods)) in peripherals.entries) {
        expect(peripheral.type, type);
        expect(peripheral.methodNames, methods, reason: type);
        // `getAdditionalTypes` is the empty default in Java too.
        expect(peripheral.additionalTypes, isEmpty, reason: type);
      }
    });

    test('an unknown method is an error, not a silent nil', () {
      final peripheral = VelocitySensorPeripheral(_Velocity());
      expect(
        () => peripheral.call(_FakeComputer(1, 'left'), 'nope', const []),
        throwsA(isA<SimPeripheralException>()),
      );
    });

    test('sameAs is identity, like SimPeripheral.equals', () {
      final source = _Velocity();
      final first = VelocitySensorPeripheral(source);
      final second = VelocitySensorPeripheral(source);
      expect(first.sameAs(first), isTrue);
      expect(first.sameAs(second), isFalse);
    });
  });

  group('sensors', () {
    test('the altitude sensor reports the height and the pressure', () {
      final peripheral = AltitudeSensorPeripheral(_Altitude(height: 128, pressure: 0.75));
      final computer = _FakeComputer(3, 'top');
      expect(peripheral.call(computer, 'getHeight', const []), [128.0]);
      expect(peripheral.call(computer, 'getAirPressure', const []), [0.75]);
    });

    test('the velocity sensor reports the adjusted velocity', () {
      final peripheral = VelocitySensorPeripheral(_Velocity(speed: -2.5));
      expect(peripheral.call(_FakeComputer(3, 'top'), 'getVelocity', const []), [-2.5]);
    });

    test('the gimbal sensor reports both angles in degrees and radians', () {
      final peripheral = GimbalSensorPeripheral(_Gimbal(x: 1.5707963267948966, z: -1.5707963267948966));
      final computer = _FakeComputer(3, 'top');
      final degrees = peripheral.call(computer, 'getAngles', const []).single! as List<Object?>;
      expect(degrees[0], closeTo(90, 1e-9));
      expect(degrees[1], closeTo(-90, 1e-9));
      expect(peripheral.call(computer, 'getAnglesRad', const []), [
        [1.5707963267948966, -1.5707963267948966],
      ]);
    });

    test('the nav table reports the angle in degrees and radians', () {
      final peripheral = NavTablePeripheral(_NavTable(angle: 180));
      final computer = _FakeComputer(3, 'top');
      expect(peripheral.call(computer, 'getRelativeAngle', const []), [180.0]);
      expect((peripheral.call(computer, 'getRelativeAngleRad', const []).single! as double), closeTo(3.141592653589793, 1e-12));
    });

    test('the swivel bearing reports its target angle', () {
      final peripheral = SwivelBearingPeripheral(_Swivel(angle: 45));
      final computer = _FakeComputer(3, 'top');
      expect(peripheral.call(computer, 'getTargetAngle', const []), [45.0]);
      expect((peripheral.call(computer, 'getTargetAngleRad', const []).single! as double), closeTo(0.7853981633974483, 1e-12));
    });

    test('the directional link reports the angle to the closest link', () {
      final peripheral = DirectionalLinkPeripheral(_Directional(angle: 1.5707963267948966));
      final computer = _FakeComputer(3, 'top');
      expect((peripheral.call(computer, 'getClosestAngle', const []).single! as double), closeTo(90, 1e-9));
      expect(peripheral.call(computer, 'getClosestAngleRad', const []), [1.5707963267948966]);
    });

    test('the modulating link reports the distance to the closest link', () {
      final peripheral = ModulatingLinkPeripheral(_Modulating(distance: 12.5));
      expect(peripheral.call(_FakeComputer(3, 'top'), 'getClosestDistance', const []), [12.5]);
    });
  });

  group('optical sensor', () {
    test('a hit reports the block and the distance', () {
      final source = _Optical(hit: true, distance: 4.25, block: 'minecraft:stone', range: 16);
      final peripheral = OpticalSensorPeripheral(source);
      final computer = _FakeComputer(3, 'top');
      expect(peripheral.call(computer, 'hasHit', const []), [true]);
      expect(peripheral.call(computer, 'getDistance', const []), [4.25]);
      expect(peripheral.call(computer, 'getBlock', const []), ['minecraft:stone']);
      expect(peripheral.call(computer, 'getRange', const []), [16.0]);
    });

    test('no hit reports air', () {
      final peripheral = OpticalSensorPeripheral(_Optical());
      final computer = _FakeComputer(3, 'top');
      expect(peripheral.call(computer, 'hasHit', const []), [false]);
      expect(peripheral.call(computer, 'getBlock', const []), ['minecraft:air']);
    });

    test('setRange passes an integer to the block entity', () {
      final source = _Optical(range: 16);
      final peripheral = OpticalSensorPeripheral(source);
      expect(peripheral.call(_FakeComputer(3, 'top'), 'setRange', [8.0]), isEmpty);
      expect(source.range, 8);
    });

    test('setRange rejects a non-number and a fraction', () {
      final peripheral = OpticalSensorPeripheral(_Optical());
      final computer = _FakeComputer(3, 'top');
      expect(
        () => peripheral.call(computer, 'setRange', ['8']),
        throwsA(isA<SimPeripheralException>().having((e) => e.message, 'message', contains('number expected'))),
      );
      expect(
        () => peripheral.call(computer, 'setRange', [1.5]),
        throwsA(isA<SimPeripheralException>().having((e) => e.message, 'message', contains('integer representation'))),
      );
      expect(() => peripheral.call(computer, 'setRange', const []), throwsA(isA<SimPeripheralException>()));
    });
  });

  group('torsion spring', () {
    test('a static spring takes a new limit', () {
      final source = _TorsionSpring(limit: 90);
      final peripheral = TorsionSpringPeripheral(source);
      final computer = _FakeComputer(3, 'top');
      expect(peripheral.call(computer, 'isRunning', const []), [false]);
      peripheral.call(computer, 'setLimit', [120.0]);
      expect(source.limit, 120);
      expect(peripheral.call(computer, 'getLimit', const []), [120.0]);
    });

    test('a running spring ignores the limit', () {
      final source = _TorsionSpring(limit: 90, isStatic: false);
      final peripheral = TorsionSpringPeripheral(source);
      final computer = _FakeComputer(3, 'top');
      expect(peripheral.call(computer, 'isRunning', const []), [true]);
      peripheral.call(computer, 'setLimit', [120.0]);
      expect(source.limit, 90);
    });

    test('the angle is reported in degrees and radians', () {
      final peripheral = TorsionSpringPeripheral(_TorsionSpring(angle: 90));
      final computer = _FakeComputer(3, 'top');
      expect(peripheral.call(computer, 'getAngle', const []), [90.0]);
      expect((peripheral.call(computer, 'getAngleRad', const []).single! as double), closeTo(1.5707963267948966, 1e-12));
    });
  });

  group('name plate', () {
    test('reads and writes the name', () {
      final source = _NamePlate(name: 'Boat');
      final peripheral = NamePlatePeripheral(source);
      final computer = _FakeComputer(3, 'top');
      expect(peripheral.call(computer, 'getName', const []), ['Boat']);
      expect(peripheral.call(computer, 'setName', ['Ship']), isEmpty);
      expect(source.name, 'Ship');
      expect(peripheral.call(computer, 'getName', const []), ['Ship']);
    });

    test('setName needs a string', () {
      final peripheral = NamePlatePeripheral(_NamePlate());
      expect(
        () => peripheral.call(_FakeComputer(3, 'top'), 'setName', [42.0]),
        throwsA(isA<SimPeripheralException>().having((e) => e.message, 'message', contains('string expected'))),
      );
    });
  });

  group('docking connector', () {
    test('no pair is an empty name', () {
      final peripheral = DockingConnectorPeripheral(_Docking());
      expect(peripheral.call(_FakeComputer(3, 'top'), 'getConnectedName', const []), ['']);
    });

    test('a pair without a name is an empty name', () {
      final peripheral = DockingConnectorPeripheral(_Docking(paired: true));
      expect(peripheral.call(_FakeComputer(3, 'top'), 'getConnectedName', const []), ['']);
    });

    test('a named pair reports the sub-level name', () {
      final peripheral = DockingConnectorPeripheral(_Docking(paired: true, name: 'Airship'));
      expect(peripheral.call(_FakeComputer(3, 'top'), 'getConnectedName', const []), ['Airship']);
    });
  });

  group('AttachedComputerHandler', () {
    test('queues events to every attached computer', () {
      final handler = AttachedComputerHandler();
      final first = _FakeComputer(1, 'left');
      final second = _FakeComputer(2, 'right');
      handler
        ..attach(first)
        ..attach(second);
      handler.queueEvent('key', [65.0]);
      expect(first.events.single.$1, 'key');
      expect(first.events.single.$2, [65.0]);
      expect(second.events.single.$1, 'key');
      expect(second.events.single.$2, [65.0]);

      handler.detach(first);
      handler.queueEvent('key_released', const []);
      expect(first.events, hasLength(1));
      expect(second.events, hasLength(2));
    });

    test('attaching the same computer twice keeps one entry', () {
      final handler = AttachedComputerHandler();
      final computer = _FakeComputer(1, 'left');
      handler
        ..attach(computer)
        ..attach(computer);
      expect(handler.attachedComputers, [computer]);
    });

    test('a computer that detaches while an event is queued still gets it', () {
      final handler = AttachedComputerHandler();
      final late = _DetachingComputer(handler);
      final other = _FakeComputer(2, 'right');
      handler
        ..attach(late)
        ..attach(other);
      handler.queueEvent('key', const []);
      expect(late.events, hasLength(1));
      expect(other.events, hasLength(1));
      expect(handler.attachedComputers, [other]);
    });

    test('the typewriter peripheral forwards attach and detach', () {
      final source = _Typewriter(keys: [65, 66]);
      final peripheral = LinkedTypewriterPeripheral(source);
      final computer = _FakeComputer(4, 'back');

      expect(peripheral.call(computer, 'getPressedKeyCodes', const []), [
        [65.0, 66.0],
      ]);

      peripheral.attach(computer);
      expect(source.handler.attachedComputers, [computer]);
      source.handler.queueEvent('key', [65.0]);
      expect(computer.events.single.$1, 'key');
      expect(computer.events.single.$2, [65.0]);

      peripheral.detach(computer);
      expect(source.handler.attachedComputers, isEmpty);
    });
  });

  group('registry', () {
    SimPeripheralRegistry newRegistry() {
      final registry = SimPeripheralRegistry();
      ComputerCraftPeripherals.init(registry);
      return registry;
    }

    test('every peripheral type of the Java init is registered', () {
      final registry = newRegistry();
      expect(registry.peripheralTypes, [
        SimBlockEntityTypes.altitudeSensor,
        SimBlockEntityTypes.gimbalSensor,
        SimBlockEntityTypes.navigationTable,
        SimBlockEntityTypes.linkedTypewriter,
        SimBlockEntityTypes.opticalSensor,
        SimBlockEntityTypes.swivelBearing,
        SimBlockEntityTypes.velocitySensor,
        SimBlockEntityTypes.directionalLinkedReceiver,
        SimBlockEntityTypes.modulatingLinkedReceiver,
        SimBlockEntityTypes.dockingConnector,
        SimBlockEntityTypes.torsionSpring,
        SimBlockEntityTypes.nameplate,
      ]);
      expect(registry.wiredTypes, [SimBlockEntityTypes.dockingConnector]);
    });

    test('a block entity resolves to its peripheral', () {
      final registry = newRegistry();
      final bearing = _Swivel(angle: 30);
      final peripheral = registry.peripheralFor(SimBlockEntityTypes.swivelBearing, bearing);
      expect(peripheral, isA<SwivelBearingPeripheral>());
      expect(peripheral!.call(_FakeComputer(1, 'top'), 'getTargetAngle', const []), [30.0]);
    });

    test('a block entity of another type is not given a peripheral', () {
      final registry = newRegistry();
      expect(registry.peripheralFor(SimBlockEntityTypes.swivelBearing, _Velocity()), isNull);
      expect(registry.peripheralFor('simulated:not_a_block_entity', _Swivel()), isNull);
    });

    test('the registry is empty before init', () {
      final registry = SimPeripheralRegistry();
      expect(registry.hasPeripheral(SimBlockEntityTypes.swivelBearing), isFalse);
      expect(registry.peripheralFor(SimBlockEntityTypes.swivelBearing, _Swivel()), isNull);
    });

    test('the docking connector has no wired element on its facing side', () {
      final registry = newRegistry();
      final connector = _Docking(facing: 'north');
      expect(registry.wiredFor(SimBlockEntityTypes.dockingConnector, connector, direction: 'north'), isNull);
      expect(
        registry.wiredFor(SimBlockEntityTypes.dockingConnector, connector, direction: 'south'),
        isA<NoopDockingConnectorWiredElement>(),
      );
      // Without a side the Java getter sees `null != FACING`, so it returns the
      // element.
      expect(registry.wiredFor(SimBlockEntityTypes.dockingConnector, connector), isNotNull);
      expect(ccWiredElementAvailable, isFalse);
    });

    test('the noop wired element does nothing', () {
      const element = NoopDockingConnectorWiredElement();
      expect(() => element.connect(element), returnsNormally);
      expect(() => element.disconnect(element), returnsNormally);
      expect(element.remove, returnsNormally);
    });

    test('clear drops every registration', () {
      final registry = newRegistry()..clear();
      expect(registry.peripheralTypes, isEmpty);
      expect(registry.wiredTypes, isEmpty);
    });
  });
}

/// A computer that records the events it is sent.
final class _FakeComputer implements SimComputerAccess {
  @override
  final int computerId;

  @override
  final String attachmentName;

  final List<(String, List<Object?>)> events = [];

  _FakeComputer(this.computerId, this.attachmentName);

  @override
  void queueEvent(String name, List<Object?> args) => events.add((name, args));
}

/// A computer that detaches itself when it receives an event.
final class _DetachingComputer implements SimComputerAccess {
  final AttachedComputerHandler handler;
  final List<(String, List<Object?>)> events = [];

  _DetachingComputer(this.handler);

  @override
  int get computerId => 99;

  @override
  String get attachmentName => 'top';

  @override
  void queueEvent(String name, List<Object?> args) {
    events.add((name, args));
    handler.detach(this);
  }
}

final class _Altitude implements SimAltitudeSensorSource {
  _Altitude({this.height = 64, this.pressure = 1});

  final double height;

  final double pressure;

  @override
  double get worldHeight => height;

  @override
  double get airPressure => pressure;
}

final class _Velocity implements SimVelocitySensorSource {
  _Velocity({this.speed = 0});

  final double speed;

  @override
  double get adjustedVelocity => speed;
}

final class _Optical implements SimOpticalSensorSource {
  _Optical({this.hit = false, this.distance = 0, this.block = 'minecraft:air', this._range = 16});

  final bool hit;

  final double distance;

  final String block;

  int _range;

  @override
  bool get hasHit => hit;

  @override
  double get hitBlockDistance => distance;

  @override
  String get hitBlockKey => block;

  @override
  double get range => _range.toDouble();

  @override
  void setRange(int blocks) => _range = blocks;
}

final class _Gimbal implements SimGimbalSensorSource {
  _Gimbal({this.x = 0, this.z = 0});

  final double x;

  final double z;

  @override
  double get xAngle => x;

  @override
  double get zAngle => z;
}

final class _NavTable implements SimNavTableSource {
  _NavTable({this.angle = 0});

  final double angle;

  @override
  double get relativeAngle => angle;
}

final class _Swivel implements SimSwivelBearingSource {
  _Swivel({this.angle = 0});

  final double angle;

  @override
  double get targetAngleDegrees => angle;
}

final class _TorsionSpring implements SimTorsionSpringSource {
  _TorsionSpring({this.limit = 90, this.isStatic = true, this.angle = 0});

  int limit;

  final bool isStatic;

  @override
  final double angle;

  @override
  bool get isSpringStatic => isStatic;

  @override
  int get angleLimit => limit;

  @override
  void setAngleLimit(int value) => limit = value;
}

final class _Directional implements SimDirectionalLinkSource {
  _Directional({this.angle = 0});

  final double angle;

  @override
  double get angleToClosestLink => angle;
}

final class _Modulating implements SimModulatingLinkSource {
  _Modulating({this.distance = 0});

  final double distance;

  @override
  double get distanceToClosest => distance;
}

final class _NamePlate implements SimNamePlateSource {
  _NamePlate({this.name = ''});

  @override
  String name;

  @override
  void setName(String newName) => name = newName;
}

final class _Typewriter implements SimLinkedTypewriterSource {
  _Typewriter({this.keys = const []});

  final List<int> keys;

  final AttachedComputerHandler handler = AttachedComputerHandler();

  @override
  List<int> get pressedKeys => keys;

  @override
  AttachedComputerHandler get computerHandler => handler;
}

final class _Docking implements SimDockingConnectorSource {
  _Docking({this.paired = false, this.name, this.facing = 'north'});

  final bool paired;

  final String? name;

  @override
  final String facing;

  @override
  bool get hasOtherConnector => paired;

  @override
  String? get otherConnectorSubLevelName => name;
}
