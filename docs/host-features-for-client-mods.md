# Host features for client mods

What the Pumpkin host (WIT `v0.2`) offers a plugin that serves a client mod such as
CC: Tweaked, beyond custom items and blocks (see [item-registry.md](item-registry.md)
and [block-registry.md](block-registry.md)). Everything here is general: nothing is
specific to one mod. It was written without being built or run, so expect fixes when
the host compiles and a real client talks to it.

The WIT is in `crates/pumpkin-plugin-wit/v0.2/`:

| File | Interface | What |
| ---- | --------- | ---- |
| `plugin-block-entity.wit` | `plugin-block-entity` | block entity types and the data of block entities of plugin blocks |
| `menus.wit` | `menus` | menu types, opening and closing menus, slots and data slots |
| `custom-components.wit` | `custom-components` | data component types and their values on item stacks |
| `event.wit` | `event` | the new events (below), appended at the end of `event-type` and `event` |

Contents: [Registries and ids](#registries-and-ids) -
[Block entities](#block-entities) - [Menus](#menus) -
[Custom data components](#custom-data-components) -
[Use events](#use-events) - [Permissions](#permissions) -
[Order of things at startup](#order-of-things-at-startup) -
[Not done](#not-done)

## Registries and ids

Block entity types, menu types and data component types follow the pattern of the item
and block registries: append only, closed when the server starts accepting connections
(after `server-load-event`), and the id is `vanilla count + registration index`:

| Registry (`minecraft:...`) | Register | Vanilla count |
| --- | --- | --- |
| `block_entity_type` | `plugin-block-entity.register-block-entity-type(key, valid-block-keys)` | `get-vanilla-block-entity-type-count()` |
| `menu` | `menus.register-menu-type(key)` | `get-vanilla-menu-type-count()` (25) |
| `data_component_type` | `custom-components.register-data-component-type(key, persistent, codec)` | `get-vanilla-data-component-type-count()` (122) |

Keys are `namespace:path` (`a-z 0-9 _ - .`, `/` in the path), `minecraft` is reserved.
Registering the same definition again returns the same id (a reloaded plugin), a different
one for a known key is an error. Register in the order of the mod's registry sync, the way
`item-registry` is used (`plugin.dart`, `_registerItems`), and compare the id you get with
the one the sync announces. At most 64 component types can exist (component ids are a
byte).

## Block entities

A block entity of a plugin type holds two **compound tags** (`nbt-tree`, the root has to be a
compound) that the server never interprets:

* `save-data`: written to the chunk and given back when it loads. Never sent to clients.
* `client-data` (optional): the "update tag" (`getUpdateTag`). It is sent to the players
  watching the chunk, inside the chunk packet and in `ClientboundBlockEntityData` when the
  entity changes. Entities without client data are not listed in the chunk packet: the
  client creates the block entity of a block that has one by itself (computers, speakers,
  modems need nothing; monitors send `{XIndex, YIndex, Width, Height}`).

```
register-block-entity-type(key, valid-block-keys) -> result<u32>
get-block-entity-data(world, pos) -> option<plugin-block-entity-data>   // type-key, save-data, client-data
set-block-entity-data(world, pos, type-key, save-data, client-data) -> result<_>
sync-block-entity(world, pos) -> result<_>      // resend the client data, mark the chunk dirty
remove-block-entity(world, pos) -> bool         // fires block-entity-unload-event (removed: true)
```

* Placing a block does **not** create its entity. Call `set-block-entity-data` once the block
  is in the world (a `block-place-event` fires *before* the block exists, so do it from a
  task one tick later, or from the first use). `valid-block-keys` is only used to log a
  warning when the block at the position is not listed.
* `set-block-entity-data` on a position that already holds an entity of the same type
  replaces its data in place (and sends the client data). Another type fails. The chunk has
  to be loaded.
* Persistence: the chunk's `block_entities` list gets `{id: "ns:path", x, y, z,
  PluginData: {...}, PluginClientData: {...}}`. Every change is written to the chunk
  immediately, and again when the chunk unloads. If a chunk loads whose entity type is no
  longer registered (the plugin is gone) the entity is skipped with a warning and its saved
  data stays in the chunk.
* Removal: when a block is **broken or replaced by another block** the entity goes with it
  (also when it lives under a vanilla block). Only a state change of the same block keeps
  it. `block-entity-unload-event` fires with `removed: true`.
* `block-entity-load-event(target-world, pos, type-key, save-data, client-data)` fires once
  per entity when its chunk becomes active, so the plugin rebuilds what it keeps in memory
  (start the computer). It is not fired for entities the plugin created itself.
  `block-entity-unload-event(..., removed, save-data)` with `removed: false` fires before the
  chunk unloads (the data stays saved): stop the computer and persist what it needs.

## Menus

```
register-menu-type(key) -> result<u32>
open-menu(player, menu-type-key, title: text-component, extra-data: option<list<u8>>) -> result<u32>
open-menu-with-slots(player, menu-type-key, title, extra-data, slot-count) -> result<u32>
close-menu(player) -> bool
get-open-menu(player) -> option<open-menu-info>   // container-id, menu-type, slot-count
set-menu-slot(player, slot, stack) -> result<_>   // a copy of the stack is sent
clear-menu-slot(player, slot) -> result<_>
set-menu-data(player, id, value: s16) -> result<_>   // ClientboundContainerSetData
```

* `open-menu` takes the next container id from the server's counter (the same one vanilla
  windows use), closes the screen the player has open, and opens the menu. The result is the
  container id: the one the mod's key/mouse messages carry. Java players only.
* **Extra data.** Without `extra-data` the vanilla `ClientboundOpenScreen` (container id, menu
  type id, title) is sent. With it the host sends the custom payload
  **`neoforge:advanced_open_screen`** instead, body built by the host:
  `VarInt containerId, VarInt menuTypeId, Component title (network NBT), VarInt length + extra
  bytes`. You supply the bytes in whatever encoding the mod's menu factory reads (for CC:
  `ComputerContainerData`). The host does not check that the connection is a NeoForge one
  that registered the payload, you decide per player.
* The window is tracked like any other (`current_screen_handler`): a close from the client,
  `close-menu`, another screen opening, or the player leaving fires **`menu-closed-event`
  (player, container-id, menu-type)** (and the usual `inventory-close-event`). The mod
  stops delivering input and releases keys there.
* Menus have **no behaviour**. Every click in one is sent as **`menu-click-event`** (player,
  container-id, menu-type, slot, button, click-type, `changed-slots` and the carried item as
  `item-id` + `count`, because a client only sends a *hash* of the components of a stack) and
  is **not applied**. After the event the host resends the menu's slots and cursor, so what
  the client predicted is reverted unless you changed the slots. A menu with **zero slots**
  (terminal GUIs) never sends any slot data and has no sync handler. The computer menu of CC
  has 9 *client side* invisible slots over the hotbar: open it with zero slots, the client's
  own inventory fills them.
* `open-menu-with-slots` tracks up to 256 slots the plugin owns; fill them with
  `set-menu-slot` (sent immediately, and the full content is sent at open).
  `set-menu-data` sends one data slot (CC's `isOn` in id 0) and does not track it.
* Not covered: `ServerboundContainerButtonClick`, drag (`quick craft`) state and shift-click
  semantics: a plugin menu has none, all of it arrives as `menu-click-event`.

## Custom data components

`DataComponent` in the host is a closed byte enum. After the vanilla ids (0 to 121) it now has
64 reserved variants, so a plugin type registered as the n-th takes id `122 + n` and values of
it travel everywhere a stack travels (inventories, container packets, creative slots,
clones) without special handling.

The value is kept as **the bytes of its network encoding**, exactly what a client writes
after the component id. The catch is that component values are not length prefixed in most
places, so the host needs the **shape** of the encoding to find where a value ends. That
shape is the `codec` argument: a list of `codec-op` in **prefix notation** with one root node.

| Op | Encoding |
| -- | -------- |
| `var-int`, `var-long`, `flag`, `byte`, `short`, `int`, `long`, `float32`, `float64` | the primitive (big endian) |
| `text` | `VarInt` length + UTF-8 (identifiers too) |
| `byte-array` | `VarInt` length + bytes |
| `uuid` | 16 bytes |
| `fixed-bytes(n)` | `n` bytes |
| `nbt` | a network NBT tag |
| `stack` | an item stack (play encoding) |
| `component-patch` | `VarInt added, VarInt removed, (id, value)*, removed id*` (values of plugin components inside are read with their own codec) |
| `optional` + node | `flag`, then the node if true |
| `repeated` + node | `VarInt` count, then that many nodes |
| `sequence(n)` + n nodes | the nodes in order |

CC's components:

```dart
computer_id        : [varInt]
storage_capacity   : [varLong]
terminal_size      : [sequence(2), varInt, varInt]
left_turtle_upgrade: [sequence(2), varInt, componentPatch]      // UpgradeData
fuel               : [varInt]
overlay            : [text]
computer           : [sequence(2), varInt, uuid]
on                 : [flag]
treasure_disk      : [sequence(2), text, text]
disk_id            : [varInt]
printout           : [sequence(2), text, repeated, sequence(2), text, text]
```

```
register-data-component-type(key, persistent, codec) -> result<u32>
set-custom-component(stack, key, bytes) -> result<_>     // bytes must be exactly one value
get-custom-component(stack, key) -> option<list<u8>>
remove-custom-component(stack, key) -> result<_>
```

* Where the protocol *is* length prefixed (stacks a client sends: creative slots, container
  clicks in 1.21.5 and later) the host takes the bytes as they are, after checking that they
  are exactly one value of the codec (a client cannot smuggle garbage into other clients'
  stacks). A wrong codec therefore shows as rejected stacks, test your shapes.
* `persistent: true` saves the component with the stack (inventory, containers, item entities)
  under its **full key** as an NBT byte array of the network bytes, and loads it back while
  the type is registered. A type that is not registered at load time is skipped with a
  warning and the rest of the stack stays. `persistent: false` types exist in memory and on
  the wire only.
* The vanilla functions of `item-stack` (`get-components`, `set-component`) do not see custom
  components, use the functions above.
* Limits: the host cannot compute the hash a client sends in a container click for a stack
  with custom components, so such a stack counts as changed and the slot is resent (extra
  `SetSlot` packets, no functional problem). Registering default components of an item
  (`item-definition.components`) cannot name a custom type yet, set the component on the stack.

## Use events

Two new cancellable events; a handler registered with `blocking` can cancel, and the changes
of the others are ignored.

* **`player-use-block-event`** (player, hand, item (a copy, an empty stack for an empty hand),
  block-pos, block, face, `cursor: (f32, f32, f32)`, sneaking, cancelled): a right click on a
  block. Fired right after `player-interact-event` and **before** the block handles the click
  and before the item is used or placed. Cancelling stops all of that; the host resends the
  clicked block and the block next to it (so a predicted placement disappears) and the held
  slot. `cursor` is the hit position inside the block (`0..1`): monitors compute the
  character cell from it and the face. Use it to open the computer menu of a plugin block.
* **`player-use-item-event`** (player, hand, item, clicked-pos, face, cancelled): the use of the
  item in hand. For a click on a block it fires after `player-use-block-event`, once the block
  did not handle the click and before the item is used or placed (`clicked-pos` set); a client
  also sends a use in the air after a click that was not handled, which fires it again with
  `clicked-pos` none. Cancelling prevents the use and the placement of a block item.

Spectators do not fire them. Items in the events are copies; to change the held item use
the inventory API.

## Permissions

`registry.block-entities`, `registry.menus`, `registry.components` (next to `registry.items`
and `registry.blocks`): constants in `pumpkin_plugin_api::permissions` and in the host's
`plugin/permissions.rs`. Declare them in the plugin metadata.

## Order of things at startup

1. Plugin load: register the items, blocks, block entity types, menu types, component types
   (the same order as the registry sync lists them).
2. `server-load-event`, then the registries close.
3. Chunks load: `block-entity-load-event` for each saved entity.
4. A client joins: after the negotiation (`configuration-pre-brand-event`), the chunk packets
   carry the client data of the block entities, stacks carry the custom components.
5. A right click: `player-use-block-event` -> your handler opens the menu and cancels.

## Not done

* Rust SDK wrappers (`pumpkin-plugin-api`) for the new events and imports (the generated
  bindings have them).
* Recipes, `ContainerButtonClick`, `ServerboundSetCreativeModeSlot` for menus, data components
  in the default components of a registered item.
* Block entity ticking (the plugin owns the behaviour: use the scheduler), redstone, and
  the block callbacks listed in [host-requirements.md](../example/cc_tweaked/docs/host-requirements.md).
* Bedrock players (menus fail for them, block entity data is Java only).
