/// Registers the wardframe with the host and checks the ids the host gave it.
/// Binding-free (it works on a [BlockRegistryBackend]), so it is tested with a
/// fake backend; the plugin passes `BlockRegistries.host`.
library;

import 'package:pumpkin_api/pumpkin_api_core.dart';

import 'block_definition.dart';
import 'item_install.dart';
import 'manifest.dart';

/// The outcome of [installManifestBlock].
final class BlockInstallation {
  /// What was registered.
  final BlockDefinition definition;

  /// What the host reports about the block after the registration: its id,
  /// the first state id, the state count, and the item linked to it.
  final RegisteredBlock block;

  /// The host's vanilla block count, which is also the id of the first custom
  /// block.
  final int vanillaBlockCount;

  /// The host's vanilla state count, which is also the first state id of the
  /// first custom block.
  final int vanillaStateCount;

  /// The id of the block's default state (what a plain placement starts as).
  final int defaultStateId;

  /// The block tags that were registered (tag ids).
  final List<String> blockTags;

  const BlockInstallation({
    required this.definition,
    required this.block,
    required this.vanillaBlockCount,
    required this.vanillaStateCount,
    required this.defaultStateId,
    required this.blockTags,
  });

  /// The id of state [stateValues] (property name to `true`/`false`).
  int stateId(Map<String, String> stateValues) =>
      definition.layout.stateId(block.baseStateId, stateValues);
}

/// Registers the block of [manifest] with [backend], in this order:
///
/// 1. checks that the host's vanilla block and state counts are the ones the
///    registry sync was built for ([expectedVanillaBlocks],
///    [expectedVanillaStates]), and that the block's definition is valid;
/// 2. `register-block` (the block item must be among [items] already: items
///    are registered first);
/// 3. checks that the host reports the id `vanillaBlockCount + 0`, the base
///    state id [expectedVanillaStates] and the state count the definition
///    computes, and that the state numbering of the host equals the one the
///    mod's Java uses (every state of the manifest);
/// 4. `set-block-item` (the block item places the block, the block drops it);
/// 5. `register-block-tag` for every block tag of the manifest;
/// 6. asks the host again (`get-registered-blocks`, `get-state-id`) and
///    compares with what the plugin computed.
///
/// Throws a [BlockRegistryException] with a message that says what to do; the
/// plugin must not go on then, or clients would be told the wrong ids.
BlockInstallation installManifestBlock(
  Manifest manifest,
  BlockRegistryBackend backend, {
  required ItemInstallation items,
  required int expectedVanillaBlocks,
  required int expectedVanillaStates,
}) {
  final b = manifest.block;
  final definition = blockDefinitionFor(manifest);
  definition.check();
  final stateIssues = blockStateIssues(manifest);
  if (stateIssues.isNotEmpty) {
    throw BlockRegistryException(
      'The state numbering of `${b.id}` differs from the mod\'s:\n  ${stateIssues.join('\n  ')}',
    );
  }

  BlockRegistryChecks.checkVanillaCounts(
    backend,
    expectedBlocks: expectedVanillaBlocks,
    expectedStates: expectedVanillaStates,
  );
  final vanillaBlockCount = backend.vanillaBlockCount;
  final vanillaStateCount = backend.vanillaStateCount;

  final blockItem = items.items.where((i) => i.key == b.item).firstOrNull;
  if (blockItem == null) {
    throw BlockRegistryException(
      'The item `${b.item}` of the block `${b.id}` is not registered. '
      'Register the items first: the host links an existing custom item to '
      'the block.',
    );
  }

  final id = backend.register(definition);
  final reported = backend.registeredBlocks;
  BlockRegistryChecks.checkAssigned(
    vanillaBlockCount: vanillaBlockCount,
    vanillaStateCount: vanillaStateCount,
    definitions: [definition],
    reported: reported,
  );
  final entry = reported.single;
  if (entry.id != id) {
    throw BlockRegistryException(
      '`${b.id}` was registered with id $id, but the host reports ${entry.id}.',
    );
  }

  backend.setBlockItem(b.item, b.id);

  final tags = <String>[];
  for (final tag in manifest.tags['block']?.values ?? const <TagFile>[]) {
    if (tag.replace) {
      throw BlockRegistryException(
        'The tag `${tag.id}` has "replace": true, which the host cannot do '
        '(it only adds entries to tags).',
      );
    }
    backend.registerTag(tag.id, tag.values);
    tags.add(tag.id);
  }

  // Ask the host again: what it reports is what the packets will carry.
  final after = backend.registeredBlocks
      .where((e) => e.key == b.id)
      .firstOrNull;
  if (after == null ||
      after !=
          RegisteredBlock(
            key: entry.key,
            id: entry.id,
            baseStateId: entry.baseStateId,
            stateCount: entry.stateCount,
            itemId: blockItem.id,
          )) {
    throw BlockRegistryException(
      '`${b.id}` should be $id with item ${blockItem.id} after linking its '
      'item, but the host reports ${after ?? 'no such block'}.',
    );
  }
  if (backend.idOf(b.id) != id) {
    throw BlockRegistryException(
      '`${b.id}` has id $id, but get-block-id says ${backend.idOf(b.id)}.',
    );
  }
  BlockRegistryChecks.checkStateIds(
    backend,
    definition,
    baseStateId: entry.baseStateId,
  );

  return BlockInstallation(
    definition: definition,
    block: after,
    vanillaBlockCount: vanillaBlockCount,
    vanillaStateCount: vanillaStateCount,
    defaultStateId: entry.baseStateId + definition.layout.defaultStateIndex,
    blockTags: tags,
  );
}
