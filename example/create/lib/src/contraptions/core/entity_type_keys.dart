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
