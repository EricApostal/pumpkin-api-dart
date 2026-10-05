# Server logic of the Lonsdaleite mod on Pumpkin

What the mod's Java does on the server, what Pumpkin does today for the vanilla
equivalent, and what is missing for a plugin to stand in for the mod. Paths are in
`/Users/eric/Documents/development/languages/rust/Pumpkin/crates/` (`pumpkin/src/...`
is `crates/pumpkin/src/...`). "Uncommitted" marks work other agents had in the tree
while this was written (`pumpkin-data/src/item_registry.rs`, `dynamic_tag.rs`,
`pumpkin/src/data/datapack/item_tag_loader.rs`); it may have changed since.

The client has the mod, so it runs the Java itself for everything it predicts
(mining speed, tooltips, models, collision of the player). The server only has to
agree on what it simulates and on the item/block ids and components it sends.

## Summary

| Mod behaviour | Pumpkin today | Plugin reach | Needed from the host |
| --- | --- | --- | --- |
| Items with their components | `ItemStack` is `&'static Item` plus a component patch; vanilla components are used for tools, attributes, armor, durability | `item-registry` WIT interface (`register-item`, `register-item-tag`, permission `registry.items`), used by the plugin; see [registration.md](registration.md) | the host's network reader drops `attribute_modifiers` and has no reader for `block_transformer` and `interact_animation` (see [registration.md](registration.md#what-the-host-keeps)) |
| Tool mining speed, drops, mining durability | component driven (`tool`) | works once items exist | nothing for pickaxes, axes, shovels, hoes; omnitool needs server-only rules (`server_components`) |
| Attack damage and speed, weapon wear | component driven (attributes, `weapon`) | works once items exist | sweep attack and shield disabling are keyed to static tags |
| Armor | component driven (attributes, `equippable`) | works once items exist | slot checks, armor wear formula and enchanting use static tags |
| Spear | `SpearItem` keyed to the static `spears` tag | none | key the behaviour to the dynamic tag or the `kinetic_weapon` component |
| Mace smash | `Item::MACE` hard-coded | none | key to the item tag `enchantable/mace` or a component |
| Omnitool right click | axe/hoe/shovel are three behaviours keyed to static tags | `PlayerInteractEvent` can cancel and replace | a way to run a block transformer (preferred) or an item behaviour hook |
| Wardframe block | runtime blocks through the `block-registry` WIT interface (written, not yet compiled when this was wired) | used by the plugin: `register-block`, `register-block-tag`, `set-block-item`, permission `registry.blocks`; see [registration.md](registration.md#the-wardframe) | entity aware collision (tamed pets, mounts); the rest is covered |
| Tags (enchantable, repair, armor, tools) | static, plus uncommitted overlay | none | finish and wire the overlay |
| Recipes, loot | datapack loader | via files only | see [Datapacks](#datapacks) |

## Components Pumpkin reads

Everything below is read from the item stack's components, so a registered item
whose default components are the manifest's gets it for free.

| Mod item | Component | Pumpkin |
| --- | --- | --- |
| tools | `tool` | `pumpkin-data/src/data_component_impl/combat.rs` (`ToolImpl`, `ToolRule`); `ItemStack::get_speed` and `is_correct_for_drops` in `pumpkin-data/src/item_stack/mod.rs` (~746 and ~779) walk the rules in order and match tags by name against the static block tags (`block.is_tagged_with`). `Player::get_mining_speed` (`pumpkin/src/entity/player.rs` ~5000) adds efficiency, haste, fatigue, and divides by 5 in the air; `can_harvest` (~4963); the breaking time is `calc_block_breaking` (`pumpkin/src/block/mod.rs` ~518). Same first-match semantics as vanilla's `Tool`. |
| tools | `tool.damage_per_block` | `Player::apply_tool_damage_for_block_break` (`player.rs` ~1778) after a break (not in creative, not for hardness 0) calls `damage_held_item`. This is what `Lonsdaleite_Pickaxe.mineBlock` and `Perfect_Lonsdaleite_Pickaxe.mineBlock` do by hand (`hurtAndBreak(1)` for non-zero hardness), so those overrides need no emulation. |
| weapons | `attribute_modifiers` | `LivingEntity::update_weapon_attributes` (`pumpkin/src/entity/living.rs` ~463) puts the held item's `attack_damage` and `attack_speed` modifiers on the player; `Player::attack` (`player.rs` ~1317) reads the speed from the modifier whose id is exactly `minecraft:base_attack_speed`, which the manifest uses. Armor modifiers are applied by `apply_equipment_slot_attribute_modifiers` (`living.rs` ~561) and summed for damage reduction in the armor absorb function (`living.rs` ~2790, `CombatRules` in `entity/combat.rs`). Knockback resistance goes through the generic path. |
| weapons | `weapon` | `Player::combat_weapon_durability_cost` (`player.rs` ~1597): `item_damage_per_attack`, applied at the end of `attack`; an item without `weapon` loses nothing. `disable_blocking_for_seconds` is not read anywhere (grep finds no use), so vanilla axes do not disable shields either. |
| armor | `equippable` | right click equip (`pumpkin/src/net/java/play/use_item.rs` ~119), `player.rs` ~7917, dispenser, mobs. `damage_on_hurt` is honoured in `damage_armor_items` (`living.rs` ~2435). `asset_id` is a string that is written back into the component; the server has no equipment asset registry, so `lonsdaleite:lonsdaleite` needs no server side definition (it is a client resource under `assets/lonsdaleite/equipment`). |
| all | `max_damage`, `damage`, `repairable`, `enchantable` | `ItemStack::damage_item` (`item_stack/mod.rs` ~376: Unbreaking, break consumes one item). `repairable` matches by tag name (`RepairableImpl::is_valid_repair_item`, `combat.rs` ~703) and `enchantable` is used by the enchanting table (`pumpkin-inventory/src/enchanting/enchanting_screen_handler.rs`). |
| spear | `kinetic_weapon`, `piercing_weapon`, `attack_range`, `minimum_attack_charge`, `use_effects` | components exist (`KineticWeaponImpl`, `PiercingWeaponImpl`, `AttackRangeImpl`), the behaviour is `pumpkin/src/item/items/spear.rs`. |
| axe, shovel, hoe | `block_transformer` | the id exists (`DataComponent::BlockTransformer`, `generated/data_component.rs`), but there is no `DataComponentImpl` and nothing reads it: the vanilla tools are matched through the static item tags instead (below). **`register-item` does not skip it, it fails** ("Unimplemented data component") because the host decodes every listed component; the plugin therefore leaves it out (`DataComponentCodec.notReadByHost`) and logs it. |

### Unknown or new components, custom equipment assets

Components are keyed by the vanilla component registry (`generated/data_component.rs`,
122 entries including the 26.x ones such as `kinetic_weapon`, `block_transformer`,
`mob_visibility`, `cushion/color`). Every component the mod uses has an id. Those
without an implementation are dropped when read from NBT (`data_component_impl::read_data`
returns `None`) and rejected when read from the network (`codec::data_component::deserialize`,
used by `register-item`). A `tool` rule naming a tag Pumpkin does not know is not an error
(`is_tagged_with(..).unwrap_or(false)`), it just never matches. A stack goes to the client as
a patch against the item's default components (`pumpkin-protocol/src/codec/item_stack_seralizer.rs`),
so for a client with the mod, whose own defaults are the Java ones, an item is consistent as
long as the server's defaults equal the manifest's `components`. Server-only differences
(`server_components`) must therefore stay in the defaults and never appear in a patch.

## The omnitool

`Lonsdaleite_Omnitool` overrides three methods.

**`useOn`** (right click on a block). In 26.3 axes, hoes and shovels carry a
`block_transformer` component and `Item.useOn` runs the transformer of the held stack. The
mod therefore looks up the three transformers itself and applies them in a fixed order: axe
(stripping logs, scraping and waxing off copper), then hoe (tilling, rooting dirt) and shovel
(paths, dousing campfires), swapped while sneaking. The transformer damages the held stack.

Pumpkin: `AxeItem`, `HoeItem` and `ShovelItem` (`pumpkin/src/item/items/{axe,hoe,shovel}.rs`)
implement `use_on_block` with the generated tables `pumpkin_data::block_transformer::{AXE,
HOE, SHOVEL}` (`generated/block_transformer.rs`). They are registered in `default_registry()`
(`item/items/mod.rs` ~112) by `ItemMetadata::ids()`, which is the static item tags
(`tag::Item::MINECRAFT_AXES.1` and so on, compile time lists of ids). `ItemRegistry`
(`item/registry.rs`) is a `FxHashMap<u16, Arc<dyn ItemBehaviour>>` created once; plugins cannot
add to it, and one id has one behaviour. There is no `block_transformer` lookup by component
and no way for code outside these three structs to run a transformer. The campfire dousing is
a special case inside `ShovelItem`. A dynamic item (uncommitted `item_registry.rs`) gets no
behaviour at all, so a right click falls through to block placement.

Plugin path today (`PlayerInteractEvent`, `Events.playerInteract`): fired in
`pumpkin/src/net/java/play/use_item_on.rs` (`handle_use_item_on`, ~85) before the block's use,
the item behaviour and placement; cancelling skips all three. The payload has the player, the
action (`right-click-block`), the clicked position and the block name, but **no hand, face,
cursor position or item**. The handler in `lib/src/plugin.dart` reads the main hand with
`player.getItemInHand`, sneaking with `asEntity().isSneaking()`, and cancels only after a
transformer applied (cancelling skips the block's own use too, e.g. opening a door). To do the
work itself the plugin would need a transformer table (the `AXE/HOE/SHOVEL` tables are host
statics, the WIT has `resolve-block-state` and `set-block-state` but no transformer access), the
face (`player.get-target-block-exact` can recover it), a durability call (the WIT has none; the
`damage` component would have to be encoded by hand, including Unbreaking and the break
effects) and the game events and `sync_world_event` particles (not exposed).
`lib/src/omnitool.dart` therefore keeps the decision logic behind a `BlockTransformerPort`
and `lib/src/host_adapter.dart` is the one place that has to implement it.

**Host change (preferred):** a WIT function "run block transformer `minecraft:axe|hoe|shovel` at
(position, face, hand) for this player" that reuses the three existing behaviours' code
(state change, sound, particle, loot, `item_damage_per_use`, creative exemption) and returns
whether it applied. Better still, key `AxeItem`/`HoeItem`/`ShovelItem` to the `block_transformer`
component instead of the tags, and add `hand`, `face` and the item to `PlayerInteractEvent`.
A general "plugin item behaviour" hook (`use-on-block` for registered items) would also solve it
but is much larger.

**`getDestroySpeed`**. Returns the material speed (8.2 / 9.0) on any block in
`#mineable/pickaxe`, `#mineable/axe`, `#mineable/shovel`, `#mineable/hoe` or
`#sword_efficient`, else 1.0, regardless of the `tool` component (which has the pickaxe
rules only). Pumpkin reads speed from the component, so the manifest's `server_components`
append speed-only rules for the other four tags after the pickaxe rules; with Pumpkin's
first-match walk that is exactly the Java result, and `correct_for_drops` stays that of the
pickaxe rules. Verified by `test/components_test.dart`. These server components must be what
the host registers as the item's defaults (the client does not use them).

**`isCorrectToolForDrops`**. See `content.md`, open question 3: very likely the pickaxe rules
again, so nothing to do. If it turns out to consult the netherite items' own rules, add
`correct_for_drops true` rules for the other tags to `server_components`.

## Swords, dagger, war axe, mace, pickaxe, armor, spear

- `Lonsdaleite_Sword`, `Perfect_Lonsdaleite_Sword`, `*_Short_Sword`, `*_War_Axe` override
  `hurtEnemy` with `hurtAndBreak(1)`. Pumpkin charges `weapon.item_damage_per_attack` once in
  `Player::attack`. If the 26.3 game charges both, the items should have
  `item_damage_per_attack: 2` on the server (a one-line change in the registration) and the
  client is unaffected since durability is server state. Decide after checking the decompiled
  `Item.hurtEnemy`/`ItemStack.postHurtEnemy` (open question 2). Plugin reach if wanted at
  run time: `PlayerItemDamageEvent` fires after the damage and cannot change it.
- Sweeping: `AttackType::new` (`pumpkin/src/entity/combat.rs`) uses `ItemStack::is_sword`
  (`item_stack/categories.rs`), which checks the static `minecraft:swords` tag with
  `has_tag(&'static Tag)`, a compile time id list. The mod puts all six swords, daggers and war
  axes in that tag; dynamic items will never sweep until `is_sword` consults the dynamic tag.
- Mace: `Lonsdaleite_Mace extends MaceItem` with no overrides but its attributes. Pumpkin's
  smash attack is `Item::MACE` hard-coded in `AttackType::new` (`combat.rs`, ~37) and `MaceItem`
  (`item/items/mace.rs`, `can_mine` for creative) is registered for `[Item::MACE.id]`. A dynamic
  mace gets neither. The smash damage is `1.5 + fall-damage-enchant bonus` per block fallen
  (`player.rs` ~1428), which should be compared with vanilla's tiered formula; that is a
  Pumpkin issue independent of this mod.
- Armor: nothing in the mod's code, all components. Needs from the host: the armor slot
  `can_insert` check (`pumpkin-inventory/src/slot.rs` ~336) uses `is_helmet()` etc. (static tags
  `head_armor`..., so clicking modded armor into an armor slot would be refused; right click
  equipping uses the `equippable` component and works); `ItemStack::is_armor` (static
  `enchantable/armor`) selects the armor Unbreaking formula in `damage_item`; the enchantment
  checks use `Enchantment::can_enchant`, `supported_items.1.contains(&item.id)` over a compile
  time list (generated `enchantment.rs` ~2908).
- Spear: components are in place, but `SpearItem::ids()` is `tag::Item::MINECRAFT_SPEARS.1`,
  so the lunge, jab, dismount and knockback logic does not run for dynamic spears. Key it to the
  tag with the overlay or to `kinetic_weapon`.

## The wardframe

> **Update:** the host has a runtime block registry now (`block-registry.wit`, written in
> the Pumpkin working tree). The plugin uses it, see [registration.md](registration.md#the-wardframe)
> and [docs/block-registry.md](../../../docs/block-registry.md). The analysis below is the
> original reading of the Pumpkin sources that led to it; "there is no dynamic block
> registry" is **outdated**. What is still true: collision is one shape per state (no
> per-entity shapes), and drops go through the registered loot rule (`self-item`).

Java (`Lonsdaleite_Wardframe`): six boolean properties; `getStateForPlacement` and
`updateShape` set each to "the neighbour in that direction is a wardframe";
`getCollisionShape` returns the empty shape for a `Player`, a tamed `TamableAnimal` and any
entity with a player passenger, a full cube otherwise (including `null` entity, which is what
pathfinding queries use); `isPathfindable` is always false; properties: strength 5/1200,
amethyst sounds, no occlusion, needs the right tool (diamond tier, pickaxe), light 7.

Pumpkin: blocks are the compile time `Block`/`BlockState` tables (`pumpkin-data/src/blocks.rs`,
`generated/block.rs`); `BlockRegistry` (`pumpkin/src/block/registry.rs` ~499) is a fixed array
sized `BlockId::COUNT`; `Block::from_name` is a static map. **There is no dynamic block
registry at all**, so the wardframe needs: runtime blocks with state ids appended after the
vanilla ones (64 states, in the manifest's order; the client's registry sync fixes the order),
per state luminance 7, full cube collision/outline shapes, `piston_behavior`, opacity 0 (it
does not occlude), tool requirement and hardness for `calc_block_breaking`, and block tag
membership (`mineable/pickaxe`, `needs_diamond_tool`; the overlay has a block registry key but
no block ids to put in it).

Behaviour hooks exist on the trait: `BlockBehaviour::on_place` (`pumpkin/src/block/mod.rs` ~62,
`getStateForPlacement`) and `get_state_for_neighbor_update` (~157, `updateShape`); the closest
examples are `block/blocks/glass_panes.rs`, `iron_bars.rs` and the chorus plant (six booleans
as well). The host should offer a generic "connect to blocks of the same kind" behaviour, or
the plugin needs a block behaviour callback.

Collision: players. Pumpkin's player movement is client authoritative (`net/java/play/
player_position.rs` accepts the position packet; no collision validation was found there,
confirm in game), and the mod's client lets players through, so the server need not do anything
for players or for a player's mount (also client driven). Server simulated entities (mobs,
items, projectiles) collide with static shapes only (`Entity::move_entity`,
`entity/mod.rs` ~2007; `BlockState::get_block_collision_shapes_at`, `pumpkin-data/src/
block_state.rs` ~194): a full cube is correct for hostile mobs and everything that is not a
tamed animal. The one deviation would be tamed animals (wolves, cats, parrots do not pass
through the wardframe), which needs an entity aware collision shape; the WIT has no collision
hook (`vehicle-*-collision` events are declared and never fired) and no way to attach to
`BlockBehaviour::on_entity_collision`. Pathfinding: `isPathfindable false` means a solid
full cube block must not be pathable, which the default for a full cube already gives; there
is no custom node evaluator hook either, only `set-pathfinding-malus` per mob.

Drops: `drop_loot` (`block/mod.rs` ~455) looks up `minecraft:blocks/<name>` of a static block,
so `lonsdaleite:blocks/lonsdaleite_wardframe` is never consulted.

## Tags, enchanting, repairs

`Taggable::is_tagged_with(&str)` (`generated/tag.rs` ~30621) checks the compile time tag
tables and, in the working tree, the uncommitted `dynamic_tag` overlay (plugin registered
tags plus datapack tags, string entries resolved lazily, `#tag` nesting limited to 8 levels).
Much of the logic above uses the other path, `Taggable::has_tag(&'static Tag)` (the lists
baked in at build time): `AxeItem::ids`, `HoeItem::ids`, `ShovelItem::ids`, `SpearItem::ids`,
`is_sword`, `is_armor`, `is_helmet`... and `Enchantment::can_enchant`. The `repairable`
component (`#lonsdaleite:repairs_*`, anvil) uses `is_tagged_with`, so it can work with the
overlay once the manifest's tags are registered. The tags the mod extends, and who needs them:

| Tag | Used for |
| --- | --- |
| `repairs_lonsdaleite_tools`, `repairs_perfect_lonsdaleite_tools` | `repairable` (anvil, mod's own tags) |
| `minecraft:axes`, `hoes`, `shovels`, `pickaxes`, `swords`, `spears` | which behaviour runs, sweeping, client UI |
| `minecraft:head_armor` ... `foot_armor` | armor slots, `is_armor` through `enchantable/armor` |
| `minecraft:enchantable/*` | which enchantments apply (client-visible enchanting UI, anvil, table) |
| `minecraft:doors` (item), `mineable/pickaxe`, `needs_diamond_tool` (block) | wardframe |

Item tags are part of the client's tag sync in the real game; Pumpkin's `UpdateTags` packets are
built from the static tables (`pumpkin-protocol/src/java/client/config/update_tags.rs`), and the
overlay says it is not part of the sync. The mod's client has its own copy of these tags from
its jar data, which is why the client side works regardless.

## Datapacks

How `data/` can reach the server (`pumpkin/src/data/datapack/mod.rs`):

- A pack is a **directory** `<world>/datapacks/<name>/` with `pack.mcmeta` and `data/<ns>/...`
  (zip packs are listed, never loaded). `--datapack` in `tool/generate_manifest.dart` writes
  that layout. `pack.mcmeta` is parsed but its formats are never validated (default 61 if
  missing), so any value loads.
- It is **not enabled automatically**; `level.dat` keeps an enabled list (default
  `["vanilla"]`). A plugin can list and enable packs and trigger a reload through the
  `datapack-manager` resource (`datapack.wit`: `list-*-packs`, `get-pack`, `enable-pack`,
  `disable-pack`, `reload`, `execute-function`; Dart: `server.datapacks`), but has **no way to
  create or install** one: the WASI sandbox only preopens the plugin's own data folder, and
  there is no API to write into `world/datapacks` or to register a pack path. Either the
  operator copies the folder, or the host adds an install call.
- Reload (`/reload`, enable, disable) re-runs `load_all`, which also **replaces every dynamic
  recipe registered through the recipe WIT**.
- Loaded from a pack: recipes of types `crafting_shaped`, `crafting_shapeless`, `smelting`,
  `blasting`, `smoking`, `campfire_cooking` (and a Pumpkin `brewing`); loot tables, functions,
  function and trade tags, and some dynamic registries (enchantment, damage type, variants...).
  Not loaded: advancements, and (committed HEAD) any **item, block or other tag**. The working
  tree adds `item_tag_loader.rs` for item tags; block tags have no loader.
- What that means for the mod's 56 data files:
  - 30 shaped recipes: parsed, ingredients kept as strings (`"lonsdaleite:refined_lonsdaleite"`,
    `"minecraft:stick"`). Matching compares strings against `Item::resource_location()` in the
    uncommitted `recipe.rs`; on committed HEAD a namespaced id never matches. The result stack
    is resolved with `Item::from_registry_key(..).unwrap_or(AIR)`, so **the items must be
    registered before the pack loads** (an unknown result gives an empty output). A bare
    `"#tag"` string ingredient is not recognised by the loader (only the legacy `{"tag": ..}`
    object), which this mod does not use.
  - 2 blasting recipes load but **furnaces and blast furnaces only read the static cooking
    table** (`RECIPES_COOKING` in `pumpkin-inventory/src/furnace_like/`), so
    refining the gems does not work without a host change.
  - tags: ignored on committed HEAD, and unknown member ids would be silently dropped anyway;
    needs the overlay, either through its loader or a plugin registration. Block tags need
    dynamic blocks.
  - loot table: loaded, but never consulted for a modded block (see above).
- Alternative for recipes: the recipe WIT (`register-shaped`, `register-shapeless`, cooking)
  takes an item stack as output and stores ingredient strings verbatim; same furnace limitation.

## What the host has to add

In priority order for a working mod, all of it beyond the item registration API being built:

1. Items: registration with default components given as vanilla JSON (the manifest's
   `ItemDefinition.components`), in call order, ignoring components without an implementation
   (`block_transformer`); numeric ids and the registry sync must match the client's.
2. Runtime tags wired in: item tags into `has_tag` users (`is_sword`, `is_armor`, `is_helmet`...,
   `AxeItem` etc.) and `Enchantment::can_enchant`; a WIT call or loader to feed the manifest's 23
   tag files.
3. A way to run block transformers for a player (omnitool) and `hand`, `face`, item in
   `PlayerInteractEvent`; durability and item-break helpers in the WIT.
4. Behaviours for dynamic items: spear (tag or `kinetic_weapon`), mace smash (tag
   `enchantable/mace`), sweeping (tag `swords`).
5. ~~Dynamic blocks (the wardframe)~~: done by the `block-registry` interface (states, shapes,
   luminance, tool requirements, tags, drops, connecting). Still open: optional entity aware
   collision.
6. Cooking recipes from the dynamic recipe manager in furnaces; recipe WIT/datapack with namespaced
   ids; a way to install a data pack from a plugin.

## Open questions

See `content.md`. The server relevant ones: whether `hurtEnemy` doubles the wear, whether
`isCorrectToolForDrops` is a no-op, and whether the Java client accepts the server's player
movement through the wardframe without correction (Pumpkin side not confirmed in game).
