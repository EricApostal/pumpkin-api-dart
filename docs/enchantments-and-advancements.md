# Enchantment effects and runtime advancements

## Enchantment effects and costs (`enchantments.wit`, `item-stack.wit`)

Wrappers in `enchantments.dart`: `EnchantmentManagerEffects` (on
`EnchantmentManager`), `EnchantedItemStack` (on `ItemStack`). The registration
of the enchantment itself is `EnchantmentBuilder`.

```dart
final manager = context.getServer().getEnchantmentManager();
await manager.registerEffectType('my_plugin:crush');             // after the vanilla types
await manager.setEffects('my_plugin:crusher',
    [EnchantmentEffectSpec('my_plugin:crush', valueNbt)]);        // network NBT value
await manager.setCosts('my_plugin:crusher',
    minBase: 5, minPerLevel: 8, maxBase: 25, maxPerLevel: 8);

final level = await stack.enchantmentLevelOf('my_plugin:crusher'); // 0 if absent
final effect = await stack.enchantmentEffect('my_plugin:crush');   // [{enchantment, level, value}] or null
```

The effect components are part of the `minecraft:enchantment` registry data sent
to every client (NeoForge clients also get the new component type). The host
stores and syncs them but does **not evaluate** the effects of plugin
enchantments, and there is no anvil or enchanting table support for them: read
`enchantmentEffect` in your own events. Errors throw `HostException`.

## Runtime advancements (`advancement.wit`, `player.wit`)

Wrappers in `advancements.dart`: `Advancements`, `AdvancementSpec`,
`AdvancementCriterion`, `PlayerCriterionTriggers`.

```dart
Advancements.registerTrigger('my_plugin:crushed');
Advancements.register(const AdvancementSpec(
  id: 'my_plugin:crush_ore', title: 'Crusher', description: 'Crush an ore.',
  icon: 'minecraft:iron_ore', frame: 'goal',
  criteria: {'crush': AdvancementCriterion.tagged('my_plugin:crushed', 'iron')},
));
final awarded = await player.fireCriterion('my_plugin:crushed', matcher: 'iron');
Advancements.unregister('my_plugin:crush_ore');
```

`registerJson` takes the datapack advancement JSON by hand. Online players get
the updated tree; plugin advancements survive datapack reloads and replace
datapack ones with the same id. The host only reads the string `plugin_tag` of a
criterion's conditions; **other conditions are kept as data and not evaluated**,
so the plugin decides when to fire. Triggers no plugin registered are accepted
but never fire.
