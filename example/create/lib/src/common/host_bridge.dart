// Conversions between the pure helper types of `common/` and the host bindings,
// plus the host-touching parts of `BlockHelper` and `NBTHelper`.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart' as host;
import 'package:pumpkin_api/pumpkin_api.dart' show BlockDirection, BlockPos, BlockRegistry, NbtCompound, World;

import 'direction.dart';
import 'vec_helper.dart' show Vec3;
import 'pos.dart';

extension PosToHost on (int, int, int) {
  /// The host's `BlockPos`.
  BlockPos toBlockPos() => BlockPos(x: $1, y: $2, z: $3);
}

extension BlockPosToPos on BlockPos {
  /// The pure position record.
  Pos toPos() => (x, y, z);
}

extension DirectionToHost on Direction {
  BlockDirection toHost() => BlockDirection.values[index];
}

extension BlockDirectionToPure on BlockDirection {
  Direction toDirection() => Direction.values[index];
}

extension RotationToHost on BlockRotation {
  host.Rotation toHost() => switch (this) {
    BlockRotation.none => host.Rotation.none,
    BlockRotation.clockwise90 => host.Rotation.clockwise90,
    BlockRotation.clockwise180 => host.Rotation.rotate180,
    BlockRotation.counterclockwise90 => host.Rotation.counterClockwise90,
  };
}

extension HostRotationToPure on host.Rotation {
  BlockRotation toPure() => switch (this) {
    host.Rotation.none => BlockRotation.none,
    host.Rotation.clockwise90 => BlockRotation.clockwise90,
    host.Rotation.rotate180 => BlockRotation.clockwise180,
    host.Rotation.counterClockwise90 => BlockRotation.counterclockwise90,
  };
}

extension MirrorToHost on BlockMirror {
  host.Mirror toHost() => switch (this) {
    BlockMirror.none => host.Mirror.none,
    BlockMirror.leftRight => host.Mirror.leftRight,
    BlockMirror.frontBack => host.Mirror.frontBack,
  };
}

extension HostMirrorToPure on host.Mirror {
  BlockMirror toPure() => switch (this) {
    host.Mirror.none => BlockMirror.none,
    host.Mirror.leftRight => BlockMirror.leftRight,
    host.Mirror.frontBack => BlockMirror.frontBack,
  };
}

/// Block state helpers by state id (the host numbers block states).
abstract final class BlockStates {
  /// The block key and properties of [stateId] (`null` when unknown).
  static ({String key, Map<String, String> properties})? info(int stateId) {
    final i = BlockRegistry.stateInfo(stateId);
    if (i == null) return null;
    return (key: i.name, properties: {for (final (k, v) in i.properties) k: v});
  }

  /// `BlockState.hasProperty`.
  static bool hasProperty(int stateId, String property) => info(stateId)?.properties.containsKey(property) ?? false;

  /// `BlockState.setValue(property, value)`: the state with one property changed, or the same
  /// state when the block does not have the property or the value is invalid.
  static int setValue(int stateId, String property, String value) {
    final i = info(stateId);
    if (i == null || !i.properties.containsKey(property)) return stateId;
    return BlockRegistry.resolveState(i.key, {...i.properties, property: value}) ?? stateId;
  }

  /// `BlockState.setValue` for several properties.
  static int setValues(int stateId, Map<String, String> values) {
    final i = info(stateId);
    if (i == null) return stateId;
    final merged = {...i.properties};
    for (final e in values.entries) {
      if (merged.containsKey(e.key)) merged[e.key] = e.value;
    }
    return BlockRegistry.resolveState(i.key, merged) ?? stateId;
  }

  /// `BlockState.getValue` as a string, or `null`.
  static String? value(int stateId, String property) => info(stateId)?.properties[property];

  /// The key of the block of [stateId].
  static String? blockKey(int stateId) => info(stateId)?.key;

  /// `BlockState.is(Block)`.
  static bool isBlock(int stateId, String key) => blockKey(stateId) == key;

  /// `BlockState.is(TagKey)`.
  static bool isTag(int stateId, String tag) => host.Tags.blockState(stateId, tag);

  /// The default state of the block [key].
  static int? defaultOf(String key) => BlockRegistry.resolveState(key);

  /// The state of the block [key] with the properties of [properties] that it has.
  static int? withProperties(String key, Map<String, String> properties) => BlockRegistry.resolveState(key, properties);

  /// `BlockHelper.copyProperties(from, to)`: every property both states have is copied.
  static int copyProperties(int from, int to) {
    final f = info(from);
    if (f == null) return to;
    return setValues(to, f.properties);
  }

  /// `BlockHelper.copyProperty`.
  static int copyProperty(String property, int from, int to) {
    final v = value(from, property);
    if (v == null || !hasProperty(to, property)) return to;
    return setValue(to, property, v);
  }
}

/// `foundation.utility.BlockHelper` (the parts that make sense on the server).
abstract final class BlockHelper {
  static const _countStates = ['eggs', 'pickles', 'candles'];
  static const _vinelikeBlocks = ['minecraft:vine', 'minecraft:glow_lichen'];
  static const _vinelikeStates = ['up', 'north', 'east', 'south', 'west', 'down'];

  /// `setZeroAge`: resets growth properties (crops, honey level, hatch, stage, composter, piston).
  static int setZeroAge(int stateId) {
    final i = BlockStates.info(stateId);
    if (i == null) return stateId;
    final p = i.properties;
    for (final name in const ['age', 'level_honey', 'hatch', 'stage']) {
      // The `age` property exists with several ranges (age_1 .. age_25), all named `age`.
      if (p.containsKey(name)) return BlockStates.setValue(stateId, name, '0');
    }
    if (BlockStates.isTag(stateId, 'minecraft:cauldrons')) return BlockStates.defaultOf('minecraft:cauldron') ?? stateId;
    if (p.containsKey('composter_level')) return BlockStates.setValue(stateId, 'composter_level', '0');
    if (i.key == 'minecraft:composter') return BlockStates.setValue(stateId, 'level', '0');
    if (p.containsKey('extended')) return BlockStates.setValue(stateId, 'extended', 'false');
    return stateId;
  }

  /// `getRequiredItem`: the item key that places [stateId] (farmland and dirt paths need dirt).
  static String getRequiredItem(int stateId) {
    final key = BlockStates.blockKey(stateId) ?? 'minecraft:air';
    if (key == 'minecraft:farmland' || key == 'minecraft:dirt_path') return 'minecraft:dirt';
    return key;
  }

  /// `getBounceMultiplier`.
  static double getBounceMultiplier(String blockKey) {
    if (blockKey == 'minecraft:slime_block') return 0.8;
    if (blockKey.endsWith('_bed')) return 0.66 * 0.8;
    return 0;
  }

  /// `isNotUnheated` for heat sources: campfires must be lit; Create's `heat_level` must not be `none`.
  static bool isNotUnheated(int stateId) {
    final i = BlockStates.info(stateId);
    if (i == null) return true;
    if (BlockStates.isTag(stateId, 'minecraft:campfires') && i.properties.containsKey('lit')) {
      return i.properties['lit'] == 'true';
    }
    if (i.properties.containsKey('blaze')) return i.properties['blaze'] != 'none';
    return true;
  }

  /// `findAndRemoveInInventory(state, player, amount)`: takes the items needed to place [stateId]
  /// from the player (held item first), returns how many placements were paid.
  static Future<int> findAndRemoveInInventory(int stateId, host.Player player, int amount) async {
    final info = BlockStates.info(stateId);
    if (info == null) return 0;
    var amountFound = 0;
    final required = getRequiredItem(stateId);
    final needsTwo = info.properties['type'] == 'double' && info.key.endsWith('slab');
    if (needsTwo) amount *= 2;
    for (final prop in _countStates) {
      final v = info.properties[prop];
      if (v != null) amount *= int.tryParse(v) ?? 1;
    }
    if (_vinelikeBlocks.contains(info.key)) {
      var vineCount = 0;
      for (final s in _vinelikeStates) {
        if (info.properties[s] == 'true') vineCount++;
      }
      amount += vineCount - 1;
    }
    final inventory = player.getInventory();
    final storage = inventory.asInventory();
    Future<void> takeFrom(int slot) async {
      final stack = storage.getItem(slot: slot);
      if (stack == null) return;
      final key = await stack.getRegistryKey();
      final count = await stack.getCount();
      if (key == required && count > 0) {
        final taken = math.min(count, amount - amountFound);
        if (count - taken <= 0) {
          await storage.setItem(slot: slot, item: null);
        } else {
          await stack.setCount(count: count - taken);
          await storage.setItem(slot: slot, item: stack);
        }
        amountFound += taken;
      }
    }

    await takeFrom(inventory.getSelectedSlot());
    final size = storage.getSize();
    for (var i = 0; i < size; i++) {
      if (amountFound == amount) break;
      await takeFrom(i);
    }
    if (needsTwo) {
      if (amountFound.isOdd) {
        final back = host.ItemStack.create(registryKey: required, count: 1);
        await storage.give(back);
      }
      amountFound ~/= 2;
    }
    return amountFound;
  }

  /// `destroyBlock(level, pos, effectChance)`: breaks the block like a machine would, dropping its
  /// items as item entities at the block.
  static Future<void> destroyBlock(World world, Pos pos, double effectChance) =>
      destroyBlockWith(world, pos, effectChance, (stack) async {
        await world.dropItem(pos.center, stack);
      });

  /// `destroyBlock(level, pos, effectChance, droppedItemCallback)`.
  static Future<void> destroyBlockWith(
    World world,
    Pos pos,
    double effectChance,
    FutureOr<void> Function(host.ItemStack stack) droppedItemCallback,
  ) => destroyBlockAs(world, pos, null, null, effectChance, droppedItemCallback);

  /// `destroyBlockAs`: like a player with [usedTool] (may be `null`) would, but the drops go to
  /// [droppedItemCallback]. Drops follow the `block_drops` game rule and are skipped for creative
  /// [player]s; the host raises the break events and replaces the block with its fluid.
  static Future<void> destroyBlockAs(
    World world,
    Pos pos,
    host.Player? player,
    host.ItemStack? usedTool,
    double effectChance,
    FutureOr<void> Function(host.ItemStack stack) droppedItemCallback,
  ) async {
    final bp = pos.toBlockPos();
    final particles = math.Random().nextDouble() < effectChance;
    var drops = const <host.ItemStack>[];
    final dropsEnabled = world.getGameRuleBool(host.GameRule.blockDrops) ?? true;
    var creative = false;
    if (player != null) creative = player.isCreative;
    if (dropsEnabled && !creative) {
      drops = await world.getBlockDrops(pos: bp, tool: usedTool);
    }
    final broke = await world.breakBlock(bp, drop: false, breaker: player?.asEntity(), particles: particles);
    if (!broke) return;
    for (final stack in drops) {
      await droppedItemCallback(stack);
    }
  }

  /// `noCollisionInSpace` is not available server side without shapes; use the block registry.
  /// `extinguishFire`: removes fire in front of [pos] on side [dir].
  static Future<bool> extinguishFire(World world, Pos pos, Direction dir) async {
    final p = pos.relative(dir);
    final bp = p.toBlockPos();
    final b = world.getBlock(pos: bp);
    if (b.name == 'minecraft:fire') {
      await world.setBlockByName(pos: bp, name: 'minecraft:air', updateFlags: host.BlockUpdateFlags.normal);
      return true;
    }
    return false;
  }
}

/// `NBTHelper` on the host's [NbtCompound].
abstract final class NbtHelper {
  static void putMarker(NbtCompound nbt, String marker) => nbt.putCompound(marker, NbtCompound());

  /// `readBlockPos`: the position at [key] (an int array `[x, y, z]`, or the legacy `{X, Y, Z}`).
  static Pos readBlockPos(NbtCompound nbt, String key) {
    final arr = nbt.getIntArray(key);
    if (arr != null && arr.length >= 3) return (arr[0], arr[1], arr[2]);
    final old = nbt.getCompound(key);
    if (old != null) return (old.getInt('X') ?? 0, old.getInt('Y') ?? 0, old.getInt('Z') ?? 0);
    return posZero;
  }

  /// `BlockPos.CODEC`: a position is stored as an int array.
  static void writeBlockPos(NbtCompound nbt, String key, Pos p) => nbt.putIntArray(key, [p.$1, p.$2, p.$3]);

  static NbtCompound intToCompound(int i) => NbtCompound()..putInt('V', i);

  static int intFromCompound(NbtCompound c) => c.getInt('V') ?? 0;

  /// `writeCompoundList`: a list of compounds, skipping `null`s.
  static List<Object> writeCompoundList<T>(Iterable<T> list, NbtCompound? Function(T) serializer) => [
    for (final e in list)
      ?serializer(e),
  ];

  /// `readCompoundList`.
  static List<T> readCompoundList<T>(List<Object>? list, T Function(NbtCompound) deserializer) => [
    if (list != null)
      for (final c in list)
        if (c is NbtCompound) deserializer(c),
  ];

  /// `VecHelper.writeNBT`: a list of three doubles.
  static List<Object> writeVec(Vec3 v) => [host.NbtTagDouble(v.$1), host.NbtTagDouble(v.$2), host.NbtTagDouble(v.$3)];
}
