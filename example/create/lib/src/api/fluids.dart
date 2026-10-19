/// The public API of the fluids module (published by `fluids`): Create's fluids,
/// tanks, pipes, the pump, the spout, the item drain and the hose pulley.
/// Import as `package:create/src/api/fluids.dart`.
///
/// ```dart
/// final runtime = FluidsRuntime.instance;           // after the module loaded
/// final level = runtime.levelOf(worldId);            // the FluidWorld of a world
/// final stack = FStack(FluidKeys.honey, 1000);       // the module's fluid stack
/// final recipes = runtime.recipes;                   // create:filling / emptying
/// ```
///
/// * Values: [FStack] / [FluidKeys], [FluidStorage] (tanks and handlers),
///   [FluidTypes] / [FluidHelper].
/// * Pipes: [PipeConnection], [PipeNodeMixin], [PipeBlocks], [FluidWorld].
/// * Block entities: [FluidTankBlockEntity], [CreativeFluidTankBlockEntity],
///   [FluidCapable] and [TankBoilerSource] (the `SteamEngineBoilerSource`).
/// * Items: [FluidItemSpec], [FluidItemRules], [GenericItemEmptying],
///   [GenericItemFilling], [FillingBySpout], [PotionFluidHandler].
library;

export 'behaviour/spouting/spouting.dart';
export 'boiler/blaze_burner_fuel.dart';
export 'boiler/boiler_heater.dart';
export 'effect/open_pipe_effect_handler.dart';
export 'transfer/create_fluid_handler.dart';
export '../fluids/fluid_helper.dart';
export '../fluids/fluid_host.dart'
    show
        ConfigsFluidsConfig,
        FluidCapable,
        HostFluidStorage,
        fromHostFluid,
        toHostFluid;
export '../fluids/fluid_runtime.dart' show FluidsRuntime;
export '../fluids/fluid_stack.dart';
export '../fluids/fluid_storage.dart';
export '../fluids/fluid_tank.dart'
    show CreativeFluidTankBlockEntity, FluidTankBlockEntity, TankBoilerSource;
export '../fluids/fluid_world.dart';
export '../fluids/fluids_module.dart' show FluidsModule;
export '../fluids/generic_item_fluid.dart';
export '../fluids/pipe_blocks.dart';
export '../fluids/pipe_connection.dart';
export '../fluids/pipe_node.dart';
export '../fluids/potion_data.dart';
export '../fluids/potion_fluid.dart';
export '../fluids/potion_mixing.dart';
export '../fluids/virtual_fluid.dart';
