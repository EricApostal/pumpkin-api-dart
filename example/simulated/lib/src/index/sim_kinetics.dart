// The kinetic rules (`IRotate`) and stress values of simulated's kinetic blocks,
// registered into Create's kinetic runtime from the plugin's `onLoad`.
//
// Java: `SwivelBearingBlock`, `SteeringWheelBlock`, `TorsionSpringBlock` and the
// stress values of `index/SimBlocks` (`SimStress.setImpact`/`setCapacity`,
// `BlockStressValues.setGeneratorSpeed`).
//
// A Pumpkin plugin is one wasm component, so this module has its own
// `KineticsRuntime` (`installHostedModuleState`). The rules are `WireKineticDef`s
// because there are **two** components to satisfy: Create's plugin runs the whole
// network (`create.kinetics`, `docs/kinetics-across-plugins.md`) and rebuilds each
// rule from its wire form, while this component keeps the same def for the case
// where no owner is loaded — one description for both sides.
//
// Without them `KineticBlockRegistry.defFor` is `null` for these keys: a shaft
// cannot connect, the swivel bearing never turns (and so never assembles), and
// the steering wheel's rotation goes nowhere.
// ignore_for_file: implementation_imports
import 'package:create/src/kinetics/runtime.dart' show KineticsRuntime;
import 'package:create/src/kinetics/wire_def.dart' show WireKineticDef;

import 'sim_blocks.dart' show SimBlockKeys;

/// `SteeringWheelBlockEntity.RPM`: the speed the wheel generates.
const int steeringWheelRpm = 16;

/// `PortableEngineBlock.hasShaftTowards(face) = face == HORIZONTAL_FACING`
/// (`PortableEngineBlock.java`): the shaft comes out of the facing side. It is a
/// generator (`setGeneratorSpeed(32)`, `setCapacity(64.0)`), so it is the one
/// simulated block that *drives* a Create network.
final WireKineticDef simPortableEngineDef = WireKineticDef.facingFront();

/// The kinetic rule of every simulated block that is an `IRotate`, by key.
///
/// * `SwivelBearingBlock.hasShaftTowards` (`SwivelBearingBlock.java:90-94`): the
///   shaft runs along the whole facing axis while the bearing is not assembled
///   (that axis becomes the hinge), and sticks out of the back once it is.
/// * `SteeringWheelBlock.getRotationAxis = Y`,
///   `hasShaftTowards = ON_FLOOR ? face == DOWN : face == UP`
///   (`SteeringWheelBlock.java:228-235`).
/// * `TorsionSpringBlock.hasShaftTowards = face.getOpposite() == FACING`,
///   `getRotationAxis = FACING.getAxis()` (`TorsionSpringBlock.java:41-44`).
final Map<String, WireKineticDef> simKineticDefs = {
  SimBlockKeys.swivelBearing: WireKineticDef.facingBackUnlessFlag(flag: 'assembled'),
  SimBlockKeys.steeringWheel: WireKineticDef.verticalByFlag(flag: 'on_floor', upWhenSet: false),
  SimBlockKeys.torsionSpring: WireKineticDef.facingBack(),
};

/// The stress impact / capacity / generated RPM per block, from `SimBlocks`:
/// `SimStress.setImpact(4.0)` for the swivel bearing (`:127`),
/// `setImpact(16.0)` + `setCapacity(8.0)` for the torsion spring (`:273-274`),
/// and `setCapacity(16.0)` + `setGeneratorSpeed(16)` for the steering wheel
/// (`:588-589`).
final Map<String, ({double? impact, double? capacity, int? generatedRpm})> simStressValues = {
  SimBlockKeys.swivelBearing: (impact: 4, capacity: null, generatedRpm: null),
  SimBlockKeys.torsionSpring: (impact: 16, capacity: 8, generatedRpm: null),
  SimBlockKeys.steeringWheel: (impact: null, capacity: 16, generatedRpm: steeringWheelRpm),
};

/// Registers the kinetic rules and stress values of the three blocks.
void registerSimKinetics(KineticsRuntime runtime) {
  for (final entry in simKineticDefs.entries) {
    runtime.blocks.register(entry.key, entry.value);
  }
  for (final entry in simStressValues.entries) {
    final values = entry.value;
    runtime.stressTable.register(
      entry.key,
      impact: values.impact,
      capacity: values.capacity,
      generatedRpm: values.generatedRpm,
    );
  }
}