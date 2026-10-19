/// The public API of the kinetics module: what belts, processing machines, fluids
/// and contraptions build on. Import it as `package:create/src/api/kinetics.dart`.
///
/// * [KineticBlockEntity] (+ [GeneratingKineticBlockEntity]): extend it for every
///   block whose block entity takes part in the kinetic network. Override
///   `generatedSpeed`, `calculateStressApplied`, `onSpeedChanged`,
///   `propagateRotationTo`, `isCustomConnection`, `addPropagationLocations` and
///   `onKineticInitialize`.
/// * [KineticNetworkService]: `ctx.services.require<KineticNetworkService>()`;
///   register the connection rules of your blocks with `registerKineticBlock`.
/// * [KineticBlockDef] and friends: `IRotate` as data.
/// * [KineticConfig], [StressSource], [SpeedLevel]: config values and stress table.
library;

export 'behaviours.dart' show KineticScrollValueBehaviour, ScrollValueBehaviour;
export 'block_defs.dart'
    show
        AxisBlockDef,
        CuckooClockDef,
        DirectionalAxisBlockDef,
        EncasedCogDef,
        FacingAxisBlockDef,
        FacingBlockDef,
        GantryShaftDef,
        KineticBlockDef;
export 'block_entities.dart'
    show
        ChainGearshiftBlockEntity,
        ClutchBlockEntity,
        CuckooClockBlockEntity,
        FlywheelBlockEntity,
        GaugeBlockEntity,
        GearboxBlockEntity,
        GearshiftBlockEntity,
        SequencedGearshiftBlockEntity,
        SpeedControllerBlockEntity,
        SpeedGaugeBlockEntity,
        SplitShaftBlockEntity,
        StressGaugeBlockEntity,
        TurntableBlockEntity;
export 'generating.dart' show GeneratingNodeMixin;
export 'gantry/gantry_shaft.dart' show GantryShaftBlockEntity;
export 'generators.dart'
    show
        CreativeMotorBlockEntity,
        HandCrankBlockEntity,
        LargeWaterWheelBlockEntity,
        PoweredShaftBlockEntity,
        ValveHandleBlockEntity,
        WaterWheelBlockEntity;
export 'geometry.dart' show KAxis, Dir, KPos, KState;
export 'kinetic_block_entity.dart'
    show
        DirectionalShaftHalvesBlockEntity,
        GeneratingKineticBlockEntity,
        KineticBlockEntity,
        KineticOps,
        SimpleKineticBlockEntity;
export 'kinetic_blocks.dart' show kineticValidBlocks;
export 'network.dart' show KineticNetwork;
export 'node.dart'
    show
        ChainModifierNode,
        KineticBlockRegistry,
        KineticLevel,
        KineticNode,
        KineticNodeMixin,
        SpeedControllerNode;
export 'propagator.dart' show RotationPropagator;
export 'runtime.dart'
    show
        HostKineticLevel,
        KineticsRuntime,
        SteamEngineBoilerSource,
        toBlockPos,
        toKPos;
export 'sequence.dart' show Instruction, SequenceContext, SequencerInstructions;
export 'service.dart' show KineticNetworkService;
export 'transform.dart' show mirrorKineticState, rotateKineticState;
export 'settings.dart'
    show
        KineticConfig,
        KineticStressTable,
        KineticsSettings,
        StressSource,
        SpeedLevel,
        StressImpactLevel,
        convertToAngular,
        convertToDirection,
        convertToLinear;
