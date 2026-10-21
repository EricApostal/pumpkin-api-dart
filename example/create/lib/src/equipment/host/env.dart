// Shared state of the equipment module's host glue: settings, services, id
// resolvers and small helpers every feature uses. Host-touching.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/advancements.dart';
import '../../api/payloads.dart';
import '../../api/sounds.dart';
import '../../api/wrenchable.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../equipment_settings.dart';
import '../model/dir.dart';

/// `InteractionHand` helpers: the host's `Hand.right` is the main hand.
extension EqHand on Hand {
  bool get isMain => this == Hand.right;
  Hand get other => this == Hand.right ? Hand.left : Hand.right;
}

extension EqBlockDirection on BlockDirection {
  Dir get dir => Dir.values[index];
}

extension EqDir on Dir {
  BlockDirection get host => BlockDirection.values[index];
}

extension EqBlockPos on BlockPos {
  P3 get p3 => (x, y, z);
}

extension EqP3 on (int, int, int) {
  BlockPos get blockPos => BlockPos(x: $1, y: $2, z: $3);
}

/// What every feature needs.
final class EquipmentEnv {
  final CreateContext ctx;
  final EquipmentSettings settings;
  final Logger log;
  final PayloadBus bus;
  final WrenchRegistry wrench;

  /// `Create.RANDOM`.
  final math.Random rng = math.Random();

  EquipmentEnv({
    required this.ctx,
    required this.settings,
    required this.bus,
    required this.wrench,
  }) : log = ctx.log;

  /// The online player with [uuid] (the payload bus keeps the roster's handles alive).
  Player? playerByUuid(String uuid) {
    for (final p in bus.roster.players) {
      try {
        if (p.getId().asString == uuid) return p;
      } on Object {
        // handle no longer valid
      }
    }
    return null;
  }

  CreateSounds? get sounds => ctx.services.find<CreateSounds>();
  CreateAdvancements? get advancements => ctx.services.find<CreateAdvancements>();

  /// Item ids of this plugin and vanilla, for [ItemStackData].
  late final ItemIdResolver itemIds = ItemIdResolver.vanilla(
    custom: (key) => ctx.ids.of(RegistryKind.items, key),
    customKey: (id) {
      for (final e in ctx.ids.all(RegistryKind.items).entries) {
        if (e.value == id) return e.key;
      }
      return null;
    },
  );

  /// Plays a Create sound if the content module provides the service.
  void playSound(World world, Vec3 pos, String name, {double volume = 1, double pitch = 1}) {
    try {
      sounds?.play(world, pos, name, volume: volume, pitch: pitch);
    } on Object catch (e) {
      log.debug('sound $name failed: $e');
    }
  }

  void playSoundAtBlock(World world, P3 pos, String name, {double volume = 1, double pitch = 1}) {
    try {
      sounds?.playAtBlock(world, pos, name, volume: volume, pitch: pitch);
    } on Object catch (e) {
      log.debug('sound $name failed: $e');
    }
  }

  /// `CreateAdvancement.awardTo(player)` for `AllAdvancements.<id>`; failures are logged.
  Future<void> award(Player player, String id) async {
    final adv = advancements;
    if (adv == null) return;
    try {
      if (adv.canAward(id)) await adv.award(player, id);
    } on Object catch (e) {
      log.debug('advancement $id failed: $e');
    }
  }
}

typedef Vec3 = (double, double, double);

/// A block key with its namespace.
///
/// `World.getBlockState().blockName` is the **bare** name for a vanilla block (`farmland`,
/// `waxed_copper_block`) and the full key for a plugin block, while the keys this module
/// compares against are always namespaced; `BlockStates.blockKey(stateId)` gives the
/// namespaced form from the state id alone.
String namespacedBlockKey(String blockKey) =>
    blockKey.contains(':') ? blockKey : 'minecraft:$blockKey';

/// Item keys of the equipment module.
abstract final class EqItems {
  static const wrench = 'create:wrench';
  static const goggles = 'create:goggles';
  static const extendoGrip = 'create:extendo_grip';
  static const potatoCannon = 'create:potato_cannon';
  static const wandOfSymmetry = 'create:wand_of_symmetry';
  static const worldshaper = 'create:handheld_worldshaper';
  static const sandPaper = 'create:sand_paper';
  static const redSandPaper = 'create:red_sand_paper';
  static const cardboardSword = 'create:cardboard_sword';
  static const craftingBlueprint = 'create:crafting_blueprint';
  static const treeFertilizer = 'create:tree_fertilizer';
  static const buildersTea = 'create:builders_tea';
  static const copperBacktank = 'create:copper_backtank';
  static const netheriteBacktank = 'create:netherite_backtank';
  static const copperBacktankPlaceable = 'create:copper_backtank_placeable';
  static const netheriteBacktankPlaceable = 'create:netherite_backtank_placeable';
  static const clipboard = 'create:clipboard';
  static const divingHelmet = 'create:copper_diving_helmet';
  static const divingBoots = 'create:copper_diving_boots';
  static const netheriteDivingHelmet = 'create:netherite_diving_helmet';
  static const netheriteDivingBoots = 'create:netherite_diving_boots';
  static const cardboardHelmet = 'create:cardboard_helmet';
  static const cardboardChestplate = 'create:cardboard_chestplate';
  static const cardboardLeggings = 'create:cardboard_leggings';
  static const cardboardBoots = 'create:cardboard_boots';

  static bool isSandPaper(String key) => key == sandPaper || key == redSandPaper;
  static bool isBacktank(String key) => key == copperBacktank || key == netheriteBacktank;
  static bool isDivingHelmet(String key) => key == divingHelmet || key == netheriteDivingHelmet;
  static bool isDivingBoots(String key) => key == divingBoots || key == netheriteDivingBoots;
  static bool isCardboardArmor(String key) =>
      key == cardboardHelmet || key == cardboardChestplate || key == cardboardLeggings || key == cardboardBoots;
  static bool isNetheriteArmor(String key) =>
      key == netheriteBacktank || key == netheriteDivingHelmet || key == netheriteDivingBoots;
}

/// Reads the registry key of an optional stack ('' for none).
Future<String> stackKey(ItemStack? stack) async => stack == null ? '' : await stack.getRegistryKey();

/// Reads a custom component, `null` when absent.
Uint8List? readComponent(ItemStack stack, String key) {
  try {
    return stack.customComponent(key);
  } on Object {
    return null;
  }
}

/// Fire-and-forget with logging.
void spawn(Future<void> Function() body, Logger log, String what) {
  unawaited(
    body().catchError((Object e, StackTrace st) {
      log.warn('$what failed: $e');
    }),
  );
}

/// The level of the custom enchantment [id] on [stack] (0 when absent).
Future<int> customEnchantLevel(ItemStack stack, String id) async =>
    await stack.getCustomEnchantmentLevel(enchantmentId: id) ?? 0;
