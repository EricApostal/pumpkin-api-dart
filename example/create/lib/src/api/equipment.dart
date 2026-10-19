/// Services of the `equipment` module for the other modules.
///
/// ```dart
/// final backtanks = ctx.services.require<BacktankApi>();
/// if (await backtanks.canAbsorbDamage(livingEntity, 200)) { ... }   // air powered tools
/// final goggles = ctx.services.find<GogglesApi>();
/// final stealth = ctx.services.find<CardboardArmorApi>();           // belts ignore hidden entities
/// ```
///
/// The equipment module also *consumes* one service: if the kinetics module provides a
/// [KineticSpeedLookup] the backtank block entity fills while its shaft turns.
library;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../equipment/data/equipment_components.dart';

/// `BacktankUtil`.
abstract interface class BacktankApi {
  /// `getAllWithAir(entity)`: worn backtanks with air, the emptiest first.
  Future<List<ItemStack>> getAllWithAir(LivingEntity entity);

  /// `hasAirRemaining(backtank)`.
  Future<bool> hasAirRemaining(ItemStack backtank);

  /// `getAir(backtank)`: the stored air capped to the maximum.
  Future<int> getAir(ItemStack backtank);

  /// `maxAir(backtank)` including the `create:capacity` enchantment.
  Future<int> maxAir(ItemStack backtank);

  /// `maxAirWithoutEnchants()`.
  int get maxAirWithoutEnchants;

  /// `consumeAir(entity, backtank, amount)`: lowers the air; with [player] (the entity when it is
  /// a player) the low / depleted warning is shown.
  Future<void> consumeAir(LivingEntity entity, ItemStack backtank, int amount, {Player? player});

  /// `canAbsorbDamage(entity, usesPerTank)`: true if the entity may use the tool for free
  /// (0 uses = unbreakable, creative, or a backtank paid for it).
  Future<bool> canAbsorbDamage(LivingEntity entity, int usesPerTank, {Player? player});

  /// `addBacktankSupplier`: more places to look for backtanks (curios slots, ...).
  void addBacktankSupplier(Future<List<ItemStack>> Function(LivingEntity entity) supplier);
}

/// `GogglesItem`.
abstract interface class GogglesApi {
  /// `isWearingGoggles(player)`.
  Future<bool> isWearingGoggles(Player player);

  /// `addIsWearingPredicate`.
  void addIsWearingPredicate(Future<bool> Function(Player player) predicate);
}

/// `CardboardArmorHandler`.
abstract interface class CardboardArmorApi {
  /// `testForStealth(entity)`: crouching in a full set of cardboard armor.
  Future<bool> testForStealth(Entity? entity);
}

/// `ExtendoGripItem`.
abstract interface class ExtendoGripApi {
  /// `isHoldingExtendoGrip(player)`.
  Future<bool> isHoldingExtendoGrip(Player player);
}

/// `SandPaperPolishingRecipe`: the recipes of `create:sandpaper_polishing`. The one recipe of
/// the mod (rose quartz) is built in; the processing module adds the ones of data packs.
abstract interface class SandPaperApi {
  /// Registers the recipe [inputKey] -> [outputKey] (item keys).
  void addPolishingRecipe(String inputKey, String outputKey);

  /// The result of polishing [inputKey], or `null`.
  String? polishResult(String inputKey);
}

/// Offered by the kinetics module: the current rotation speed (RPM) of the kinetic block
/// entity at a position, or `null` when there is none. The backtank block uses it.
abstract interface class KineticSpeedLookup {
  double? speedAt(String worldId, (int, int, int) pos);
}

/// `ClipboardCloneable`: a block entity (or behaviour) whose settings can be copied to a clipboard
/// by right-clicking it with a clipboard and pasted with a left click. Implement it on the block
/// entity class (`class FilterBlockEntity extends CreateBlockEntity implements ClipboardCloneable`);
/// a block entity with several implementations lists them through [ClipboardCloneables].
abstract interface class ClipboardCloneable {
  /// The key under which the copied values are stored (`filtering`, `scroll_value`, ...).
  String get clipboardKey;

  /// `writeToClipboard(tag, side)`: stores the settings in [tag]; false if there is nothing to copy.
  bool writeToClipboard(NbtCompound tag, BlockDirection side);

  /// `readFromClipboard(tag, player, side, simulate)`: applies the copied settings (or only checks
  /// that they would apply, with [simulate]).
  bool readFromClipboard(NbtCompound tag, Player player, BlockDirection side, bool simulate);
}

/// A block entity with several [ClipboardCloneable]s (Create's behaviours).
abstract interface class ClipboardCloneables {
  List<ClipboardCloneable> get clipboardCloneables;
}

/// The text of the first entry of the clipboard item [stack] (what a nixie tube shows), or `null`.
Future<String?> clipboardFirstEntryText(ItemStack stack) async {
  final raw = stack.customComponent(EquipmentComponents.clipboardContent);
  if (raw == null) return null;
  try {
    final content = EquipmentWire.readClipboardContent(raw);
    for (final page in content.pages) {
      if (page.isNotEmpty) return page.first.plainText;
    }
  } on Object {
    return null;
  }
  return null;
}
