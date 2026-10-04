import 'package:pumpkin_api/pumpkin_api.dart';

import 'catalog.dart';
import 'model.dart';
import 'service.dart';

const _slots = 36;

/// Max stack sizes already looked up (the host has no registry call, so a
/// throw-away stack is asked).
final Map<String, int> _maxStacks = {};

int _maxStackOf(String key) => _maxStacks.putIfAbsent(key, () {
  final probe = ItemStack.create(registryKey: key, count: 1);
  final max = probe.getMaxCount();
  probe.dispose();
  return max < 1 ? 1 : max;
});

/// The spec of one stack of [item]: its name, lore and enchantments.
ItemSpec _spec(KitItem item, int count) => ItemSpec(
  item.item,
  count: count,
  name: item.name,
  lore: item.lore,
  enchantments: [
    for (final MapEntry(key: key, value: level) in item.enchantments.entries)
      if (EnchantmentKey.fromKey(key) case final enchantment?)
        (enchantment, level),
  ],
);

/// How [item] looks as a single icon, for previews: the count is limited to
/// a stack.
ItemSpec previewSpec(KitItem item) =>
    _spec(item, item.count.clamp(1, _maxStackOf(normalizeItemKey(item.item))));

/// The stacks [items] turn into, splitting counts above the max stack size.
List<ItemSpec> stacksOf(List<KitItem> items) => [
  for (final item in items)
    ..._split(
      item.count,
      _maxStackOf(normalizeItemKey(item.item)),
    ).map((n) => _spec(item, n)),
];

List<int> _split(int count, int max) => [
  for (var left = count; left > 0; left -= max) left < max ? left : max,
];

/// A [Player]'s main inventory as a [KitRecipient]. Only valid while the
/// player handle is.
final class PlayerKitRecipient implements KitRecipient {
  final Player _player;

  @override
  final String uuid;

  @override
  final String name;

  PlayerKitRecipient(Player player)
    : _player = player,
      uuid = player.asEntity().getUuid().asString,
      name = player.getName();

  @override
  bool hasPermission(String node) => _player.hasPermission(node: node);

  List<int> _emptySlots(Inventory inv) {
    final all = inv.getAllItems();
    return [
      for (var i = 0; i < all.length && i < _slots; i++)
        if (all[i] == null) i,
    ];
  }

  /// Kits go into empty slots only: they never merge into stacks the player
  /// already has, so named and enchanted items stay as they are.
  @override
  bool canFit(List<KitItem> items) =>
      stacksOf(items).length <=
      _emptySlots(_player.getInventory().storage).length;

  @override
  void give(List<KitItem> items) {
    final inv = _player.getInventory().storage;
    final stacks = stacksOf(items);
    final empty = _emptySlots(inv);
    if (stacks.length > empty.length) {
      throw StateError('Not enough room for ${stacks.length} stacks');
    }
    final placed = <int>[];
    try {
      for (var i = 0; i < stacks.length; i++) {
        inv.setItem(slot: empty[i], item: stacks[i].build());
        placed.add(empty[i]);
      }
    } catch (_) {
      for (final slot in placed) {
        inv.setItem(slot: slot, item: null);
      }
      rethrow;
    }
  }

  /// What the player carries (the 36 hotbar and storage slots) as kit items,
  /// for `/kit create`. Names and lore are copied as plain text: the host
  /// does not tell their colors, edit `kits.json` to add them.
  List<KitItem> capture() {
    final inv = _player.getInventory().storage;
    final items = <KitItem>[];
    for (var slot = 0; slot < _slots; slot++) {
      final stack = inv.getItem(slot: slot);
      if (stack == null) continue;
      items.add(
        KitItem(
          item: stack.getRegistryKey(),
          count: stack.getCount(),
          name: stack.getCustomName()?.getText(),
          lore: [for (final line in stack.getLore()) line.getText()],
          enchantments: {
            for (final e in stack.getEnchantments())
              RegistryKeys.path(e.enchantment.registryKey): e.level,
          },
        ),
      );
    }
    return items;
  }
}
