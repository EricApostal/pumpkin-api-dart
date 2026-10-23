// The state properties and block keys of the Simulated blocks this port had not
// registered yet, shared by the four family files that build them.
//
// Every property here is the Java one, down to the value list: the value order is
// what numbers the states (`sim_java_order.dart` `SimPorted.stateProperties` pins
// the same lists), and a property with different values shifts the base state id of
// every block after it.
//
// Host: this file uses `pumpkin_api` (`CreateProps` is `package:create`'s).
//
// Java: the `createBlockStateDefinition` of each `content.blocks.*` class named at
// the property.
// ignore_for_file: implementation_imports
import 'package:create/src/core/blocks.dart' show CreateProps;
import 'package:pumpkin_api/pumpkin_api.dart';

/// The properties the port had not declared before.
abstract final class SimExtraProps {
  /// `AbstractDirectionalAxisBlock.AXIS_ALONG_FIRST_COORDINATE`
  /// (`util/AbstractDirectionalAxisBlock.java:16`), also
  /// `DirectionalAxisKineticBlock`'s (Create).
  static final BlockProperty alongFirst = BlockProperty.boolean('axis_along_first');

  /// `DirectedDirectionalBlock.TARGET` (Create, `content/redstone/DirectedDirectionalBlock.java:27`):
  /// `AttachFace` in enum order, `wall` the registered default.
  static final BlockProperty target = BlockProperty.enumeration('target', ['floor', 'wall', 'ceiling']);

  /// `BlockStateProperties.HORIZONTAL_AXIS` (`GimbalSensorBlock.java:35`): `x`/`z` only.
  static final BlockProperty horizontalAxis = BlockProperty.enumeration('horizontal_axis', ['x', 'z']);

  /// `NameplateBlock.POSITION` (`nameplate/NameplateBlock.java:62`), the `Position`
  /// enum order of `:269-272`.
  static final BlockProperty position =
      BlockProperty.enumeration('position', ['single', 'left', 'right', 'middle']);

  /// `AugerShaftBlock.SECTION` (`auger_shaft/AugerShaftBlock.java:66`), the
  /// `BarrelSection` enum order of `:262-265`.
  static final BlockProperty section =
      BlockProperty.enumeration('section', ['front', 'middle', 'end', 'single']);

  /// `AugerShaftBlock.DIAL`... no: `AltitudeSensorBlock.DIAL`
  /// (`altitude_sensor/AltitudeSensorBlock.java:41`), the `FaceType` enum order of
  /// `:175-177`.
  static final BlockProperty dial = BlockProperty.enumeration('dial', ['linear', 'radial']);

  /// `AugerShaftBlock.COG`.
  static final BlockProperty cog = BlockProperty.boolean('cog');

  /// `AugerShaftBlock.ENCASED`.
  static final BlockProperty encased = BlockProperty.boolean('encased');

  /// `AugerShaftBlock`'s six `BlockStateProperties` connect booleans, in the order
  /// the Java declares them (`:69-74`).
  static final BlockProperty north = BlockProperty.boolean('north');
  static final BlockProperty east = BlockProperty.boolean('east');
  static final BlockProperty south = BlockProperty.boolean('south');
  static final BlockProperty west = BlockProperty.boolean('west');
  static final BlockProperty up = BlockProperty.boolean('up');
  static final BlockProperty down = BlockProperty.boolean('down');

  /// `DirectionalGearshiftBlock.LEFT_POWERED` / `RIGHT_POWERED` (`:30-31`).
  static final BlockProperty leftPowered = BlockProperty.boolean('left_powered');
  static final BlockProperty rightPowered = BlockProperty.boolean('right_powered');

  /// `DockingConnectorBlock.EXTENDED` (`docking_connector/DockingConnectorBlock.java:37`).
  static final BlockProperty extended = BlockProperty.boolean('extended');

  /// `RedstoneAccumulatorBlock.SIDE_POWERED` (`:38`) and the vanilla `POWERING`
  /// (`BlockStateProperties.POWERING`, used at `:53-54`).
  static final BlockProperty sidePowered = BlockProperty.boolean('side_powered');
  static final BlockProperty powering = BlockProperty.boolean('powering');

  /// `LaserPointerBlock.INVERTED` / `RedstoneInductorBlock.INVERTED` /
  /// `RedstoneAccumulatorBlock.INVERTED` — vanilla `BlockStateProperties.INVERTED`.
  static final BlockProperty inverted = BlockProperty.boolean('inverted');

  /// `VelocitySensorBlock.POWERED` (`velocity_sensor/VelocitySensorBlock.java:28-30`):
  /// **not** a boolean — 0 unpowered, 1 along the positive axis, 2 along the negative
  /// one.
  static final BlockProperty poweredAxis = BlockProperty.intRange('powered', 0, 2);

  /// `TorsionSpringBlock`'s and the other blocks' boolean `powered` is
  /// [CreateProps.powered].
  static BlockProperty get powered => CreateProps.powered;

  /// `spring`'s enemy: nothing. Kept so the family files read uniformly.
  static const List<BlockProperty> none = [];
}

/// The keys of the blocks this port registers now that it did not before.
///
/// Names are the Java `SimBlocks` names, so the registry ids line up with the Java
/// order (`sim_java_order.dart`).
abstract final class SimExtraKeys {
  static const String mergingGlue = 'simulated:merging_glue';
  static const String ropeWinch = 'simulated:rope_winch';
  static const String ropeConnector = 'simulated:rope_connector';
  static const String ironHandle = 'simulated:iron_handle';
  static const String copperHandle = 'simulated:copper_handle';
  static const String directionalGearshift = 'simulated:directional_gearshift';
  static const String augerShaft = 'simulated:auger_shaft';
  static const String augerCog = 'simulated:auger_cog';
  static const String laserPointer = 'simulated:laser_pointer';
  static const String laserSensor = 'simulated:laser_sensor';
  static const String velocitySensor = 'simulated:velocity_sensor';
  static const String altitudeSensor = 'simulated:altitude_sensor';
  static const String gimbalSensor = 'simulated:gimbal_sensor';
  static const String navigationTable = 'simulated:navigation_table';
  static const String opticalSensor = 'simulated:optical_sensor';
  static const String dockingConnector = 'simulated:docking_connector';
  static const String pairedDockingConnector = 'simulated:paired_docking_connector';
  static const String analogTransmission = 'simulated:analog_transmission';
  static const String linkedTypewriter = 'simulated:linked_typewriter';
  static const String directionalLinkedReceiver = 'simulated:directional_linked_receiver';
  static const String modulatingLinkedReceiver = 'simulated:modulating_linked_receiver';
  static const String redstoneAccumulator = 'simulated:redstone_accumulator';
  static const String redstoneInductor = 'simulated:redstone_inductor';
  static const String redstoneMagnet = 'simulated:redstone_magnet';

  /// `simulated:<colour>_handle` (`SimBlocks.createHandle`, `:847-864`).
  static String handle(String colour) => 'simulated:${colour}_handle';

  /// `simulated:<colour>_nameplate` (`SimBlocks.NAMEPLATES`, `:801-841`).
  static String nameplate(String colour) => 'simulated:${colour}_nameplate';
}