import 'model.dart';

const _day = 24 * 60 * 60;

/// The kits written to `kits/kits.json` on first run.
KitCatalog defaultKits() => const KitCatalog(
  kits: [
    Kit(
      name: 'starter',
      displayName: '&aStarter kit',
      icon: 'wooden_sword',
      oneTime: true,
      items: [
        KitItem(item: 'stone_sword'),
        KitItem(item: 'stone_pickaxe'),
        KitItem(item: 'stone_axe'),
        KitItem(item: 'stone_shovel'),
        KitItem(item: 'bread', count: 16),
        KitItem(item: 'torch', count: 16),
      ],
    ),
    Kit(
      name: 'daily',
      displayName: '&eDaily supplies',
      icon: 'bread',
      cooldownSeconds: _day,
      items: [
        KitItem(item: 'cooked_beef', count: 16),
        KitItem(item: 'iron_ingot', count: 8),
        KitItem(item: 'coal', count: 16),
        KitItem(item: 'experience_bottle', count: 4),
      ],
    ),
    Kit(
      name: 'vip',
      displayName: '&bVIP crate',
      icon: 'diamond',
      cooldownSeconds: 7 * _day,
      restricted: true,
      items: [
        KitItem(
          item: 'diamond_pickaxe',
          name: '&bVIP pickaxe',
          lore: ['&7A gift for our supporters'],
          enchantments: {'efficiency': 3, 'unbreaking': 2},
        ),
        KitItem(item: 'diamond', count: 8),
        KitItem(item: 'golden_apple', count: 4),
        KitItem(item: 'ender_pearl', count: 8),
      ],
    ),
  ],
);
