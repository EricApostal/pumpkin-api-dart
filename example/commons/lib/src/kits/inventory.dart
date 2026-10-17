import 'package:pumpkin_api/pumpkin_api.dart';

import 'catalog.dart';
import 'model.dart';
import 'service.dart';

const _slots = 36;

/// Max stack sizes already looked up (the host has no registry call, so a
/// throw-away stack is asked).
final Map<String, int> _maxStacks = {};

Future<int> _maxStackOf(String key) async {
  final known = _maxStacks[key];
  if (known != null) return known;
  final probe = ItemStack.create(registryKey: key, count: 1);
  final int max;
  try {
    max = await probe.getMaxCount();
  } finally {
    probe.dispose();
  }
  return _maxStacks[key] = max < 1 ? 1 : max;
}

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
Future<ItemSpec> previewSpec(KitItem item) async => _spec(
  item,
  item.count.clamp(1, await _maxStackOf(normalizeItemKey(item.item))),
);

/// The stacks [items] turn into, splitting counts above the max stack size.
Future<List<ItemSpec>> stacksOf(List<KitItem> items) async => [
  for (final item in items)
    ..._split(
      item.count,
      await _maxStackOf(normalizeItemKey(item.item)),
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
  Future<bool> hasPermission(String node) => _player.hasPermission(node: node);

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
  Future<bool> canFit(List<KitItem> items) async =>
      (await stacksOf(items)).length <=
      _emptySlots(_player.getInventory().storage).length;

  @override
  Future<void> give(List<KitItem> items) async {
    final inv = _player.getInventory().storage;
    // Build the stacks first: the slots are looked at right before they are
    // written, so the player can't move items into them in between.
    final stacks = [
      for (final spec in await stacksOf(items)) await spec.build(),
    ];
    final empty = _emptySlots(inv);
    if (stacks.length > empty.length) {
      for (final stack in stacks) {
        stack.dispose();
      }
      throw StateError('Not enough room for ${stacks.length} stacks');
    }
    final placed = <int>[];
    try {
      for (var i = 0; i < stacks.length; i++) {
        if (inv.getItem(slot: empty[i]) != null) {
          throw StateError('Slot ${empty[i]} was taken');
        }
        await inv.setItem(slot: empty[i], item: stacks[i]);
        placed.add(empty[i]);
      }
    } catch (_) {
      for (var i = placed.length + 1; i < stacks.length; i++) {
        stacks[i].dispose();
      }
      for (final slot in placed) {
        await inv.setItem(slot: slot, item: null);
      }
      rethrow;
    }
  }

  /// What the player carries (the 36 hotbar and storage slots) as kit items,
  /// for `/kit create`. Names and lore are copied as plain text: the host
  /// does not tell their colors, edit `kits.json` to add them.
  Future<List<KitItem>> capture() async {
    final inv = _player.getInventory().storage;
    final items = <KitItem>[];
    for (var slot = 0; slot < _slots; slot++) {
      final stack = inv.getItem(slot: slot);
      if (stack == null) continue;
      items.add(
        KitItem(
          item: await stack.getRegistryKey(),
          count: await stack.getCount(),
          name: (await stack.getCustomName())?.getText(),
          lore: [for (final line in await stack.getLore()) line.getText()],
          enchantments: {
            for (final e in await stack.getEnchantments())
              RegistryKeys.path(e.enchantment.registryKey): e.level,
          },
        ),
      );
    }
    return items;
  }
}
