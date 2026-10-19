// Registration hooks for the actuator content of the contraptions module: bearings, pistons,
// pulleys, gantries, elevators, minecart contraptions, chassis, super glue, mounted contraptions,
// the wrench and the contraption data. The contraptions module (`contraptions_module.dart`) calls
// these in its phases; the actuator area fills them in.
import '../core/module.dart';
import '../core/registry.dart';

/// Phase 1: blocks, block entity types, items, entity types.
void registerActuatorContent(CreateRegistry registry) {}

/// Phase 2: services, event subscriptions, payload handlers.
void loadActuatorContent(CreateContext ctx) {}

/// Phase 3: the server finished loading.
void serverActuatorContentLoaded(CreateRuntime runtime) {}

/// Plugin unload.
void unloadActuatorContent() {}
