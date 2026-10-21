// The items of Simulated.
//
// Host: this file imports only the binding-free `pumpkin_api_core` (the host
// `pumpkin_api` is wasm-only), so the tests can read the item table on the VM.
//
// The registration order is the Java one (`SimJavaOrder.items`), which
// `SimRegistry` pins with `useOrder`: the block items first, in `SimBlocks`
// order, then these standalone items in `SimItems` field order. The items of the
// Java that this port has not translated yet (the rope coupling, the gyroscopic
// mechanism and its incomplete form, the engine assembly and its incomplete
// form, the physics staff, the plunger launcher) are not registered, and
// `SimRegistry` reports them as the gap.
//
// Java: dev.simulated_team.simulated.index.SimItems
// ignore_for_file: implementation_imports
import 'package:pumpkin_api/pumpkin_api_core.dart' show ItemRegistration;

/// The item keys.
abstract final class SimItemKeys {
  static const String spring = 'simulated:spring';
  static const String honeyGlue = 'simulated:honey_glue';
  static const String contraptionDiagram = 'simulated:contraption_diagram';
}

/// The items of the mod, in registration order.
///
/// `simulated:spring` is not a block item: `SimItems.SPRING` is a `SpringItem`
/// (`SimItems.java:41-54`), and `SimBlocks.SPRING` registers no item, so this
/// list is the only registration of the key.
List<ItemRegistration> simItems() => const [
  ItemRegistration(key: SimItemKeys.contraptionDiagram),
  ItemRegistration(key: SimItemKeys.spring),
  ItemRegistration(key: SimItemKeys.honeyGlue),
];