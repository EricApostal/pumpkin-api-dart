// Entity type keys as the contraption code compares them (`minecraft:minecart`).
//
// The host reports a vanilla entity's type only as its kebab-case wire name (`chest-minecart`,
// `EntityType.wireName`); a plugin type has its registered `namespace:path` key. Every check in
// the contraption code (the cart assembler's carts, passengers, the collider) uses the
// namespaced, snake_case key, so the wire name is mapped here once. Pure: no host imports, so
// the mapping is unit tested on the VM.

/// The `namespace:path` key of an entity type: [pluginKey] when the host reported one, else
/// `minecraft:` plus [wireName] in snake_case (`minecart` -> `minecraft:minecart`).
String entityTypeKey({String? pluginKey, required String wireName}) =>
    pluginKey ?? 'minecraft:${wireName.replaceAll('-', '_')}';

/// The key of an entity type from what the host reports: a plugin key, a vanilla wire name, or
/// neither (an inconsistent host). [pluginKey] wins, and `null` means "no type".
///
/// The plugin key is checked first: `Entity.getType()` returns `null` for a plugin entity (its
/// type is registered at runtime and has no `EntityType` variant), so a caller must never read the
/// wire name before it knows the entity is vanilla.
String? hostTypeKey({String? pluginKey, String? wireName}) {
  if (pluginKey != null) return pluginKey;
  if (wireName == null) return null;
  return entityTypeKey(wireName: wireName);
}

/// `AbstractMinecart` variants: `MinecartRef.canAssemble` and the collision/riding checks of the
/// contraption code (`_isMinecartType`).
const Set<String> minecartEntityTypeKeys = {
  'minecraft:minecart',
  'minecraft:chest_minecart',
  'minecraft:furnace_minecart',
  'minecraft:hopper_minecart',
  'minecraft:command_block_minecart',
};

/// Whether [key] is a minecart type (`AbstractMinecart`).
bool isMinecartEntityType(String key) => minecartEntityTypeKeys.contains(key);
