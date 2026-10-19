// `BacktankUtil` over the host: the air of worn backtanks, consumption with warnings.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/equipment.dart';
import '../data/equipment_components.dart';
import '../host/env.dart';
import 'backtank_math.dart';

typedef BacktankSupplier = Future<List<ItemStack>> Function(LivingEntity entity);

final class BacktankHost implements BacktankApi {
  final EquipmentEnv env;
  final List<BacktankSupplier> _suppliers = [];

  BacktankHost(this.env) {
    _suppliers.add(_wornArmor);
  }

  static const _armorSlots = [EquipmentSlot.head, EquipmentSlot.chest, EquipmentSlot.legs, EquipmentSlot.feet];

  /// The default supplier: armor slots holding an item of `#create:pressurized_air_sources`.
  Future<List<ItemStack>> _wornArmor(LivingEntity entity) async {
    final stacks = <ItemStack>[];
    for (final slot in _armorSlots) {
      final s = entity.getEquipment(slot: slot);
      if (s == null) continue;
      if (Tags.item(await s.getRegistryKey(), 'create:pressurized_air_sources')) stacks.add(s);
    }
    return stacks;
  }

  @override
  void addBacktankSupplier(BacktankSupplier supplier) => _suppliers.add(supplier);

  @override
  Future<List<ItemStack>> getAllWithAir(LivingEntity entity) async {
    final all = <(int, ItemStack)>[];
    for (final supplier in _suppliers) {
      for (final stack in await supplier(entity)) {
        final air = await getAir(stack);
        if (air > 0) all.add((air, stack));
      }
    }
    // Ascending: prioritise the most empty so things actually run out.
    all.sort((a, b) => BacktankMath.compareAir(a.$1, b.$1));
    return [for (final e in all) e.$2];
  }

  @override
  Future<bool> hasAirRemaining(ItemStack backtank) async => await getAir(backtank) > 0;

  /// The raw stored air (`BacktankItem.getRemainingAir`).
  int storedAir(ItemStack backtank) {
    final b = readComponent(backtank, EquipmentComponents.backtankAir);
    return b == null ? 0 : EquipmentWire.readVarInt(b);
  }

  void setStoredAir(ItemStack backtank, int air) =>
      backtank.setCustomComponent(EquipmentComponents.backtankAir, EquipmentWire.varInt(air));

  @override
  Future<int> getAir(ItemStack backtank) async => BacktankMath.air(storedAir(backtank), await maxAir(backtank));

  @override
  Future<int> maxAir(ItemStack backtank) async => maxAirFor(await customEnchantLevel(backtank, 'create:capacity'));

  int maxAirFor(int enchantLevel) => BacktankMath.maxAir(
    airInBacktank: env.settings.airInBacktank,
    enchantedCapacity: env.settings.enchantedBacktankCapacity,
    enchantLevel: enchantLevel,
  );

  @override
  int get maxAirWithoutEnchants => env.settings.airInBacktank;

  @override
  Future<void> consumeAir(LivingEntity entity, ItemStack backtank, int amount, {Player? player}) async {
    final max = await maxAir(backtank);
    final air = await getAir(backtank);
    final newAir = BacktankMath.consume(air, amount, max);
    setStoredAir(backtank, newAir);
    if (player == null) return;
    _sendWarning(player, air, newAir, max / 10);
    _sendWarning(player, air, newAir, 1);
  }

  void _sendWarning(Player player, num air, num newAir, num threshold) {
    if (!BacktankMath.crossesWarning(air, newAir, threshold)) return;
    final depleted = threshold == 1;
    final world = player.getWorld();
    final pos = player.getPosition();
    env.playSound(world, pos, 'deny', pitch: 1.25);
    env.playSound(world, pos, 'steam', volume: 0.5, pitch: 0.5);
    player.sendTitleAnimation(fadeIn: 10, stay: 40, fadeOut: 10);
    // The title itself is empty, the subtitle carries the warning.
    final label = depleted ? 'Backtank depleted' : 'Backtank running low';
    player.showSubtitle(text: Messages.component('${depleted ? '&c' : '&6'}⚠ &7$label'));
    player.showTitle(text: Messages.component(' '));
  }

  @override
  Future<bool> canAbsorbDamage(LivingEntity entity, int usesPerTank, {Player? player}) async {
    if (usesPerTank == 0) return true;
    if (player != null && player.isCreative) return true;
    final tanks = await getAllWithAir(entity);
    if (tanks.isEmpty) return false;
    final cost = BacktankMath.usageCost(maxAirWithoutEnchants, usesPerTank);
    await consumeAir(entity, tanks.first, cost, player: player);
    return true;
  }
}
