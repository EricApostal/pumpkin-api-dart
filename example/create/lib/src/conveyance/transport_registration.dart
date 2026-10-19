// Registration hooks for the item-transport half of the conveyance module: chutes, funnels,
// tunnels, vaults, crates and the depot/ejector. `conveyance_module.dart` calls these in its
// phases; the item-transport area fills them in.
import '../core/module.dart';
import '../core/registry.dart';

/// Phase 1: blocks, block entity types, items.
void registerTransport(CreateRegistry registry) {}

/// Phase 2: services, event subscriptions, payload handlers.
void loadTransport(CreateContext ctx) {}

/// Phase 3: the server finished loading.
void serverTransportLoaded(CreateRuntime runtime) {}

/// Plugin unload.
void unloadTransport() {}
