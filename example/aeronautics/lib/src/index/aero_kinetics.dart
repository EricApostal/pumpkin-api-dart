// The kinetic rules (`IRotate`) and stress values of the aeronautics blocks,
// registered into Create's kinetic runtime from the module's `onLoad`.
//
// Java: `index/AeroBlocks` (`AeroStress.setImpact`) and the block classes
// `BasePropellerBlock`, `SmartPropellerBlock`, `EncasedShaftBlock` (Create's,
// aeronautics builds the dyed shafts from it), `BearingBlock` (both propeller
// bearings) and `MountedPotatoCannonBlock` (`DirectionalAxisKineticBlock`).
//
// A Pumpkin plugin is one wasm component, so this module has its own
// `KineticsRuntime` (`installHostedModuleState`): the rules are registered on
// that instance, which is also what the kinetic network resolves its neighbours
// through. Without them `KineticBlockRegistry.defFor` returns `null` for every
// aeronautics key, so no shaft connects and `speed` stays 0 forever.
// ignore_for_file: implementation_imports
import 'package:create/src/kinetics/block_defs.dart'
    show AxisBlockDef, DirectionalAxisBlockDef, FacingBlockDef, KineticBlockDef, VerticalShaftDef;
import 'package:create/src/kinetics/runtime.dart' show KineticsRuntime;

import '../content/blocks/hot_air/envelope_blocks.dart' show encasedEnvelopeKey, envelopeColors;
import '../content/blocks/mounted_potato_cannon/mounted_potato_cannon.dart' show mountedPotatoCannonKey;
import '../content/blocks/propeller/gyroscopic_propeller_bearing_block.dart'
    show gyroscopicPropellerBearingKey;
import '../content/blocks/propeller/propeller_bearing_block.dart' show propellerBearingKey;
import '../content/blocks/propeller/small_propeller_blocks.dart' show SmallPropellerKeys;

/// `MountedPotatoCannonBlock`'s `AXIS_ALONG_FIRST_COORDINATE` property as the
/// port declares it. Java names it `axis_along_first` (Create's
/// `DirectionalAxisKineticBlock`, `DirectionalAxisKineticBlock.java:21`); the
/// port's block and its `AeroJavaOrder` row use this name instead, and this is
/// the property the state actually carries, so the rule reads it.
const String mountedPotatoCannonAxisProperty = 'axis_along_first_coordinate';

/// `BasePropellerBlock.hasShaftTowards = face == FACING.getOpposite()`,
/// `getRotationAxis = FACING.getAxis()`: the shaft comes out of the back. The
/// two propeller bearings are Create's `BearingBlock`, the same rule.
const FacingBlockDef _propellerDef = FacingBlockDef(shaftAtFront: false);

/// The kinetic rule of every aeronautics block that is an `IRotate`, by block
/// key.
///
/// * `BasePropellerBlock` (`BasePropellerBlock.java:53-59`) and `BearingBlock`
///   (`BearingBlock.hasShaftTowards`): the shaft is behind the block.
/// * `SmartPropellerBlock` (`SmartPropellerBlock.java:50-57`): vertical axis,
///   the shaft is on the top face when `ceiling` is set, else on the bottom.
/// * `EncasedShaftBlock extends RotatedPillarKineticBlock`: the shaft runs
///   through the `axis` property (`AeroBlocks.java:145-160`).
/// * `MountedPotatoCannonBlock extends DirectionalAxisKineticBlock`: the shaft
///   runs on the axis perpendicular to `facing`.
final Map<String, KineticBlockDef> aeroKineticDefs = {
  SmallPropellerKeys.wooden: _propellerDef,
  SmallPropellerKeys.andesite: _propellerDef,
  SmallPropellerKeys.smart: const VerticalShaftDef(property: 'ceiling', shaftUpWhenSet: true),
  for (final colour in envelopeColors) encasedEnvelopeKey(colour): const AxisBlockDef(),
  propellerBearingKey: _propellerDef,
  gyroscopicPropellerBearingKey: _propellerDef,
  mountedPotatoCannonKey: const DirectionalAxisBlockDef(
    alongFirstProperty: mountedPotatoCannonAxisProperty,
  ),
};

/// `AeroStress.setImpact` per block (`AeroBlocks.java:251,271,297,326,354,376`):
/// 2.0 for the two bearings and the cannon, 4.0 for the three propellers. The
/// encased shafts register none, like every other plain shaft (Create's
/// `BlockStressValues` default is 0).
final Map<String, double> aeroStressImpacts = {
  propellerBearingKey: 2,
  gyroscopicPropellerBearingKey: 2,
  mountedPotatoCannonKey: 2,
  SmallPropellerKeys.wooden: 4,
  SmallPropellerKeys.andesite: 4,
  SmallPropellerKeys.smart: 4,
};

/// Registers every aeronautics block that is an `IRotate` and its stress impact
/// with the component's kinetic runtime.
void registerAeroKinetics(KineticsRuntime runtime) {
  for (final entry in aeroKineticDefs.entries) {
    runtime.blocks.register(entry.key, entry.value);
  }
  for (final entry in aeroStressImpacts.entries) {
    runtime.stressTable.register(entry.key, impact: entry.value);
  }
}