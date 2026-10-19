/// The decoration module's API for other modules (published by `decoration`):
///
/// * `BracketedBlockEntityBehaviour` and `BracketRegistry`: brackets on shafts, cogwheels and pipes.
///   Kinetics / fluids add `BracketedBlockEntityBehaviour(canHave: ...)` to the block entities of
///   those blocks; `ctx.services.require<BracketRegistry>().addTarget(key, resolve)` registers extra
///   bracketable blocks (shafts, cogwheels, `fluid_pipe`, `glass_fluid_pipe` and `mechanical_pump`
///   are known).
/// * `EncasingRegistry`: `EncasableBlock` / `EncasedBlock`.
/// * `SlidingDoors`, `DoorControl`, `DoorControlBehaviour`: opening sliding doors from trains and
///   contraptions, the door mode of stations.
/// * `WhistleBoilerHooks`: optional service the fluid module provides to keep a boiler in step with
///   the whistles on its tank.
/// * `CopycatBlockEntity`: the material of a copycat (for contraption transforms).
library;

export '../decoration/block_entities.dart' show CopycatBlockEntity, PlacardBlockEntity, SlidingDoorBlockEntity, WhistleBlockEntity;
export '../decoration/blocks_whistle.dart' show WhistleBoilerHooks;
export '../decoration/bracket.dart' show BracketTarget, BracketType, woodenBracketKey, metalBracketKey;
export '../decoration/bracketed_behaviour.dart' show BracketRegistry, BracketedBlockEntityBehaviour, straightPipeAxis;
export '../decoration/copycat.dart' show copycatBaseKey, copycatPanelKey, copycatStepKey;
export '../decoration/encasing.dart' show EncasedVariant, EncasingContext, EncasingRegistry;
export '../decoration/girder.dart' show girderKey, girderEncasedShaftKey;
export '../decoration/sliding_doors.dart' show DoorControl, DoorControlBehaviour, SlidingDoors;
