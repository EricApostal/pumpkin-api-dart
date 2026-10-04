import 'package:dart_mappable/dart_mappable.dart';

part 'model.mapper.dart';

/// One stack of a kit. Like the `ItemSpec` of `pumpkin_api`, but plain data
/// without server types, so it can be stored and tested.
@MappableClass(ignoreNull: true)
class KitItem with KitItemMappable {
  /// Registry key, `bread` or `minecraft:bread`.
  final String item;

  final int count;

  /// Custom name (`&` colour codes), or `null` for the item's own name.
  final String? name;

  final List<String> lore;

  /// Enchantment registry key (`sharpness`) to level.
  final Map<String, int> enchantments;

  const KitItem({
    required this.item,
    this.count = 1,
    this.name,
    this.lore = const [],
    this.enchantments = const {},
  });
}

/// A set of items players can claim.
@MappableClass(ignoreNull: true)
class Kit with KitMappable {
  /// Short lowercase name used in commands and in the permission node
  /// `commons:kits.kit.<name>`.
  final String name;

  /// Name shown in menus (`&` colour codes). Defaults to [name].
  final String? displayName;

  /// Registry key of the item that represents the kit in the menu.
  final String icon;

  final List<KitItem> items;

  /// How long a player must wait between two claims; `0` means none.
  final int cooldownSeconds;

  /// Whether each player can claim the kit only once, ever.
  final bool oneTime;

  /// What claiming costs, in whole currency units; `0` is free.
  final int price;

  /// Whether the permission to claim the kit is for operators only unless it
  /// is granted explicitly (otherwise everybody has it).
  final bool restricted;

  const Kit({
    required this.name,
    this.displayName,
    this.icon = 'chest',
    this.items = const [],
    this.cooldownSeconds = 0,
    this.oneTime = false,
    this.price = 0,
    this.restricted = false,
  });

  Duration get cooldown => Duration(seconds: cooldownSeconds);

  /// The name for menus and messages.
  String get title => displayName ?? name;

  /// The permission node a player needs to claim this kit.
  String get permission => kitPermission(name);
}

/// `commons:kits.kit.<name>`.
String kitPermission(String name) => 'commons:kits.kit.$name';

/// The content of `kits/kits.json`.
@MappableClass()
class KitCatalog with KitCatalogMappable {
  final List<Kit> kits;

  const KitCatalog({this.kits = const []});
}

/// The content of `kits/config.json`.
@MappableClass()
class KitsConfig with KitsConfigMappable {
  /// Give [starterKit] to players who join for the first time.
  final bool giveStarterKit;

  final String starterKit;

  /// Put before every kit message (`&` colour codes).
  final String prefix;

  const KitsConfig({
    this.giveStarterKit = true,
    this.starterKit = 'starter',
    this.prefix = '&8[&6Kits&8] &r',
  });
}

/// A player's history with one kit.
@MappableClass()
class KitClaim with KitClaimMappable {
  final DateTime lastClaimed;
  final int count;

  const KitClaim({required this.lastClaimed, required this.count});
}

/// The content of `kits/claims.json`: player UUID, then kit name.
@MappableClass()
class KitClaims with KitClaimsMappable {
  final Map<String, Map<String, KitClaim>> players;

  const KitClaims({this.players = const {}});
}
