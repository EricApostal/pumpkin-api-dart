// Registration hooks for the belt half of the conveyance module: belts, chain conveyors and the
// belt funnels. `conveyance_module.dart` calls these in its phases; the belt area fills them in.
import '../core/module.dart';
import '../core/registry.dart';

/// Phase 1: blocks, block entity types, items.
void registerBelts(CreateRegistry registry) {}

/// Phase 2: services, event subscriptions, kinetic block rules, payload handlers.
void loadBelts(CreateContext ctx) {}

/// Phase 3: the server finished loading.
void serverBeltsLoaded(CreateRuntime runtime) {}

/// Plugin unload.
void unloadBelts() {}
