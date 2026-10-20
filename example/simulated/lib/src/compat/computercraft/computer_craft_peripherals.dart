// The CC: Tweaked compat of Simulated: which block entity gets which
// peripheral.
//
// Java's `ComputerCraftPeripherals` is a `SimModCompatibilityService` that
// `ServiceLoader` only runs when CC is loaded. The port has no `ServiceLoader`
// and `simulated` must not depend on `cc_tweaked`, so this is a plain [init]
// that fills a [SimPeripheralRegistry]; the CC adapter
// (`cc_tweaked/lib/src/compat/simulated_peripherals.dart`) calls it and hands
// the registry's answers to the computers.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.ComputerCraftPeripherals:12-47

import 'peripherals/altitude_sensor_peripheral.dart';
import 'peripherals/directional_link_peripheral.dart';
import 'peripherals/docking_connector_peripheral.dart';
import 'peripherals/gimbal_sensor_peripheral.dart';
import 'peripherals/linked_typewriter_peripheral.dart';
import 'peripherals/modulating_link_peripheral.dart';
import 'peripherals/name_plate_peripheral.dart';
import 'peripherals/nav_table_peripheral.dart';
import 'peripherals/optical_sensor_peripheral.dart';
import 'peripherals/swivel_bearing_peripheral.dart';
import 'peripherals/torsion_spring_peripheral.dart';
import 'peripherals/velocity_sensor_peripheral.dart';
import 'sim_block_entity_types.dart';
import 'sim_peripheral_registry.dart';
import 'wired/docking_connector_wired_element.dart';

/// `ComputerCraftPeripherals`.
abstract final class ComputerCraftPeripherals {
  /// `getModId`: the mod whose presence makes Java run [init].
  static const String modId = 'computercraft';

  /// `init`: registers every peripheral and the docking connector's wired
  /// element, in the order of the Java method.
  static void init(SimPeripheralRegistry registry) {
    registry.addPeripheral(
      SimBlockEntityTypes.altitudeSensor,
      (entity, direction) => entity is SimAltitudeSensorSource ? AltitudeSensorPeripheral(entity) : null,
    );
    registry.addPeripheral(
      SimBlockEntityTypes.gimbalSensor,
      (entity, direction) => entity is SimGimbalSensorSource ? GimbalSensorPeripheral(entity) : null,
    );
    registry.addPeripheral(
      SimBlockEntityTypes.navigationTable,
      (entity, direction) => entity is SimNavTableSource ? NavTablePeripheral(entity) : null,
    );
    registry.addPeripheral(
      SimBlockEntityTypes.linkedTypewriter,
      (entity, direction) => entity is SimLinkedTypewriterSource ? LinkedTypewriterPeripheral(entity) : null,
    );
    registry.addPeripheral(
      SimBlockEntityTypes.opticalSensor,
      (entity, direction) => entity is SimOpticalSensorSource ? OpticalSensorPeripheral(entity) : null,
    );
    registry.addPeripheral(
      SimBlockEntityTypes.swivelBearing,
      (entity, direction) => entity is SimSwivelBearingSource ? SwivelBearingPeripheral(entity) : null,
    );

    registry.addPeripheral(
      SimBlockEntityTypes.velocitySensor,
      (entity, direction) => entity is SimVelocitySensorSource ? VelocitySensorPeripheral(entity) : null,
    );

    registry.addPeripheral(
      SimBlockEntityTypes.directionalLinkedReceiver,
      (entity, direction) => entity is SimDirectionalLinkSource ? DirectionalLinkPeripheral(entity) : null,
    );
    registry.addPeripheral(
      SimBlockEntityTypes.modulatingLinkedReceiver,
      (entity, direction) => entity is SimModulatingLinkSource ? ModulatingLinkPeripheral(entity) : null,
    );

    registry.addPeripheral(
      SimBlockEntityTypes.dockingConnector,
      (entity, direction) => entity is SimDockingConnectorSource ? DockingConnectorPeripheral(entity) : null,
    );
    registry.addPeripheral(
      SimBlockEntityTypes.torsionSpring,
      (entity, direction) => entity is SimTorsionSpringSource ? TorsionSpringPeripheral(entity) : null,
    );
    registry.addPeripheral(
      SimBlockEntityTypes.nameplate,
      (entity, direction) => entity is SimNamePlateSource ? NamePlatePeripheral(entity) : null,
    );

    // `addWired(DOCKING_CONNECTOR, ...)`: no wired element on the side the
    // connector faces (it is the side it docks on), the element on the others.
    registry.addWired(SimBlockEntityTypes.dockingConnector, (entity, direction) {
      if (entity is SimDockingConnectorSource && direction == entity.facing) return null;
      return createDockingConnectorWiredElement();
    });
  }
}
