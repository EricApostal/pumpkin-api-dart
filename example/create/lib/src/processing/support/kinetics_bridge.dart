// The one place where the processing module reaches into the kinetics module's internals:
// the block factory and behaviour builder that the machines (all kinetic blocks) share with
// the kinetic blocks of `lib/src/kinetics`. `lib/src/api/kinetics.dart` does not export them
// (and may not be edited by this module), so they are re-exported here.
export '../../api/kinetics.dart';
export '../../kinetics/behavior_builder.dart' show HookCtx, buildKineticBehavior, makeCtx;
export '../../kinetics/block_data.dart' show KineticBlockData, kineticBlockData, manifestBlockOf;
export '../../kinetics/block_factory.dart' show KineticBlockSpec, applyKineticBlockChange, createBlockFromManifest, setKState, stateOfEvent;
export '../../kinetics/placement.dart' show PlacementContext, horizontalDirection, nearestLookingDirection, orderedByNearest;
export '../../kinetics/use_records.dart' show UseRecord, UseRecords;
