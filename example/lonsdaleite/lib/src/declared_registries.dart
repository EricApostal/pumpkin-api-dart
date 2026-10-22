// The registries the plugin registers content into, as the NeoForge declaration
// names them (`neoforge.dart`).
//
// Naming a registry is what vouches for its content: the host numbers a plugin's
// entries in a registry it numbers itself (`vanilla count + registration index`) and
// writes those ids in chunk data and packets, and a host-numbered registry is sent
// whole or not at all
// (`crates/pumpkin-core/src/net/neoforge/registries.rs`, `syncable`) — so a registry
// the plugin registered into but did not name is dropped from the sync for *every*
// plugin, and a client that was not sent it resolves each id against its own order: a
// different item or block, silently.
//
// Binding-free (no host imports), so `test/declaration_test.dart` can hold this list
// against what the plugin registers and against the declaration on the plain VM.
library;

/// The registries the plugin registers content into, in the order the host numbers
/// them: the items of the manifest (`item_install.dart`, `minecraft:item`) and the
/// wardframe block (`block_install.dart`, `minecraft:block`).
///
/// Both are host-numbered, so the declaration's `entries` are ignored for them: the
/// entries sent are the host's dynamic registry, which is exactly what the plugin
/// registered, in this order.
const List<String> lonsdaleiteDeclaredRegistries = [
  'minecraft:item',
  'minecraft:block',
];