/// The wardframe as a host block definition, derived from the manifest.
/// Binding-free.
library;

import 'package:pumpkin_api/pumpkin_api_core.dart';

import 'manifest.dart';

/// The [BlockDefinition] the plugin registers for [manifest]'s block.
///
/// Everything comes from the manifest (the mod's Java `BlockBehaviour.Properties`
/// and `createBlockStateDefinition`):
///
/// * `strength(5.0F, 1200.0F)`, `requiresCorrectToolForDrops()`,
///   `sound(AMETHYST)`, `lightLevel(7)`, `noOcclusion()`,
///   `isSuffocating(false)`;
/// * one boolean property per direction (the property is named after the
///   direction, which is how the mod's `updateShape` works), default
///   `false`, each following the neighbour in that direction when it is the
///   same block (`connect-rules`);
/// * a full cube for collision and selection (the mod's per-entity empty
///   collision is not modelled, see README.md);
/// * drops: the block's item when the loot table is "one of the block item",
///   otherwise the loot table by key.
///
/// The block's tags are not part of the definition: [installManifestBlock]
/// registers the manifest's block tags with `register-block-tag`.
BlockDefinition blockDefinitionFor(Manifest manifest) {
  final b = manifest.block;
  for (final name in b.properties) {
    if (!ConnectDirection.values.any((d) => d.name == name)) {
      throw StateError(
        '${b.id}: the property `$name` is not a direction, so it has no connect rule.',
      );
    }
  }
  if (b.collisionDefault != 'full_cube') {
    throw StateError(
      '${b.id}: the collision shape `${b.collisionDefault}` is not supported '
      '(only full_cube).',
    );
  }
  return BlockDefinition(
    key: b.id,
    properties: [for (final name in b.properties) BlockProperty.boolean(name)],
    defaultState: {
      for (final name in b.properties)
        name: (b.defaults[name] ?? false) ? 'true' : 'false',
    },
    hardness: b.destroyTime,
    blastResistance: b.explosionResistance,
    requiresCorrectTool: b.requiresCorrectToolForDrops,
    soundType: b.soundType,
    luminance: b.lightLevel,
    canOcclude: b.canOcclude,
    suffocating: b.isSuffocating,
    replaceable: b.replaceable,
    collisionShape: BlockShape.fullCube,
    selectionShape: BlockShape.fullCube,
    connectRules: [
      for (final name in b.properties)
        ConnectRule(
          property: name,
          direction: ConnectDirection.values.byName(name),
          target: const ConnectTarget.sameBlock(),
        ),
    ],
    drops: _dropsOf(manifest),
  );
}

BlockDrops _dropsOf(Manifest manifest) {
  final b = manifest.block;
  final table = manifest.lootTables
      .where((t) => t.id == b.lootTable)
      .firstOrNull;
  if (table == null) return BlockDrops.nothing;
  final items = table.items;
  return items.length == 1 && items.single == b.item
      ? BlockDrops.selfItem
      : BlockDrops.lootTable(table.id);
}

/// Differences between the state numbering the host will use (computed from
/// the definition, [BlockStateLayout]) and the table the mod's Java produces
/// (`block_state` in the manifest: `state_order`, `state_count`,
/// `default_state_index` and every state). The client numbers the states with
/// Java's `StateDefinition`; if this is not empty the host and the client would
/// disagree about every state of the block.
List<String> blockStateIssues(Manifest manifest) {
  final b = manifest.block;
  final layout = blockDefinitionFor(manifest).layout;
  final issues = <String>[];
  if (!_same(layout.propertyNames, b.stateOrder)) {
    issues.add(
      '${b.id}: the host sorts the properties as ${layout.propertyNames}, the mod as ${b.stateOrder}.',
    );
  }
  if (layout.stateCount != b.stateCount || b.states.length != b.stateCount) {
    issues.add(
      '${b.id}: ${layout.stateCount} states computed, ${b.stateCount} in the manifest '
      '(${b.states.length} listed).',
    );
    return issues;
  }
  if (layout.defaultStateIndex != b.defaultStateIndex) {
    issues.add(
      '${b.id}: the default state is index ${layout.defaultStateIndex}, the manifest says ${b.defaultStateIndex}.',
    );
  }
  for (var i = 0; i < b.stateCount; i++) {
    final computed = layout.valuesAt(i);
    final listed = {for (final e in b.states[i].entries) e.key: '${e.value}'};
    if (computed.length != listed.length ||
        computed.entries.any((e) => listed[e.key] != e.value)) {
      issues.add('${b.id}: state $i is $computed, the manifest lists $listed.');
      break;
    }
  }
  return issues;
}

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
