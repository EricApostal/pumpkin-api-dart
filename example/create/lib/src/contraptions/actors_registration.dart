// Registration hooks for the actors (movement behaviours) of the contraptions module: harvesters,
// ploughs, rollers, seats, portable storage interfaces, contraption controls, train controls and the
// block behaviours that run on a moving contraption. The contraptions module
// (`contraptions_module.dart`) calls these in its phases; the actor area fills them in.
import '../core/module.dart';
import '../core/registry.dart';

/// Phase 1: blocks, block entity types, items.
void registerActorContent(CreateRegistry registry) {}

/// Phase 2: the movement behaviour registry and the services.
void loadActorContent(CreateContext ctx) {}

/// Phase 3: the server finished loading.
void serverActorContentLoaded(CreateRuntime runtime) {}

/// Plugin unload.
void unloadActorContent() {}
