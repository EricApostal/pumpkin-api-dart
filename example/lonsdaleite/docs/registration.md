# Registering the mod's items and block on Pumpkin

How `lib/src/` turns `data/manifest.json` into registered items and the wardframe
block, in the order it happens at load (`LonsdaleitePlugin.onLoad`), and what the host
does with it. Everything here was derived from reading Pumpkin's sources (the
uncommitted `item-registry` and `block-registry` work in
`/Users/eric/Documents/development/languages/rust/Pumpkin`); **nothing was run against a
built server yet** (see [README.md](../README.md#what-is-verified)).

## Pipeline

1. `validateManifest` (the embedded manifest is consistent).
2. `installManifestItems` (`lib/src/item_install.dart`), against the host's
   `item-registry`:
   1. **vanilla check**: the host's vanilla item list must equal the list the
      NeoForge registry sync is built from (`VanillaRegistries 'minecraft:item'`,
      generated from Pumpkin's `assets/items.json`: 1658 items). A different
      count or a different key at any id stops the plugin with a message,
      before anything is registered. The ids of the mod's items are
      `vanillaCount + index`; if the host's vanilla ids differed from what the
      client is told, every item would be wrong.
   2. **register the 32 items** in `registration_index` order
      (`register-item`). Each item's *server view* of the components is used
      (the omnitools carry their extra mining rules, `server_components`), encoded
      by `DataComponentCodec` (`packages/pumpkin_api/lib/src/data_component_codec.dart`).
   3. **verify the ids**: every item must have got `vanillaCount + registration
      index` (a different start means another plugin registered items first, and the
      message says so), and `get-registered-items` must report the same ids.
   4. **register the 21 item tags** (`register-item-tag`; entries are item keys
      and `#tag` references as in the data pack files).
3. `installManifestBlock` (`lib/src/block_install.dart`), against the host's
   `block-registry`, see [The wardframe](#the-wardframe): vanilla counts check,
   `register-block`, id and state checks, `set-block-item`, the block tags
   (`register-block-tag`), read back.
4. `installNeoForge` (`lib/src/neoforge.dart`) builds the sync spec from the
   manifest and the ids the host assigned to the items and the block (so the
   snapshot is what the packets use) and installs `NeoForgeServer` (`pumpkin_neoforge`) with the library's
   default **adhoc** negotiation and refusal of non-NeoForge clients. The spec
   equals `lonsdaleiteSpec()` (`test/neoforge_spec_test.dart`).
5. The `/lonsdaleite` command and the omnitool handler.

Registration only works while the server loads; the host closes the registries
before it accepts connections. Registering the same key again with identical
components (or the same block definition) returns the existing item (block), so a
reload keeps the ids.

Permissions: `registry.items` and `registry.blocks` (`PluginInfo.permissions`).

## Component encoding

The host decodes every `data-component-value.value` with the network reader of
that component (`crates/pumpkin-protocol/src/codec/data_component.rs`,
`DataComponentCodec::deserialize`). The Dart encoder is its inverse; golden bytes
are in `packages/pumpkin_api/test/data_component_codec_test.dart` (hand derived
from the Rust readers) and `test/component_codec_test.dart` compares the encoding
of all 32 items with `tool/golden_components.py`, a second encoder written from
the Rust readers without using the Dart one (regenerate
`test/fixtures/component_bytes.json` with it).

Registry ids that appear in values come from tables generated from Pumpkin's
assets (`packages/pumpkin_api/tool/generate_registry_ids.dart` ->
`lib/src/registry_ids.g.dart`): sound events (list order of `sounds.json`; a
`Holder<SoundEvent>` is written as id + 1), blocks, attributes, damage types
(sorted file names of the damage_type directory), mob effects, entity types,
enchantments, items, data component types.

### What the host keeps

| Component | Read by the host as | Kept by the host |
| --- | --- | --- |
| `max_stack_size`, `max_damage`, `damage`, `repair_cost`, `enchantable` | one VarInt | yes |
| `rarity` | VarInt id (common 0 .. epic 3) | yes |
| `item_model` | string | yes |
| `item_name` | **a string, the translation key** (its writer produces NBT; the reader is not the inverse), so only `{"translate": key}` can be registered | yes |
| `lore`, `enchantments` | VarInt count (the mod has none) | yes |
| `repairable` | `HolderSet<Item>`: VarInt 0 and the tag name, or count + 1 and ids | yes (matched by tag name, so `#lonsdaleite:repairs_*` works through the tag overlay) |
| `tool` | rules (`HolderSet<Block>`, optional speed, optional correct_for_drops), default speed, damage per block, creative flag | yes |
| `weapon` | VarInt `item_damage_per_attack`, f32 `disable_blocking_for_seconds` | the damage; **the shield disable time is dropped** |
| `equippable` | slot, sound, asset id, camera overlay, allowed entities, five flags, shearing sound | yes |
| `attack_animation`, `attack_range`, `minimum_attack_charge`, `damage_type`, `piercing_weapon`, `kinetic_weapon` | as in vanilla's StreamCodecs | yes |
| **`attribute_modifiers`** | parsed completely, then **discarded**: `AttributeModifiersImpl::deserialize` returns an empty list | **no** |
| `use_effects`, `tooltip_display`, `break_sound` | parsed, discarded (unit structs) | no (the spear's `use_effects` is not kept) |
| `interact_animation`, `block_transformer` | **no reader**: `register-item` would fail with "Unimplemented data component" | n/a, skipped |

So on a server built from the current tree: tool mining speeds, drop rules,
durability, repair, enchantability, equippable armor slots and the spear/kinetic
values are in place, but **weapons and armor have no attribute modifiers**
(attack damage and speed, armor, toughness, knockback resistance). A sword does
the damage of a bare hand and armor protects nothing until the host keeps them.
The place to change is `AttributeModifiersImpl::deserialize` in
`crates/pumpkin-protocol/src/codec/data_component.rs` (keep the entries instead of
`Cow::Borrowed(&[])`; the type, id, amount, operation and slot are all read there
already). The plugin already sends the vanilla bytes for them.

Also worth checking on the host: `SwingAnimationType::from_id` maps whack 0, stab 1,
none 2, while (from memory of the game's source, not verified here) vanilla's ids
are none 0, whack 1, stab 2. The plugin writes what the host reads (stab = 1).
Nothing on the server uses the value, and clients only see it when a stack's
patch contains it, which it does not for these items.

### Skipped components

Components the host cannot read are left out of the registration and logged at
load, so the list can be checked:

| Component | Items | Why it is harmless |
| --- | --- | --- |
| `minecraft:block_transformer` | the 6 axes, shovels and hoes | Pumpkin matches `AxeItem`/`ShovelItem`/`HoeItem` through the static item tags; the dynamic tag overlay does not reach them (see [server-logic.md](server-logic.md#the-omnitool)) |
| `minecraft:interact_animation` | all 32 | nothing on the server reads it; clients use their own defaults |

`DataComponentCodec.notReadByHost` lists all 12 components of 26.3 that the host
has no reader for (also `villager_food`, `compostable`, `cooking_fuel`,
`brewing_fuel`, `mob_visibility`, `provides_pottery_pattern`, `sign_text_front`,
`sign_text_back`, `waxed`, `cushion/color`).

## The wardframe

The plugin registers the block with the host's `block-registry`
(`packages/pumpkin_api`: `BlockRegistries.host`, spec in
[docs/block-registry.md](../../../docs/block-registry.md)). The exact sequence of
`LonsdaleitePlugin.onLoad` (all inside the load window):

1. `validateManifest`: includes the definition's own validation and the comparison of
   the computed state numbering with the mod's `block_state` table.
2. **Items** (`installManifestItems`): vanilla item check, 32 x `register-item` (the
   wardframe item first, id 1658), id checks, 21 x `register-item-tag`.
3. **Block** (`installManifestBlock`):
   1. `blockDefinitionFor(manifest)`: the definition below, validated with the host's
      rules (`BlockDefinition.check`);
   2. check that the host has 1286 vanilla blocks and 35723 vanilla states (the numbers
      the registry sync was built from; `VanillaRegistries` and `vanillaBlockStateCount`);
   3. `register-block` -> id;
   4. `get-registered-blocks` must report exactly: block id 1286 (`vanillaBlockCount +
      0`), base state id 35723 (`vanillaStateCount`), 64 states; another plugin's block
      before ours is a loud failure;
   5. `set-block-item("lonsdaleite:lonsdaleite_wardframe",
      "lonsdaleite:lonsdaleite_wardframe")`;
   6. `register-block-tag` for each block tag of the manifest
      (`minecraft:mineable/pickaxe`, `minecraft:needs_diamond_tool`; the host adds the
      lower tiers' `incorrect_for_*` tags for the second);
   7. read back: `get-registered-blocks` again (item id 1658 now), `get-block-id`, and
      `get-state-id` for **all 64 states** and for the default state against the
      plugin's computation.
4. **NeoForge** (`installNeoForge`): the sync spec lists the wardframe at index 1286 of
   `minecraft:block` (`verifyBlocksAgainstSpec` checks id and first state id).
5. `/lonsdaleite` and the omnitool handler.

### The definition

From the manifest (`lib/src/block_definition.dart`): six boolean properties
`north south east west up down` (property name = direction), default all `false`;
hardness 5.0, blast resistance 1200.0, `requires-correct-tool`, sound `amethyst`,
luminance 7, `can-occlude` false, `suffocating` false, not replaceable, collision and
selection `full-cube`, a `same-block` connect rule per face, drops `self-item` (the
manifest's loot table is exactly "one of the block item"; any other table would be
registered as `loot-table(key)`), tags through `register-block-tag`.

### State ids

The host numbers states like vanilla's `StateDefinition`: properties sorted by name
(`down east north south up west`), the first the most significant, `true` before `false`.
For the wardframe the strides are 32, 16, 8, 4, 2, 1; index 0 is all `true`, index 63
all `false`; **the default state (all `false`) is base + 63 = 35786**; `east` and `up`
true is 63 - 16 - 2 = 45, id 35768. The plugin computes it in Dart
(`BlockStateLayout`, `packages/pumpkin_api/lib/src/block_registry_core.dart`) and
compares with:

* the mod's table (`block_state.states` in the manifest: every state's index and
  values), at validation, so a generator or Java change shows up in the tests;
* the host's `get-state-id`, at load, for every state.

The client does not receive state ids in the registry sync: it walks its block registry
in id order, appending each block's states
(`NeoForgeRegistryCallbacks.BlockCallbacks`), so with the block at id 1286 and all
vanilla blocks before it, its states start at 35723 and use the same order. The plugin
refuses to load if the host would number anything differently
(`verifyBlocksAgainstSpec`, `BlockRegistryChecks`).

### What the host does, and what it does not

Works: placing through the block item (vanilla placement path), auto-connecting
(placement and neighbour updates), hardness and tool requirement (tags + `requires
correct tool`), the self drop, light 7, chunk save and load by name and properties.

Gaps: per-entity collision (players pass on the client only; tamed pets and mounts
collide on the server), `sound-type` and `map-color` are only stored, block entities,
redstone power, random ticks and waterlogging do not exist for custom blocks, static tag
checks by generated constant do not see the block (checks by name do).

## Known gaps (host side)

| Gap | Effect |
| --- | --- |
| `attribute_modifiers` dropped on register | no attack damage / armor values (above) |
| no `block_transformer` support, no transformer call | the omnitool's right click does nothing; plain axes, hoes and shovels of the mod do not strip/till/path (they are not in the static item tags) |
| static tags in behaviour code (`is_sword`, `SpearItem::ids`, `Item::MACE`, ...) | no sweeping, no spear lunge, no mace smash for the mod's items |
| blasting recipes read only the static cooking table | `prepared` -> `refined` -> `perfect` gems cannot be smelted |
| per-entity collision | tamed pets and mounts collide with the wardframe on the server (players pass on the client) |
| the plugin installs no recipes | no crafting recipes (see the README) |

See [server-logic.md](server-logic.md) for the full list and where each lives in
Pumpkin.
