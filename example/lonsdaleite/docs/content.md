# Lonsdaleite content manifest

`data/manifest.json` describes everything the [Lonsdaleite Tools](https://github.com/kestalkayden/Lonsdaleite)
NeoForge mod (CC0, Minecraft 26.3, NeoForge `26.3.0.7-beta`) adds, in the shape a
server needs to stand in for it. It is **generated**, never edited:

```sh
# from example/lonsdaleite
export LONSDALEITE_SRC=/path/to/Lonsdaleite     # a checkout of the mod
puro dart run tool/generate_manifest.dart                 # rewrite both files
puro dart run tool/generate_manifest.dart --check         # fail if they are stale
puro dart run tool/generate_manifest.dart --verify-vanilla /path/to/Pumpkin/assets/items.json
puro dart run tool/generate_manifest.dart --datapack out/lonsdaleite   # data/ as a data pack
```

The script writes `data/manifest.json` (readable) and `lib/src/manifest.g.dart`
(the same JSON as a Dart string constant). The plugin is compiled to a `.wasm`
that cannot read files shipped with it, so the embedded copy is what it parses
at load time. `test/manifest_test.dart` fails if the two differ, and
`test/generator_test.dart` regenerates the manifest from the mod sources when
`LONSDALEITE_SRC` is set and compares.

## How the values are obtained

The script reads the mod's Java (`neoforge/.../Lonsdaleite.java`, the classes
under `common/`) with a small parser for the subset of Java the mod uses. Each
`ITEMS.registerItem(...)` lambda is resolved to the `Item.Properties` call chain
it ends in, following constructors (`LonsdaleiteArmor` calls
`properties.humanoidArmor(material, type)`), the material classes
(`LonsdaleiteToolMaterials`, `LonsdaleiteArmorMaterials`) and the static
attribute builder of the mace. Anything the parser does not model (a new builder
call, a new `@Override`, a different lambda shape) stops the generation with a
`JavaParseError` instead of being skipped.

What each vanilla builder puts into the item's default components is modelled in
`tool/src/vanilla.dart`. There is no decompiled 26.3 source in this workspace,
so the model was read off the vanilla items in Pumpkin's `assets/items.json` (an
extractor dump of the real game) and **verified** against them:
`--verify-vanilla` rebuilds every vanilla wooden/stone/copper/iron/golden/diamond/
netherite pickaxe, axe, shovel, hoe, sword and spear, and the iron/golden/diamond/
netherite armor, through the model and compares all components. 60 items match
exactly (the checked-in fixture `test/fixtures/vanilla_items_subset.json` keeps a
subset of this as a regression test). The semantics that came out of it:

| Builder | Components |
| --- | --- |
| `pickaxe/axe/shovel/hoe(m, dmg, spd)` | `tool` with rules `[#m.incorrect_blocks_for_drops -> correct_for_drops false, #mineable/<type> -> speed m.speed, correct_for_drops true]`; `max_damage` `m.durability`, `max_stack_size` 1, `damage` 0; `repairable` `#m.repair_items`; `enchantable` `m.enchantment_value`; attribute modifiers `attack_damage = dmg + m.attack_damage_bonus` and `attack_speed = spd` (the modifier is added to the player's base of 4, it is not `4 + spd`); `weapon {item_damage_per_attack: 2}`. The axe adds `disable_blocking_for_seconds: 5.0`. Axe, shovel and hoe add `block_transformer` `minecraft:axe/shovel/hoe`. |
| `sword(m, dmg, spd)` | the same durability/repair/enchant/attributes, `tool` with the cobweb, `#sword_instantly_mines` and `#sword_efficient` rules, `damage_per_block 2`, `can_destroy_blocks_in_creative false`; `weapon {}` (1 durability per attack). The material speed does not appear. |
| `spear(m, swing, mult, delay, dismountT, dismountV, kbT, kbV, dmgT, dmgV)` | `kinetic_weapon` (times x20 cut to ticks, `forward_movement` 0.38, `damage_multiplier` `mult`, sounds `item.spear.*`), `piercing_weapon` (`item.spear.attack/hit`), `attack_range` (2.0 to 4.5, creative 6.5, margin 0.125, mob factor 0.5), `use_effects {can_sprint true, interact_vibrations false, speed_multiplier 1.0}`, `attack_animation {type stab, duration swing x20}`, `minimum_attack_charge 1.0`, `damage_type minecraft:spear`, `weapon {}`; attribute `attack_damage = m.attack_damage_bonus` and `attack_speed = 1/swing - 4` (a float division widened to double). |
| `humanoidArmor(m, type)` | `max_damage = m.durability x {helmet 11, chestplate 16, leggings 15, boots 13}`; `equippable {slot, equip_sound, asset_id}` (the defaults for `damage_on_hurt`, `dispensable`, `swappable` are not written); `repairable`; `enchantable`; attributes `armor` = defense, `armor_toughness` (always written, even 0.0) and `knockback_resistance` (only when above 0), all with id `minecraft:armor.<type>` and the slot of the piece. |
| `registerSimpleItem` and every item | `lore []`, `interact_animation {}`, `attack_animation {}`, `repair_cost 0`, `item_model <id>`, `break_sound`, `tooltip_display {}`, `use_effects {}`, `item_name {translate item.<ns>.<path>}`, `attribute_modifiers []`, `rarity common`, `max_stack_size 64`, `enchantments {}`. |

Numbers follow the extractor's JSON conventions, which the manifest copies so
that it can be diffed against Pumpkin's `items.json` and loaded by the same code:
a codec default is omitted, a Java `float` field prints as the shortest decimal
(`speed: 8.2`), a `double` field as the widened float (`amount: -2.799999952316284`
for `-2.8F`, but exactly `-3.4` for the mace, whose Java passes a `double`).

## Sections

`schema_version`, `generator`, `mod`
: Id, name, version (`2.3.0`), license, Minecraft/NeoForge versions from
  `gradle.properties` and `neoforge.mods.toml`, and the git commit of the sources.

`open_questions`
: Things the sources cannot settle; see the list below.

`materials.tool`, `materials.armor`
: The two tool tiers (`lonsdaleite`: durability 2800, speed 8.2, bonus 3, enchant 15;
  `perfect_lonsdaleite`: 3800, 9.0, 4, 20; both with the netherite
  `incorrect_for_netherite_tool` tag, so both mine like netherite) and two armor tiers
  (durability factor 44 and 60, defense 3/8/6/3 for both, toughness 2.0 and 3.0,
  knockback resistance 0 and 0.1, sounds diamond and netherite, assets
  `lonsdaleite:lonsdaleite` and `lonsdaleite:perfect_lonsdaleite`).

`items` (32, in registration order)
: Per item: `id`, `registration_index`, `kind`, `tier`, `translation_key`,
  `display_name` (from `en_us.json`), `java` (class, superclass, overridden methods,
  the builder calls as written), `behaviors` (ids from the `behaviors` section),
  `components` (the full default component map, vanilla JSON format), optionally
  `server_components` and `block`.

  | Kind | Count | Notes |
  | --- | --- | --- |
  | `material` | 4 | raw, prepared, refined ("Lonsdaleite Gem") and perfect gem; defaults only |
  | `block_item` | 1 | the wardframe item, registered first; `item_name` uses the block's key |
  | `pickaxe`, `axe`, `shovel`, `hoe` | 2 each | one per tier |
  | `omnitool` | 2 | built with `pickaxe(...)`; behaviour from Java overrides |
  | `sword`, `short_sword` ("Dagger"), `war_axe` | 2 each | all `sword(...)`; the war axe is a sword with attack 12/15 |
  | `spear` | 2 | damage multiplier 1.25 and 1.35 (netherite: 1.2) |
  | `mace` | 1 | hand-built: epic, 2640 durability, attack +7, speed -3.4, tag repair |
  | `armor` | 8 | four pieces per tier |

  `server_components` exists for the omnitools only: their Tool component with
  the mining speed rules that the Java `getDestroySpeed` override adds. It is for
  Pumpkin's own mining speed calculation; the client keeps using its Java code, so
  the stack sent to a client must not carry it (see `server-logic.md`).

`block`
: The wardframe: `destroy_time 5.0`, `explosion_resistance 1200.0`, sound type
  `amethyst`, `can_occlude false`, `requires_correct_tool_for_drops`, constant light
  level 7, not suffocating, not view blocking; six boolean state properties declared
  `north, south, east, west, up, down` (default all false); the 64 states in vanilla's
  state order (properties sorted by name, the first varying slowest, `true` before
  `false`, so all-false is index 63); collision rules; loot table; block and item tags;
  `vanilla_defaults` for properties the mod does not set (assumed, see the open
  questions). The two tags it joins are `minecraft:mineable/pickaxe` and
  `minecraft:needs_diamond_tool`; as an item it is also in `minecraft:doors`.

`creative_tabs`
: `own`: the tab `lonsdaleite:lonsdaleite` (title `itemGroup.lonsdaleite.item_group`,
  icon the refined gem, 32 items in display order, the wardframe fifth).
  `insertions`: 31 `insertAfter` steps into vanilla tabs: ingredients after
  `raw_gold`, tools and utilities after `netherite_hoe`, combat after `netherite_axe`
  (weapons) and `netherite_boots` (armor), each chained after the previous insertion.

`tags`
: 21 item tags and 2 block tags, verbatim. `lonsdaleite:repairs_lonsdaleite_tools` and
  `...repairs_perfect_lonsdaleite_tools` (refined / perfect gem) are the repair tags the
  `repairable` components point at. The rest extend vanilla tags: `axes`, `pickaxes`,
  `shovels`, `hoes`, `swords` (short sword and war axe included), `spears`, the four
  armor tags, `doors`, and `enchantable/{durability, mining, weapon, sharp_weapon, sword,
  mace, fire_aspect, vanishing}`. The omnitools are in the pickaxe, axe, shovel and hoe tags.

`recipes`
: 32 recipes, one per item: 30 `minecraft:crafting_shaped` and 2 `minecraft:blasting`
  (`refined` from `prepared`: 2000 ticks, 200 xp; `perfect` from `refined`: 4000 ticks,
  20 xp). The chain is 8 diamonds around an obsidian into raw, coal blocks and gunpowder
  into prepared, then smelting. Tools and armor use the refined gem (perfect tier: the
  perfect gem); the wardframe makes 8 from a ring of refined gems; the mace needs perfect
  gems and a breeze rod. Ingredients use the 26.x string form. Raw JSON is kept in `json`.

`loot_tables`
: One: the wardframe block drops itself (`survives_explosion`).

`behaviors`
: Every Java override and inherited behaviour, with the side it runs on, the items it
  applies to and a summary; see `server-logic.md`. The generator refuses an override it
  has no entry for.

`lang`
: All 36 English translations (the mod ships only `en_us.json`).

`client`
: What the client needs and the server does not serve: `resource_pack` lists the files
  of `assets/` by kind (32 item definitions, 36 models, 24 textures, 1 blockstate with
  twelve multipart cases, 2 equipment definitions, the language file, the icon),
  `pack_meta` is the mod's `pack.mcmeta` (pack format 97, supported 97.1 to 121.0), and
  `unread_data_files` lists data files of kinds the generator does not read (empty: the
  mod has no advancements, enchantments or other data).

## Using it from Dart

`lib/src/manifest.dart` parses the manifest into plain classes (`Manifest`,
`ManifestItem`, `ManifestBlock`, `Recipe`, ...), `lib/src/components.dart` gives typed
views of the components the server acts on (`ToolComponent`, `EquippableComponent`,
`KineticWeaponComponent`, ...; the raw JSON stays available), and
`lib/src/validation.dart` checks a manifest:

- ids and registration order are unique and consistent, `item_model` equals the id,
  every display name matches `lang`;
- components agree with the material (durability, repair tag, enchantability, armor
  defence and sound, durability factor of the slot);
- every id and tag of the mod's own namespace used by tags, recipes, loot tables,
  repair components, creative tabs and behaviours exists; every item has exactly one
  recipe and appears in the creative tab; tab insertions only anchor on vanilla items
  or on items inserted before them;
- the block has 2^n states and a valid default.

`externalReferences` lists what the manifest takes from other namespaces (vanilla items,
blocks, item tags and block tags, e.g. `minecraft:breeze_rod`, `#minecraft:sword_efficient`)
for the host to check against its own registries; none of it is resolvable without them.

## Open questions

These are also in the manifest (`open_questions`):

1. **Builder semantics are observed, not read from source.** Verified for all vanilla
   tiers listed above, but the spear builder's argument order is deduced from the
   netherite spear (the mod's call matches it: 1.15, 1.25, 0.4, 2.5, 9.0, 5.5, 5.1, 8.75, 4.6)
   and ticks are a float product cut to an int (which reproduces every
   vanilla spear). The copper tier of armor, leather and the turtle
   helmet are not covered.
2. **Double durability wear on weapons.** The sword, dagger and war axe classes override
   `hurtEnemy` with `hurtAndBreak(1)`. If 26.3 also applies the `weapon` component's
   `item_damage_per_attack` (1), they lose 2 per hit. Not verifiable here. The pickaxe
   `mineBlock` override does what the `tool` component already does (1 per block), so it
   changes nothing.
3. **Omnitool `isCorrectToolForDrops`.** It ORs five calls on `Items.NETHERITE_*` with the
   omnitool's own stack. If that reads the passed stack's `tool` component (the likely
   implementation) it equals the pickaxe rules and the override is redundant.
4. **Spear sounds** for non-wooden materials are the default `item.spear.*` pair; the mod
   has no way to change them.
5. **Block defaults** the Java does not set (friction 0.6, speed and jump factor 1.0, map
   colour, instrument, push reaction) are `BlockBehaviour.Properties.of()` defaults and are
   assumed, not parsed.
6. **No fire resistance.** Unlike netherite, none of the items has `damage_resistant`, so
   they burn in lava. That follows from the Java (no `fireResistant()` call) and is
   presumably intended or an oversight of the mod.
7. **Registry ids.** Items are listed in registration order (the wardframe item first,
   because it is registered before the raw materials). NeoForge assigns numeric ids from that
   order after the vanilla entries; the actual numbers must come from the registry sync.
8. **Client assets look copied.** `equipment/perfect_lonsdaleite.json` points at the
   texture `lonsdaleite:lonsdaleite`, the same as the base tier. Not a server concern.

## Delivering `data/` to the server

`--datapack <dir>` copies the mod's 56 data files into `<dir>/data` and writes a
`pack.mcmeta` (the mod's formats). What Pumpkin does with such a pack is in
[server-logic.md](server-logic.md#datapacks).
