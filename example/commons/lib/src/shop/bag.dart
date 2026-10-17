import 'package:pumpkin_api/pumpkin_api.dart';

import 'service.dart';

/// The item the player holds in the main hand.
typedef HeldItem = ({String key, int count, bool plain});

/// A player's main inventory (the 36 hotbar and storage slots, not armor or
/// the off hand) as an [ItemBag].
///
/// Only *plain* stacks are sold or topped up: no custom name, no lore, no
/// enchantments and no durability damage. That keeps renamed or enchanted
/// items, and worn tools, out of the shop.
final class PlayerBag implements ItemBag {
  static const _slots = 36;

  /// Max stack sizes already looked up (the host has no registry call, so a
  /// throw-away stack is asked).
  static final Map<String, int> _maxStack = {};

  final Player _player;

  PlayerBag(this._player);

  Inventory get _storage => _player.getInventory().storage;

  static Future<int> _maxStackOf(String key) async {
    final known = _maxStack[key];
    if (known != null) return known;
    final probe = ItemStack.create(registryKey: key, count: 1);
    final int max;
    try {
      max = await probe.getMaxCount();
    } finally {
      probe.dispose();
    }
    return _maxStack[key] = max < 1 ? 1 : max;
  }

  /// Whether [stack] is an ordinary stack of its item.
  static Future<bool> isPlain(ItemStack stack) async {
    if (await stack.getCustomName() != null) return false;
    if ((await stack.getLore()).isNotEmpty) return false;
    if ((await stack.getEnchantments()).isNotEmpty) return false;
    for (final c in await stack.getComponents()) {
      // A varint of 0 is a single zero byte: anything else is damage.
      if (c.component == DataComponent.damage && c.value.any((b) => b != 0)) {
        return false;
      }
    }
    return true;
  }

  /// What the player holds, or `null` for an empty hand.
  Future<HeldItem?> held() async {
    final stack = _player.getInventory().heldItem;
    if (stack == null) return null;
    return (
      key: normalizeRegistryKey(await stack.getRegistryKey()),
      count: await stack.getCount(),
      plain: await isPlain(stack),
    );
  }

  @override
  Future<int> spaceFor(String key) async {
    final id = normalizeRegistryKey(key);
    final max = await _maxStackOf(id);
    final inv = _storage;
    var room = 0;
    for (var slot = 0; slot < _slots; slot++) {
      final stack = inv.getItem(slot: slot);
      if (stack == null) {
        room += max;
        continue;
      }
      final count = await stack.getCount();
      if (registryKeysMatch(await stack.getRegistryKey(), id) &&
          count < max &&
          await isPlain(stack)) {
        room += max - count;
      }
    }
    return room;
  }

  @override
  Future<int> countOf(String key) async {
    final id = normalizeRegistryKey(key);
    final inv = _storage;
    var total = 0;
    for (var slot = 0; slot < _slots; slot++) {
      final stack = inv.getItem(slot: slot);
      if (stack != null &&
          registryKeysMatch(await stack.getRegistryKey(), id) &&
          await isPlain(stack)) {
        total += await stack.getCount();
      }
    }
    return total;
  }

  @override
  Future<int> add(String key, int count) => _player.giveItem(key, count: count);

  @override
  Future<int> remove(String key, int count) async {
    final id = normalizeRegistryKey(key);
    final inv = _storage;
    var left = count;
    for (var slot = 0; slot < _slots && left > 0; slot++) {
      final stack = inv.getItem(slot: slot);
      if (stack == null ||
          !registryKeysMatch(await stack.getRegistryKey(), id) ||
          !await isPlain(stack)) {
        continue;
      }
      final have = await stack.getCount();
      final take = have < left ? have : left;
      if (take == have) {
        await inv.setItem(slot: slot, item: null);
      } else {
        await stack.setCount(count: have - take);
        await inv.setItem(slot: slot, item: stack);
      }
      left -= take;
    }
    return count - left;
  }
}

/// A [Player] as a [Shopper]. Only valid while the player handle is.
final class PlayerShopper implements Shopper {
  final Player _player;

  @override
  final String uuid;

  @override
  final String name;

  @override
  final PlayerBag bag;

  PlayerShopper(Player player)
    : _player = player,
      uuid = player.asEntity().getUuid().asString,
      name = player.getName(),
      bag = PlayerBag(player);

  @override
  Future<bool> hasPermission(String node) => _player.hasPermission(node: node);
}
