// Registers CC: Tweaked's blocks with the host and checks every id the host
// gives back. Binding-free (it works on a `BlockRegistryBackend`; the plugin
// passes `BlockRegistries.host`).
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../protocol/blocks.dart';
import '../protocol/registries.dart';

/// What [installCcBlocks] did.
final class CcBlockInstallation {
  /// The registered blocks with the ids the host reports, in id order.
  final List<RegisteredBlock> blocks;

  /// The plans they came from (same order).
  final List<CcBlockPlan> plans;

  /// The blocks of CC that were left out, and why.
  final List<String> skipped;

  /// The tags that were registered.
  final List<String> tags;

  const CcBlockInstallation(this.blocks, this.plans, this.skipped, this.tags);

  /// The number of states the host has for CC's blocks.
  int get hostStates => blocks.fold(0, (sum, b) => sum + b.stateCount);

  /// The plans whose block lacks states the client has.
  List<CcBlockPlan> get incomplete => [for (final p in plans) if (!p.complete) p];
}

/// Registers the blocks of [CcBlockCatalog.plan] and their tags, links their
/// items, and verifies the result.
///
/// The items must be registered already (`set-block-item` needs an existing
/// custom item), in the order of [CcRegistries.items], the first id being
/// [firstItemId] (the host's vanilla item count). Steps:
///
/// 1. the host has the vanilla block and state counts the registry sync was
///    built for ([expectedVanillaBlocks], [expectedVanillaStates]) and no other
///    plugin registered blocks first;
/// 2. `register-block` for every planned block, in the order of
///    [CcRegistries.blocks];
/// 3. the host reports block id `vanillaBlockCount + position`, base state ids
///    that follow the vanilla states with no gap, and the state counts the
///    definitions describe; the state ids of the host (`get-state-id`) equal
///    the layout's; and every state of a reduced block has the id the client
///    computes from CC's own property definitions;
/// 3b. when a [placement] backend is given, `set-block-placement-rules` for the blocks
///    whose Java `getStateForPlacement` chooses properties (`CcBlockSpec.placement`);
/// 4. `set-block-item` for every block that has an item, and the host reports
///    the item id the registry sync tells the client;
/// 5. `register-block-tag` for the tags of [CcBlockCatalog.tags].
///
/// Throws a [BlockRegistryException] that says which side to fix; the plugin
/// must not go on then, because clients would be told wrong ids.
CcBlockInstallation installCcBlocks(
  BlockRegistryBackend backend, {
  required int expectedVanillaBlocks,
  required int expectedVanillaStates,
  required int firstItemId,
  int? maxStatesPerBlock,
  BlockPlacementBackend? placement,
}) {
  // The sync lists the blocks in this order; the plan must be a prefix of it.
  final plans = CcBlockCatalog.plan(maxStatesPerBlock: maxStatesPerBlock ?? BlockRegistryChecks.maxStatesPerBlock);
  for (var i = 0; i < plans.length; i++) {
    if (plans[i].spec.key != CcRegistries.blocks[i]) {
      throw BlockRegistryException(
        'The block catalog has `${plans[i].spec.key}` at position $i, but the registry sync lists `${CcRegistries.blocks[i]}`.',
      );
    }
  }
  if (CcBlockCatalog.all.length != CcRegistries.blocks.length) {
    throw BlockRegistryException(
      'The block catalog has ${CcBlockCatalog.all.length} blocks, the registry sync ${CcRegistries.blocks.length}.',
    );
  }
  final skipped = [
    for (final spec in CcBlockCatalog.all.skip(plans.length))
      '${spec.key}: it follows a block with states the host cannot have, so its state ids would not match the client\'s',
  ];

  BlockRegistryChecks.checkVanillaCounts(
    backend,
    expectedBlocks: expectedVanillaBlocks,
    expectedStates: expectedVanillaStates,
  );
  final vanillaBlocks = backend.vanillaBlockCount;
  final vanillaStates = backend.vanillaStateCount;
  if (backend.registeredBlocks.isNotEmpty) {
    throw BlockRegistryException(
      'The host already has custom blocks (${backend.registeredBlocks.map((b) => b.key).join(', ')}). '
      'The ids CC: Tweaked tells the client start right after the vanilla blocks, so this plugin must be '
      'the first to register blocks.',
    );
  }

  // 2. Register.
  final definitions = [for (final p in plans) p.definition];
  for (var i = 0; i < plans.length; i++) {
    final id = backend.register(definitions[i]);
    if (id != vanillaBlocks + i) {
      throw BlockRegistryException(
        '`${plans[i].spec.key}` got block id $id, but the registry sync tells the client ${vanillaBlocks + i}.',
      );
    }
  }

  // 2b. How placing a block chooses its properties (`block-placement.wit`).
  if (placement != null) {
    for (final plan in plans) {
      if (plan.spec.placement.isEmpty) continue;
      try {
        placement.setRules(plan.spec.key, plan.spec.placement);
      } on PluginRegistryException catch (e) {
        throw BlockRegistryException(e.message);
      }
    }
  }

  // 3. What the host reports.
  final reported = backend.registeredBlocks;
  BlockRegistryChecks.checkAssigned(
    vanillaBlockCount: vanillaBlocks,
    vanillaStateCount: vanillaStates,
    definitions: definitions,
    reported: reported,
  );
  // The client numbers CC's states after the vanilla ones with Java's counts;
  // the host's range for each block must start where the client's does.
  var clientBase = vanillaStates;
  for (var i = 0; i < plans.length; i++) {
    final plan = plans[i];
    if (reported[i].baseStateId != clientBase) {
      throw BlockRegistryException(
        'The states of `${plan.spec.key}` start at ${reported[i].baseStateId} on the host, but the client numbers '
        'them from $clientBase (the blocks before it have ${clientBase - vanillaStates} states in CC: Tweaked).',
      );
    }
    clientBase += plan.clientStates;
  }
  for (var i = 0; i < plans.length; i++) {
    BlockRegistryChecks.checkStateIds(
      backend,
      definitions[i],
      baseStateId: reported[i].baseStateId,
    );
    final plan = plans[i];
    if (!plan.complete) {
      // Every state the host has must be the state the client means by that id.
      for (var s = 0; s < plan.hostStates; s++) {
        final client = plan.clientIndexOf(s);
        if (client != s) {
          throw BlockRegistryException(
            '`${plan.spec.key}`: state $s of the host is state $client of the client '
            '(${plan.definition.layout.valuesAt(s)}), leaving out ${plan.omitted.join(', ')} renumbered it.',
          );
        }
      }
    }
  }

  // 4. Items. `entry.itemId` is the host's id of the linked item.
  for (var i = 0; i < plans.length; i++) {
    final spec = plans[i].spec;
    final itemKey = spec.itemKey;
    if (itemKey == null) continue;
    try {
      backend.setBlockItem(itemKey, spec.key);
    } on BlockRegistryException catch (e) {
      throw BlockRegistryException(
        'The item `$itemKey` of the block `${spec.key}` could not be linked: ${e.message} '
        'Register the items first: the host links an existing custom item to the block.',
      );
    }
  }
  final linked = backend.registeredBlocks;
  for (var i = 0; i < plans.length; i++) {
    final spec = plans[i].spec;
    final itemKey = spec.itemKey;
    final entry = linked[i];
    if (entry.id != reported[i].id || entry.baseStateId != reported[i].baseStateId || entry.stateCount != reported[i].stateCount) {
      throw BlockRegistryException('`${spec.key}` changed from ${reported[i]} to $entry when its item was linked.');
    }
    if (backend.idOf(spec.key) != entry.id) {
      throw BlockRegistryException('`${spec.key}` has id ${entry.id}, but get-block-id says ${backend.idOf(spec.key)}.');
    }
    if (itemKey == null) continue;
    final position = CcRegistries.items.indexOf(itemKey);
    if (position < 0) {
      throw BlockRegistryException('The item `$itemKey` is not in the registry sync\'s item list.');
    }
    if (entry.itemId != firstItemId + position) {
      throw BlockRegistryException(
        '`${spec.key}` is linked to item ${entry.itemId}, but the registry sync tells the client $itemKey '
        'is item ${firstItemId + position}: register the items first and in the order of CcRegistries.items.',
      );
    }
  }

  // 5. Tags.
  final tags = <String>[];
  for (final entry in CcBlockCatalog.tagsFor(plans).entries) {
    backend.registerTag(entry.key, entry.value);
    tags.add(entry.key);
  }

  return CcBlockInstallation(linked, plans, skipped, tags);
}
