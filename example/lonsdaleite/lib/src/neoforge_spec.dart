/// The registry sync's view of the mod, derived from the manifest and from
/// what the host actually registered. Binding-free.
library;

import 'package:pumpkin_api/pumpkin_api_core.dart'
    show BlockRegistryException, RegisteredBlock, RegisteredItem;
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart';

import 'manifest.dart';

/// The NeoForge server spec for [manifest]: the vanilla item and block
/// registries with the mod's entries appended.
///
/// * `minecraft:item`: the mod's items in the order and with the ids the
///   host assigned ([items], from the registration), so the snapshot the
///   client applies is exactly what the server's packets use. The list must
///   be contiguous from the vanilla count, which [installManifestItems]
///   checks.
/// * `minecraft:block`: the wardframe, after the vanilla blocks, with the id
///   the host assigned ([blocks]; [verifyBlocksAgainstSpec] checks it). The
///   client numbers block states by walking this registry in id order and
///   appending each block's states (`NeoForgeRegistryCallbacks.BlockCallbacks`),
///   so the states of the wardframe start right after the vanilla states: id
///   [vanillaBlockStateCount] and on, in the order of Java's `StateDefinition`
///   (which the host's `block-registry` replicates; see docs/block-registry.md).
///
/// The mod id, name and version come from the manifest, so the spec follows
/// the mod the manifest was generated from.
NeoForgeServerSpec neoForgeSpecFor(
  Manifest manifest,
  List<RegisteredItem> items, {
  required List<RegisteredBlock> blocks,
}) {
  final spec = NeoForgeServerSpec.vanillaPlus(
    mods: [
      NeoForgeModInfo(
        id: manifest.mod.id,
        version: manifest.mod.version,
        displayName: manifest.mod.name,
      ),
    ],
    additions: {
      'minecraft:block': [for (final block in blocks) block.key],
      'minecraft:item': [for (final item in items) item.key],
    },
  );
  verifyBlocksAgainstSpec(spec, blocks);
  return spec;
}

/// Throws a [BlockRegistryException] unless the blocks the host reports sit
/// where [spec] puts them for a client: the block with id `i` is entry `i` of
/// the `minecraft:block` registry, and the states of the custom blocks, in id
/// order, follow the [vanillaBlockStateCount] vanilla states without a gap.
///
/// The sync sends only the registry; a client derives every state id from it.
/// So this is the whole agreement about block states: the first state id and
/// the number of states per block (the host's state order is checked against
/// the mod's table when the block is registered).
void verifyBlocksAgainstSpec(
  NeoForgeServerSpec spec,
  List<RegisteredBlock> blocks,
) {
  final registry = spec.registries
      .where((r) => r.key == 'minecraft:block')
      .firstOrNull;
  if (registry == null) {
    throw BlockRegistryException('The spec has no minecraft:block registry.');
  }
  final vanilla = VanillaRegistries.require('minecraft:block').length;
  var nextState = vanillaBlockStateCount;
  for (final block in blocks) {
    if (block.id >= registry.length ||
        registry.entries[block.id] != block.key) {
      throw BlockRegistryException(
        '`${block.key}` has block id ${block.id} on the host, but the '
        'registry sync lists '
        '${block.id < registry.length ? '`${registry.entries[block.id]}`' : 'nothing'} '
        'there ($vanilla vanilla blocks, ${registry.length} entries).',
      );
    }
    if (block.baseStateId != nextState) {
      throw BlockRegistryException(
        'The states of `${block.key}` start at id ${block.baseStateId} on the '
        'host, but a client numbers them from $nextState ($vanillaBlockStateCount '
        'vanilla states plus the states of the custom blocks before it).',
      );
    }
    nextState += block.stateCount;
  }
  if (registry.length != vanilla + blocks.length) {
    throw BlockRegistryException(
      'The spec lists ${registry.length - vanilla} custom blocks, the host has ${blocks.length}.',
    );
  }
}
