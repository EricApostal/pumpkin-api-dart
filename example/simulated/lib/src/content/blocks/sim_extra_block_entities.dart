// The block entities of the content this port registers now but has not ported the
// behaviour of yet.
//
// **These are registration placeholders.** Each one is a real host block entity of the
// Java type's key, with the Java class named at it, so the block links to a registered
// type and the world can save and load it -- but the Java class's logic (inventories,
// the winch's rope physics, the sensors' scans, the receivers' link state, the
// nameplate's text, the accumulator's count, the magnet's field) is **not** in here.
// Nothing in this file pretends to be that logic: the classes exist so the *content*
// is registered, and every behaviour that is missing is named at the class.
//
// Two of them are more than placeholders because the state is on the block and the
// host drives it: `DirectionalGearshiftBlockEntity` and `AnalogTransmissionBlockEntity`
// are kinetic (`KineticBlockEntity`), so the network turns them with the Java's
// `getRotationAxis` / `hasShaftTowards` rules, which are registered in
// `index/sim_kinetics.dart`.
//
// Host: this file uses `pumpkin_api`.
//
// Java: dev.simulated_team.simulated.index.SimBlockEntityTypes (the 30 types;
//       `:53-278`) and the `content.blocks.*.*BlockEntity` classes named below.
// ignore_for_file: implementation_imports
import 'package:create/src/core/block_entity.dart';
import 'package:create/src/kinetics/kinetic_block_entity.dart' show KineticBlockEntity;

/// `simulated:simple` (`SimBlockEntityTypes.java:53-58`) — the block entity of
/// `simulated:analog_transmission`.
///
/// Java: `content.blocks.analog_transmission.AnalogTransmissionBlockEntity`, a
/// `KineticBlockEntity` with an `ExtraKinetics` cogwheel configuration and the
/// `POWERED` gate that couples the two halves of the shaft. Stubbed: the analog
/// coupling (the extra cogwheel), the stress hand-off and the `POWERED` write.
final class AnalogTransmissionBlockEntity extends KineticBlockEntity {
  static const String type = 'simulated:simple';
  static const String block = 'simulated:analog_transmission';

  AnalogTransmissionBlockEntity(super.worldId, super.pos);
}

/// `simulated:rope_winch` (`SimBlockEntityTypes.java:73-77`).
///
/// Java: `content.blocks.rope.rope_winch.RopeWinchBlockEntity`, a `SmartBlockEntity`
/// that holds a rope strand (`RopeHolderBlock`). Stubbed: the whole winch -- the
/// strand, its Sable physics object, the winding speed, the shear-on-click and the
/// sub-level attachment. The port's pure half of the strand is in
/// `content/blocks/rope/rope_strand.dart`, unwired.
final class RopeWinchBlockEntity extends KineticBlockEntity {
  static const String type = 'simulated:rope_winch';
  static const String block = 'simulated:rope_winch';

  RopeWinchBlockEntity(super.worldId, super.pos);
}

/// `simulated:rope_connector` (`SimBlockEntityTypes.java:79-83`).
///
/// Java: `content.blocks.rope.rope_connector.RopeConnectorBlockEntity`, the far end
/// of a strand. Stubbed: the strand and its constraints.
final class RopeConnectorBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:rope_connector';
  static const String block = 'simulated:rope_connector';

  RopeConnectorBlockEntity(super.worldId, super.pos);
}

/// `simulated:merging_glue` (`SimBlockEntityTypes.java:267-271`).
///
/// Java: `content.blocks.merging_glue.MergingGlueBlockEntity`, which joins two
/// sub-levels. Stubbed: the join itself; the port has the packet's rules
/// (`merging_glue_placement.dart`) and no world side.
final class MergingGlueBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:merging_glue';
  static const String block = 'simulated:merging_glue';

  MergingGlueBlockEntity(super.worldId, super.pos);
}

/// `simulated:handle` (`SimBlockEntityTypes.java:107-112`) — one type for the iron,
/// the copper and the sixteen dyed handles (`validBlocks(SimBlocks.DYED_HANDLES...)`).
///
/// Java: `content.blocks.handle.HandleBlockEntity`, which holds a `Player` grabbing
/// the handle and drives the sub-level. Stubbed: the grab (the hold payload, the
/// player's attachment, the strength readout).
final class HandleBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:handle';
  static const String block = 'simulated:iron_handle';

  HandleBlockEntity(super.worldId, super.pos);
}

/// `simulated:nameplate` (`SimBlockEntityTypes.java:188-192`) — one type for all
/// sixteen colours.
///
/// Java: `content.blocks.nameplate.NameplateBlockEntity`, which holds the text and
/// names its sub-level (`ClipboardCloneable`). Stubbed: the text, the sub-level name
/// and the screen.
final class NameplateBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:nameplate';
  static const String block = 'simulated:white_nameplate';

  NameplateBlockEntity(super.worldId, super.pos);
}

/// `simulated:linked_typewriter` (`SimBlockEntityTypes.java:148-153`).
///
/// Java: `content.blocks.redstone.linked_typewriter.LinkedTypewriterBlockEntity`,
/// which drives the typewriter's display target. Stubbed: the display target, the
/// `POWERED` output and the entries. The port has the entries and the logic
/// (`linked_typewriter_logic.dart`, `linked_typewriter_entries.dart`) and does not
/// tick them.
final class LinkedTypewriterBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:linked_typewriter';
  static const String block = 'simulated:linked_typewriter';

  LinkedTypewriterBlockEntity(super.worldId, super.pos);
}

/// `simulated:optical_sensor` (`SimBlockEntityTypes.java:156-159`).
///
/// Java: `content.blocks.lasers.optical_sensor.OpticalSensorBlockEntity`, an
/// `AbstractLaserBlockEntity` shooting a beam and dyeing it. Stubbed: the beam, the
/// detection, the `POWERED` write, the dye slot.
final class OpticalSensorBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:optical_sensor';
  static const String block = 'simulated:optical_sensor';

  OpticalSensorBlockEntity(super.worldId, super.pos);
}

/// `simulated:laser_pointer` (`SimBlockEntityTypes.java:161-164`).
///
/// Java: `content.blocks.lasers.laser_pointer.LaserPointerBlockEntity`, the beam
/// source. Stubbed: the beam and the `INVERTED` / `POWERED` behaviour.
final class LaserPointerBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:laser_pointer';
  static const String block = 'simulated:laser_pointer';

  LaserPointerBlockEntity(super.worldId, super.pos);
}

/// `simulated:ir_sensor` (`SimBlockEntityTypes.java:166-171`) — the type of the
/// block `simulated:laser_sensor`: the block entity id is the legacy one, which is
/// why the two differ.
///
/// Java: `content.blocks.lasers.laser_sensor.LaserSensorBlockEntity`, which reads the
/// beam that hits it and reports `currentPower`. Stubbed: the hit detection and the
/// power output.
final class LaserSensorBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:ir_sensor';
  static const String block = 'simulated:laser_sensor';

  LaserSensorBlockEntity(super.worldId, super.pos);
}

/// `simulated:velocity_sensor` (`SimBlockEntityTypes.java:174-179`).
///
/// Java: `content.blocks.velocity_sensor.VelocitySensorBlockEntity`, which reads the
/// relative velocity of a facing contraption and writes `POWERED` (`0..2`) and the
/// strength. Stubbed: the velocity read, the `POWERED` write and the redstone output.
final class VelocitySensorBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:velocity_sensor';
  static const String block = 'simulated:velocity_sensor';

  VelocitySensorBlockEntity(super.worldId, super.pos);
}

/// `simulated:altitude_sensor` (`SimBlockEntityTypes.java:94-98`).
///
/// Java: `content.blocks.altitude_sensor.AltitudeSensorBlockEntity`, which reports the
/// sub-level's altitude and runs on a contraption
/// (`AltitudeSensorMovementBehaviour`). Stubbed: the altitude read, the redstone
/// output, the movement behaviour.
final class AltitudeSensorBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:altitude_sensor';
  static const String block = 'simulated:altitude_sensor';

  AltitudeSensorBlockEntity(super.worldId, super.pos);
}

/// `simulated:gimbal_sensor` (`SimBlockEntityTypes.java:100-105`).
///
/// Java: `content.blocks.gimbal_sensor.GimbalSensorBlockEntity`, which reports the
/// sub-level's tilt. Stubbed: the tilt read and the redstone output.
final class GimbalSensorBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:gimbal_sensor';
  static const String block = 'simulated:gimbal_sensor';

  GimbalSensorBlockEntity(super.worldId, super.pos);
}

/// `simulated:navigation_table` (`SimBlockEntityTypes.java:209-215`).
///
/// Java: `content.blocks.nav_table.NavTableBlockEntity`, with a `NavTableInventory`
/// of navigation targets. Stubbed: the inventory, the target tracking and the
/// display source.
final class NavigationTableBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:navigation_table';
  static const String block = 'simulated:navigation_table';

  NavigationTableBlockEntity(super.worldId, super.pos);
}

/// `simulated:docking_connector` (`SimBlockEntityTypes.java:85-92`).
///
/// Java: `content.blocks.docking_connector.DockingConnectorBlockEntity`, a `SimMagnet`
/// with a battery, a tank and a duo inventory, pairing with the connector it faces.
/// Stubbed: the pairing, the magnet behaviour, the battery / tank / inventory, the
/// `EXTENDED` / `POWERED` writes.
final class DockingConnectorBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:docking_connector';
  static const String block = 'simulated:docking_connector';

  DockingConnectorBlockEntity(super.worldId, super.pos);
}

/// `simulated:directional_linked_receiver` (`SimBlockEntityTypes.java:181-186`).
///
/// Java: `content.blocks.redstone.directional_receiver.DirectionalLinkedReceiverBlockEntity`,
/// which reads a directional redstone link and drives its output face. Stubbed: the
/// link read and the `POWERED` write.
final class DirectionalLinkedReceiverBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:directional_linked_receiver';
  static const String block = 'simulated:directional_linked_receiver';

  DirectionalLinkedReceiverBlockEntity(super.worldId, super.pos);
}

/// `simulated:modulating_linked_receiver` (`SimBlockEntityTypes.java:194-201`).
///
/// Java: `content.blocks.redstone.modulating_receiver.ModulatingLinkedReceiverBlockEntity`,
/// a `RedstoneInductorValueBehaviour` receiver whose strength follows the link's
/// frequency. Stubbed: the link read, the strength and the `POWERED` write.
final class ModulatingLinkedReceiverBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:modulating_linked_receiver';
  static const String block = 'simulated:modulating_linked_receiver';

  ModulatingLinkedReceiverBlockEntity(super.worldId, super.pos);
}

/// `simulated:redstone_accumulator` (`SimBlockEntityTypes.java:203-207`).
///
/// Java: `content.blocks.redstone.redstone_accumulator.RedstoneAccumulatorBlockEntity`,
/// a counter: it adds the pulses it sees and reports the total as an analog signal,
/// with `SIDE_POWERED` / `POWERING` / `INVERTED`. Stubbed: the count, the output and
/// the tick scheduling.
final class RedstoneAccumulatorBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:redstone_accumulator';
  static const String block = 'simulated:redstone_accumulator';

  RedstoneAccumulatorBlockEntity(super.worldId, super.pos);
}

/// `simulated:redstone_inductor` (`SimBlockEntityTypes.java:217-222`).
///
/// Java: `content.blocks.redstone.redstone_inductor.RedstoneInductorBlockEntity`,
/// whose `outputSignal` is raised by a wrench value box and inverted by the block's
/// `INVERTED`. Stubbed: the value box, the output and the `INVERTED` read.
final class RedstoneInductorBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:redstone_inductor';
  static const String block = 'simulated:redstone_inductor';

  RedstoneInductorBlockEntity(super.worldId, super.pos);
}

/// `simulated:redstone_magnet` (`SimBlockEntityTypes.java:224-227`).
///
/// Java: `content.blocks.redstone_magnet.RedstoneMagnetBlockEntity`, a `SimMagnet`
/// that links to a partner and reports whether they are close enough. Stubbed: the
/// magnet map, the pairing and the `POWERED` write.
final class RedstoneMagnetBlockEntity extends CreateBlockEntity {
  static const String type = 'simulated:redstone_magnet';
  static const String block = 'simulated:redstone_magnet';

  RedstoneMagnetBlockEntity(super.worldId, super.pos);
}

/// `simulated:auger_shaft` (`SimBlockEntityTypes.java:244-247`) — one type for
/// `simulated:auger_shaft` and `simulated:auger_cog`.
///
/// Java: `content.blocks.auger_shaft.AugerShaftBlockEntity`, a `KineticBlockEntity`
/// with an `AugerInventory`, a `BlockHarvester` and an `ItemReciever`: the auger
/// breaks the blocks in front of it and collects the drops. Stubbed: the harvest, the
/// inventory, the funnel interaction and the `SECTION` / connect-boolean state.
final class AugerShaftBlockEntity extends KineticBlockEntity {
  static const String type = 'simulated:auger_shaft';
  static const String block = 'simulated:auger_shaft';

  AugerShaftBlockEntity(super.worldId, super.pos);
}

/// `simulated:directional_gearshift` (`SimBlockEntityTypes.java:273-277`).
///
/// Java: `content.blocks.directional_gearshift.DirectionalGearshiftBlockEntity`, a
/// `SplitShaftBlockEntity`: each side is powered separately by the two neighbours
/// across the gearshift's `facing` axis. Stubbed: the split-shaft coupling (the
/// `LEFT_POWERED` / `RIGHT_POWERED` reads and the two half-shaft speeds).
final class DirectionalGearshiftBlockEntity extends KineticBlockEntity {
  static const String type = 'simulated:directional_gearshift';
  static const String block = 'simulated:directional_gearshift';

  DirectionalGearshiftBlockEntity(super.worldId, super.pos);
}