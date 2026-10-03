# Menus, item builder and typed data

Three small layers on top of the generated API. Call `context.installMenus()`
once in `onLoad` to use menus.

## Item builder

`ItemSpec` is a plain, `const`-friendly description of an item (key, count,
name, lore, enchantments, attribute modifiers, custom model data, unbreakable,
glint, damage, max damage, max stack size, rarity, item model). It has value
equality and `build()` makes a fresh `ItemStack` every time, which matters
because stacks are consumed when put into an inventory.

```dart
const sword = ItemSpec('diamond_sword', name: '&6Excalibur', lore: ['Sharp'],
    enchantments: [(Enchantment.sharpness, 5)], unbreakable: true);
player.inventory.give(sword.build());

final stack = ItemBuilder('apple').name('Snack').count(3).glint().build();
```

Names and lore use `&` colour codes and are non-italic unless `italic: true`.
Data components are set through `ItemStack.setComponent` with the protocol
encoding (`ComponentBytes`).

Host limits: `tooltip-display` can't hide parts of the tooltip (the host
ignores the hidden list), and the glint override can only be forced on.

## Menus

```dart
final menu = Menu(title: 'Shop', rows: 3)
  ..border(const ItemSpec('gray_stained_glass_pane', name: ' '))
  ..button(row: 1, column: 4, item: const ItemSpec('diamond'),
      onClick: (click) => click.update(13, const ItemSpec('emerald')));
menu.open(player);
```

* `Menu.button/set/clear/fill/border/fillRow/fillColumn`, `onOpen`, `onClose`.
* `MenuClick`: `player`, `playerName`, `playerId`, `slot`, `row`, `column`,
  `type` (`ClickType`), `isLeft/isRight/isShift`, `page`, `update(slot, item)`,
  `refresh()`, `open(otherMenu)`.
* `PagedMenu<T>`: entries from `items()`, rendered by `render(entry)`, previous
  and next buttons and a page indicator in the bottom row, a page per player.
* `MenuLayout` / `PageLayout` (binding-free, unit tested) do the slot maths.

How it works: `Menu.open` builds a `Gui` (screen `generic-9xN`, grab and put
disabled), keeps its `Inventory` to change slots later, and calls
`Player.openGui`. The host has no menu id in its events, so menus are tracked
per player (UUID) from `open` until `inventory-close-event` or leaving. While a
menu is open, every click and drag is cancelled; clicks in the player's own
inventory are cancelled only for shift, double-click and number-key clicks.

Gaps in the host API:

* A menu can't be closed by code (no close call). Replace it by opening
  another menu; the old one gets `onClose`.
* A click handler runs inside a blocking event, so `MenuClick.open` opens the
  next menu on the following tick.
* Click handlers are synchronous (the event is intercepted); start futures
  yourself for async work.
* In-place slot changes rely on the host syncing the open window; if a client
  doesn't redraw, use `menu.reopen(player)`.
* Item names/titles are strings (plus `&` codes); no `TextComponent` input.

## Typed persistent data

```dart
const kills = IntKey('kills', defaultValue: 0);
const home = DataKey<List<double>>.custom(...);   // not const: use final
const ns = PluginData('my_plugin');

player.data(ns).update(kills, (n) => n + 1);
final n = world.data(ns).get(kills);
```

Keys: `IntKey`, `StringKey`, `BoolKey`, `DoubleKey`, `StringListKey` (const),
`DataKey<T>(name)` for those types, `DataKey.custom(name, encode:, decode:)`
(stored as a string, e.g. JSON; decode errors read as missing) and
`DataKey.withCodec` for a const key with a const `DataCodec.string`. `data(ns)`
exists on `Player`, `Entity`, `ItemStack`, `World`, `Chunk`, `BlockEntity` and
returns `TypedData` with `get`, `getOrNull`, `set`, `update`, `has`, `remove`.
Integers are stored as longs. `DataStore`/`MemoryDataStore` make the logic
testable without a server.

## Registry keys

`RegistryKeys.normalize('zombie') == 'minecraft:zombie'`, `toWireName`,
`fromWireName`, and `registryKey` / `XxxKey.fromKey` for `EntityType`,
`Biome`, `Particle`, `Enchantment`, `Attribute`, `DamageType`
(e.g. `EntityTypeKey.fromKey('zombie')`). Sounds are not covered: their wire
names don't map to dotted registry keys.
