// The block entity type keys the peripherals are registered under.
//
// Java reads them from `SimBlockEntityTypes` (a Registrate entry); the port
// keys its registry by the same id, which is what the host reports for a block
// entity (`CreateBlockEntity.typeKey`).
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.index.SimBlockEntityTypes

/// `SimBlockEntityTypes`.
abstract final class SimBlockEntityTypes {
  static const String torsionSpring = 'simulated:torsion_spring';
  static const String dockingConnector = 'simulated:docking_connector';
  static const String altitudeSensor = 'simulated:altitude_sensor';
  static const String gimbalSensor = 'simulated:gimbal_sensor';
  static const String swivelBearing = 'simulated:swivel_bearing';
  static const String linkedTypewriter = 'simulated:linked_typewriter';
  static const String opticalSensor = 'simulated:optical_sensor';
  static const String velocitySensor = 'simulated:velocity_sensor';
  static const String directionalLinkedReceiver = 'simulated:directional_linked_receiver';
  static const String nameplate = 'simulated:nameplate';
  static const String modulatingLinkedReceiver = 'simulated:modulating_linked_receiver';
  static const String navigationTable = 'simulated:navigation_table';
}
