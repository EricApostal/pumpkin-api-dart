// The kinetic rules (`IRotate`) and stress values of simulated's kinetic blocks,
// registered into Create's kinetic runtime from the plugin's `onLoad`.
//
// Java: `SwivelBearingBlock`, `SteeringWheelBlock`, `TorsionSpringBlock` and the
// stress values of `index/SimBlocks` (`SimStress.setImpact`/`setCapacity`,
// `BlockStressValues.setGeneratorSpeed`).
//
// A Pumpkin plugin is one wasm component, so this module has its own
// `KineticsRuntime` (`installHostedModuleState`): the rules go on that instance,
// which is also what the kinetic network resolves its neighbours through.
// Without them `KineticBlockRegistry.defFor` returns `null` for these keys: a
// shaft cannot connect, the swivel bearing never turns (and so never assembles),
// and the steering wheel's rotation goes nowhere.
// ignore_for_file: implementation_imports
import 'package:create/src/kinetics/block_defs.dart'
    show FacingBlockDef, KineticBlockDef, VerticalShaftDef;
import 'package:create/src/kinetics/geometry.dart' show Dir, KAxis, KState;
import 'package:create/src/kinetics/runtime.dart' show KineticsRuntime;

import 'sim_blocks.dart' show SimBlockKeys;

/// `SwivelBearingBlock.hasShaftTowards` (`SwivelBearingBlock.java:90-94`): the
/// shaft runs along the whole facing axis while the bearing is not assembled
/// (that axis becomes the hinge), and sticks out of the back once it is.
final class SwivelBearingDef extends KineticBlockDef {
  const SwivelBearingDef();

  @override
  KAxis rotationAxis(KState state) => (state.dirOf('facing') ?? Dir.up).axis;

  @override
  bool hasShaftTowards(KState state, Dir face) {
    final facing = state.dirOf('facing') ?? Dir.up;
    return state.flag('assembled')
        ? face == facing.opposite
        : face.axis == facing.axis;
  }
}

/// `SteeringWheelBlockEntity.RPM`: the speed the wheel generates.
const int steeringWheelRpm = 16;

/// The kinetic rule of every simulated block that is an `IRotate`, by key.
///
/// * `SwivelBearingBlock.getRotationAxis = FACING.getAxis()`.
/// * `SteeringWheelBlock.getRotationAxis = Y`,
///   `hasShaftTowards = ON_FLOOR ? face == DOWN : face == UP`
///   (`SteeringWheelBlock.java:228-235`).
/// * `TorsionSpringBlock.hasShaftTowards = face.getOpposite() == FACING`,
///   `getRotationAxis = FACING.getAxis()` (`TorsionSpringBlock.java:41-44`).
final Map<String, KineticBlockDef> simKineticDefs = {
  SimBlockKeys.swivelBearing: const SwivelBearingDef(),
  SimBlockKeys.steeringWheel: const VerticalShaftDef(property: 'on_floor', shaftUpWhenSet: false),
  SimBlockKeys.torsionSpring: const FacingBlockDef(shaftAtFront: false),
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