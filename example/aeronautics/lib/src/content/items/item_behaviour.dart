// The item-entity behaviour of the mod's two components.
//
// Java: `mixin/levitite/ItemEntityMixin` and `mixin/item_converter/ItemEntityMixin`.
//
// Two behaviours ride on a dropped item:
//
// * `aeronautics:levitating`: the item does not fall (its default gravity is 0)
//   and its motion is damped by `drag_fraction` every tick, with a sparkle trail.
// * `aeronautics:converter`: a counter runs down and the stack becomes another
//   item; and a stack tagged `aeronautics:converts_to_cloud_skipper` dropped in
//   the overworld between y 192 and 196 gains the converter (plus levitation), so
//   a thrown item turns into the music disc in the cloud layer.
//
// Host: this file uses `pumpkin_api`.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:create/src/core/module.dart' show CreateContext;
import 'package:create/src/core/nbt.dart' show NbtKind, NbtValue, NetworkNbt;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../components/converter.dart';
import '../components/levitating.dart';

/// The entity type key of a dropped item.
const String itemEntityType = 'minecraft:item';

/// `AeroTags.ItemTags.CONVERTS_TO_CLOUD_SKIPPER`.
const String convertsToCloudSkipperTag = 'aeronautics:converts_to_cloud_skipper';

/// The overworld dimension id (`level.dimension().equals(Level.OVERWORLD)`).
const String overworldDimension = 'minecraft:overworld';

/// The y range the cloud-skipper conversion needs (both ends inclusive).
const double cloudSkipperMinY = 192;
const double cloudSkipperMaxY = 196;

/// The levitation of an item key, for stacks whose component the host cannot
/// carry as a *default* component.
///
/// TODO(parity): `AeroBlocks.java:405,420` and `AeroItems.java:41,50` give the
/// two levitite items, the music disc and the powder their `aeronautics:levitating`
/// default component. `item-registry.register-item` only accepts the vanilla
/// component set, so those defaults are read from the item key here.
Levitating? levitatingForItemKey(String itemKey) => switch (itemKey) {
  'aeronautics:levitite' => Levitating.levitite,
  'aeronautics:pearlescent_levitite' => Levitating.pearlescentLevitite,
  'aeronautics:music_disc_cloud_skipper' => Levitating.defaultLevitating,
  'aeronautics:end_stone_powder' => Levitating.endStone,
  _ => null,
};

/// The two item-entity behaviours, installed by the module.
final class ItemBehaviour {
  /// The entities that already converted this tick, so a stack does not convert
  /// twice from its old key in the same tick.
  final Set<int> _converted = {};

  /// Subscribes to the entity tick.
  void install(CreateContext ctx) {
    ctx.listen(Events.entityTick, _onTick);
    ctx.listen(Events.entityRemove, (server, e) => _converted.remove(e.entityId));
  }

  Future<void> _onTick(Server server, EntityTickEventData e) async {
    if (e.entityType != itemEntityType) return;
    if (_converted.contains(e.entityId)) return;

    final entity = _itemOf(server, e.entityId);
    if (entity == null) return;

    final stack = entity.getStack();
    final itemKey = await stack.getRegistryKey();
    if (itemKey.isEmpty) return;

    await _tickConverter(server, entity, stack, itemKey);
    await _tickLevitating(entity, stack, itemKey);
  }

  /// `ItemEntityMixin` of `item_converter`: the counter, and the cloud-layer
  /// conversion that starts it.
  Future<void> _tickConverter(Server server, ItemEntity entity, ItemStack stack, String itemKey) async {
    final stored = stack.customComponent('aeronautics:converter');
    if (stored != null) {
      final converter = Converter.fromJson(_readNbt(stored));
      final outcome = converter.tick();
      if (outcome.isConverting) {
        await _applyConversion(server, entity, stack, outcome.converted!);
      } else if (outcome.isCounting) {
        stack.setCustomComponent('aeronautics:converter', _writeNbt(outcome.next!.toJson()));
      }
      return;
    }

    final body = entity.asEntity();
    final world = body.getWorld();
    // `level.dimension().equals(Level.OVERWORLD)`. Not `world.getName()`: the host's
    // `get_name` is `get_world_name()` (the folder name, `world`), so the comparison against a
    // dimension key would never match and the conversion would never start.
    if (world.getDimension() != overworldDimension) return;
    if (!Tags.item(itemKey, convertsToCloudSkipperTag)) return;

    final pos = body.getPosition();
    if (pos.$2 < cloudSkipperMinY || pos.$2 > cloudSkipperMaxY) return;

    // `DataComponentPatch.builder().set(CONVERTER, cloudSkipper()).set(LEVITATING,
    // Levitating.DEFAULT).build()`.
    stack.setCustomComponent('aeronautics:converter', _writeNbt(Converter.cloudSkipper.toJson()));
    stack.setCustomComponent('aeronautics:levitating', _writeNbt(Levitating.defaultLevitating.toJson()));
    final velocity = body.getVelocity();
    body.setVelocity(velocity: (velocity.$1 * 0.5, velocity.$2 * 0.5, velocity.$3 * 0.5));
  }

  /// `Converter.tick`: replace the stack, keeping the count, then play the sound
  /// and the particle burst.
  Future<void> _applyConversion(Server server, ItemEntity entity, ItemStack stack, Converter converter) async {
    final target = converter.item;
    if (target == null) return;
    final count = await stack.getCount();

    final replacement = await ItemBuilder(target, count: count).build();
    await entity.setStack(stack: replacement);
    _converted.add(entity.asEntity().getId());

    final body = entity.asEntity();
    final world = body.getWorld();
    final pos = body.getPosition();
    if (converter.sound != null) {
      world.playCustomSound(
        soundName: converter.sound!,
        category: SoundCategory.ambient,
        pos: pos,
        volume: 5,
        pitch: 1,
      );
    }
    if (converter.particle != null) {
      // `serverLevel.sendParticles(particle, x, y + bbHeight + bbHeight / 2, z,
      // 20, 0, 0, 0, 0.05)`.
      world.spawnPluginParticle(
        key: converter.particle!,
        pos: (pos.$1, pos.$2 + 1.5, pos.$3),
        delta: (0, 0, 0),
        speed: 0.05,
        count: 20,
        options: const [],
      );
    }
  }

  /// `ItemEntityMixin` of `levitite`: no fall, damped motion.
  ///
  /// TODO(parity): Java cancels `getDefaultGravity` (the item keeps its motion
  /// and never accelerates down) and then scales the motion by `drag_fraction`.
  /// The host has no gravity override for entities, so the vertical velocity is
  /// zeroed here instead: the same "does not fall" result, minus the case where
  /// something else gives the item downward speed in the same tick.
  Future<void> _tickLevitating(ItemEntity entity, ItemStack stack, String itemKey) async {
    final stored = stack.customComponent('aeronautics:levitating');
    final levitating = stored != null ? Levitating.fromJson(_readNbt(stored)) : levitatingForItemKey(itemKey);
    if (levitating == null) return;

    final drag = levitating.dragFraction.clamp(0.0, 1.0);
    final body = entity.asEntity();
    final velocity = body.getVelocity();
    body.setVelocity(velocity: (velocity.$1 * drag, 0, velocity.$3 * drag));
  }

  /// The live item entity with [id], or `null` when it is gone or is not one.
  ItemEntity? _itemOf(Server server, int id) {
    for (final world in server.getAllWorlds()) {
      final entity = world.getEntityById(id: id);
      if (entity == null) continue;
      final item = entity.asItem();
      if (item != null) return item;
    }
    return null;
  }

  /// The network NBT of a custom component value, as the json the codecs read.
  Map<String, Object?> _readNbt(List<int> bytes) => _nbtToJson(NetworkNbt.decode(bytes));

  List<int> _writeNbt(Map<String, Object?> json) => NetworkNbt.encode(_jsonToNbt(json));

  static Map<String, Object?> _nbtToJson(NbtValue? value) {
    final compound = value?.asCompound;
    if (compound == null) return const {};
    return {for (final e in compound.entries) e.key: _valueToDart(e.value)};
  }

  static Object? _valueToDart(NbtValue value) {
    switch (value.kind) {
      case NbtKind.compound:
        return _nbtToJson(value);
      case NbtKind.list:
        return [for (final v in value.value as List<NbtValue>) _valueToDart(v)];
      case NbtKind.string:
        return value.value as String;
      default:
        return value.value;
    }
  }

  static NbtValue _jsonToNbt(Object? value) {
    if (value is Map) {
      return NbtValue.compound({for (final e in value.entries) '${e.key}': _jsonToNbt(e.value)});
    }
    if (value is List) return NbtValue.list([for (final v in value) _jsonToNbt(v)]);
    if (value is String) return NbtValue.string(value);
    if (value is bool) return NbtValue.byte(value ? 1 : 0);
    if (value is int) return NbtValue.int32(value);
    if (value is double) return NbtValue.double64(value);
    return NbtValue.string('$value');
  }
}
