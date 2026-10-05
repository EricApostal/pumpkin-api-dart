# Registering custom items

Pumpkin's items are compile-time tables; the `item-registry` interface appends
items at runtime. A plugin needs the `registry.items` permission
(`Permissions.registryItems` in `PluginInfo.permissions`) and registers while the
server loads (`Plugin.onLoad`, `ServerLoadEvent`): the host closes the registry
before players can connect.

Vanilla items have the ids `0 ..< vanillaCount`; custom items get
`vanillaCount + n`, `n` being the order of registration across all plugins (a
client with a mod is told these ids by the registry sync, see
[neoforge-protocol.md](neoforge-protocol.md)). Registering a key again with
identical components returns the existing item, so reloads keep the ids.

```dart
final encoded = DataComponentCodec.encodeAll({
  'minecraft:max_damage': 250,
  'minecraft:enchantable': {'value': 10},
  'minecraft:repairable': {'items': '#my_plugin:repairs_ruby'},
});
final id = ItemRegistries.host.register(
  ItemRegistration(key: 'my_plugin:ruby_sword', components: encoded.encoded),
);
ItemRegistries.host.registerTag('minecraft:swords', ['my_plugin:ruby_sword']);
```

## What is in `package:pumpkin_api`

* `ItemRegistries.host` (`ItemRegistryBackend`): `register`, `registerTag`, `idOf`,
  `keyOf`, `vanillaCount`, `vanillaItems`, `registeredItems`. Failures are an
  `ItemRegistryException` with the host's message. The generated names
  (`ItemRegistry`, `ItemDefinition`, `ItemEntry`, `itemRegistry`) are hidden.
* `ItemRegistryChecks`: `checkVanillaItems` (the host's vanilla list is the one you
  expect) and `checkAssignedIds` (ids are `vanillaCount + index`); use them when
  clients depend on the ids.
* `DataComponentCodec`: vanilla-format JSON -> the bytes `register-item` and
  `set-component` take, for 27 components (`DataComponentCodec.supported`).
  `encodeAll` skips the components the host cannot read
  (`notReadByHost`: `block_transformer`, `interact_animation` and ten more) and
  reports them; every other failure is a `ComponentEncodeException`.
* `VanillaIds`: the registry ids that component values use (sounds, blocks,
  attributes, damage types, mob effects, entity types, enchantments, items, data
  component types), generated from Pumpkin's assets by
  `packages/pumpkin_api/tool/generate_registry_ids.dart`.

All of it except `ItemRegistries.host` is in `package:pumpkin_api/pumpkin_api_core.dart`,
which has no host imports and runs on the Dart VM (tests, tools).

## What the host does with the bytes

The host decodes each value with the network reader of that component
(`crates/pumpkin-protocol/src/codec/data_component.rs`), which is **not** the
inverse of every writer and **drops some fields**: notably `attribute_modifiers`
(read, then discarded: an item registered through the WIT has none), `use_effects`,
`tooltip_display`, `break_sound` and the shield-disable time of `weapon`;
`item_name` is read as a plain translation key. A component without a reader makes
`register-item` fail. The table is in
[example/lonsdaleite/docs/registration.md](../example/lonsdaleite/docs/registration.md#what-the-host-keeps),
and `example/lonsdaleite` is the complete example.
