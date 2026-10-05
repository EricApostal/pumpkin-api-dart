// Registers CC: Tweaked's block entity types, menu types and data component
// types with the host and checks every id it gives back against the registry
// sync (`CcRegistries`). Binding-free: it works on the backends of
// `pumpkin_api_core`, the plugin passes the `.host` ones.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../protocol/components.dart';
import '../protocol/registries.dart';

/// What [installCcRegistries] registered.
final class CcRegistryInstallation {
  final List<RegisteredType> blockEntityTypes;
  final List<RegisteredType> menus;
  final List<RegisteredType> componentTypes;

  const CcRegistryInstallation(this.blockEntityTypes, this.menus, this.componentTypes);
}

/// Registers the 16 block entity types, 7 menu types and 14 data component
/// types, in the order of the registry sync, and verifies them.
///
/// Every registry is checked the same way: the host's vanilla count must be the
/// one the sync was built for (`expected*VanillaCount`, the length of the
/// vanilla list the plugin knows), every register call must return
/// `vanillaCount + position`, and afterwards the host's list of plugin entries
/// must be exactly CC's list (so no other plugin registered first). A mismatch
/// throws a [PluginRegistryException] that says what to fix, because a client
/// would otherwise draw and open other things than the server means.
///
/// Call it after the items and blocks are registered (the same order the sync
/// lists its registries in), while the server loads.
CcRegistryInstallation installCcRegistries({
  required BlockEntityTypeBackend blockEntityTypes,
  required MenuTypeBackend menus,
  required ComponentTypeBackend componentTypes,
  required int expectedBlockEntityVanillaCount,
  required int expectedMenuVanillaCount,
  required int expectedComponentVanillaCount,
}) {
  // Block entity types.
  _checkVanilla('minecraft:block_entity_type', blockEntityTypes.vanillaCount, expectedBlockEntityVanillaCount);
  _checkNoneYet('minecraft:block_entity_type', blockEntityTypes.registered, CcRegistries.blockEntityTypes);
  for (var i = 0; i < CcRegistries.blockEntityTypes.length; i++) {
    final key = CcRegistries.blockEntityTypes[i];
    final id = blockEntityTypes.register(key, CcBlockEntityTypes.validBlocks(key));
    _checkId('minecraft:block_entity_type', key, id, expectedBlockEntityVanillaCount + i);
  }
  PluginRegistryChecks.checkSequence(
    'minecraft:block_entity_type',
    expectedVanillaCount: expectedBlockEntityVanillaCount,
    vanillaCount: blockEntityTypes.vanillaCount,
    expectedKeys: CcRegistries.blockEntityTypes,
    registered: blockEntityTypes.registered,
  );

  // Menu types.
  _checkVanilla('minecraft:menu', menus.vanillaCount, expectedMenuVanillaCount);
  _checkNoneYet('minecraft:menu', menus.registered, CcRegistries.menus);
  for (var i = 0; i < CcRegistries.menus.length; i++) {
    final key = CcRegistries.menus[i];
    _checkId('minecraft:menu', key, menus.register(key), expectedMenuVanillaCount + i);
  }
  PluginRegistryChecks.checkSequence(
    'minecraft:menu',
    expectedVanillaCount: expectedMenuVanillaCount,
    vanillaCount: menus.vanillaCount,
    expectedKeys: CcRegistries.menus,
    registered: menus.registered,
  );

  // Data component types. The list in the codec table must be the sync's list.
  if (CcComponents.all.length != CcRegistries.dataComponentTypes.length) {
    throw PluginRegistryException(
      'The component table has ${CcComponents.all.length} types, the registry sync ${CcRegistries.dataComponentTypes.length}.',
    );
  }
  _checkVanilla('minecraft:data_component_type', componentTypes.vanillaCount, expectedComponentVanillaCount);
  _checkNoneYet('minecraft:data_component_type', componentTypes.registered, CcRegistries.dataComponentTypes);
  for (var i = 0; i < CcComponents.all.length; i++) {
    final type = CcComponents.all[i];
    if (type.key != CcRegistries.dataComponentTypes[i]) {
      throw PluginRegistryException(
        'The component table has `${type.key}` at position $i, but the registry sync lists `${CcRegistries.dataComponentTypes[i]}`.',
      );
    }
    final id = componentTypes.register(type.key, persistent: type.persistent, codec: type.codec);
    _checkId('minecraft:data_component_type', type.key, id, expectedComponentVanillaCount + i);
  }
  PluginRegistryChecks.checkSequence(
    'minecraft:data_component_type',
    expectedVanillaCount: expectedComponentVanillaCount,
    vanillaCount: componentTypes.vanillaCount,
    expectedKeys: CcRegistries.dataComponentTypes,
    registered: componentTypes.registered,
  );

  return CcRegistryInstallation(blockEntityTypes.registered, menus.registered, componentTypes.registered);
}

void _checkVanilla(String registry, int host, int expected) {
  if (host != expected) {
    throw PluginRegistryException(
      'The host has $host vanilla entries in `$registry`, the registry sync was built for $expected: '
      'the ids CC: Tweaked announces to the client would be wrong. Update the vanilla lists '
      '(pumpkin_neoforge `vanilla_registries.g.dart`) or the host.',
    );
  }
}

void _checkNoneYet(String registry, List<RegisteredType> registered, List<String> ours) {
  // Entries of CC itself are fine: a reloaded plugin registers the same ones again.
  final others = [
    for (final e in registered)
      if (!ours.contains(e.key)) e.key,
  ];
  if (others.isNotEmpty) {
    throw PluginRegistryException(
      'The host already has plugin entries in `$registry` (${others.join(', ')}). '
      'The ids CC: Tweaked tells the client start right after the vanilla entries, so this plugin must be '
      'the first to register.',
    );
  }
}

void _checkId(String registry, String key, int id, int expected) {
  if (id != expected) {
    throw PluginRegistryException(
      '`$key` got id $id in `$registry`, but the registry sync tells the client $expected.',
    );
  }
}
