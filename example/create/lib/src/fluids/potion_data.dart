// The data of a `create:potion` fluid (pure): which potion, which bottle. It travels with the
// fluid as `FluidStack.data` (JSON bytes) and as the `minecraft:potion_contents` and
// `create:potion_fluid_bottle_type` components in the NBT Create's client reads.
import 'dart:convert';

import 'package:dart_mappable/dart_mappable.dart';

import '../core/nbt.dart';
import 'fluid_stack.dart';
import 'nbt_util.dart';

part 'potion_data.mapper.dart';

/// `PotionFluid.BottleType`.
@MappableEnum()
enum BottleType {
  regular,
  splash,
  lingering;

  /// `PotionFluidHandler.itemFromBottleType`.
  String get itemKey => switch (this) {
    BottleType.regular => 'minecraft:potion',
    BottleType.splash => 'minecraft:splash_potion',
    BottleType.lingering => 'minecraft:lingering_potion',
  };

  /// `PotionFluidHandler.bottleTypeFromItem`.
  static BottleType fromItem(String itemKey) => switch (itemKey) {
    'minecraft:lingering_potion' => BottleType.lingering,
    'minecraft:splash_potion' => BottleType.splash,
    _ => BottleType.regular,
  };

  static BottleType parse(String? name) => BottleType.values.firstWhere((b) => b.name == name, orElse: () => BottleType.regular);
}

/// A custom effect of a potion (`MobEffectInstance`).
@MappableClass()
class PotionEffectData with PotionEffectDataMappable {
  final String effect;
  final int duration;
  final int amplifier;
  final bool ambient;
  final bool visible;

  const PotionEffectData(this.effect, {this.duration = 0, this.amplifier = 0, this.ambient = false, this.visible = true});
}

/// The `PotionContents` of a potion fluid plus its bottle type.
@MappableClass()
class PotionFluidData with PotionFluidDataMappable {
  /// The potion (`minecraft:healing`); `minecraft:water` for a plain water bottle.
  final String potion;
  final BottleType bottle;
  final List<PotionEffectData> customEffects;

  const PotionFluidData(this.potion, {this.bottle = BottleType.regular, this.customEffects = const []});

  /// `Potions.WATER` with no custom effects in a regular bottle: this is plain water.
  bool get isWater => potion == 'minecraft:water' && customEffects.isEmpty && bottle == BottleType.regular;

  /// The data bytes of a [FStack].
  List<int> encode() => utf8.encode(jsonEncode(toMap()));

  /// The data of a stack, `null` for stacks without (or with other) data.
  static PotionFluidData? decode(List<int>? data) {
    if (data == null || data.isEmpty) return null;
    try {
      return PotionFluidDataMapper.fromMap(jsonDecode(utf8.decode(data)) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  /// `PotionFluid.of(amount, contents, bottleType)`.
  FStack toStack(int amount) => FStack(FluidKeys.potion, amount, encode());

  /// The component map Create's client reads from a fluid stack.
  Map<String, NbtValue> toComponents() {
    final contents = <String, NbtValue>{'potion': NbtValue.string(potion)};
    if (customEffects.isNotEmpty) {
      contents['custom_effects'] = NbtValue.list([
        for (final e in customEffects)
          NbtValue.compound({
            'id': NbtValue.string(e.effect),
            'amplifier': NbtValue.byte(e.amplifier),
            'duration': NbtValue.int32(e.duration),
            'ambient': NbtValue.byte(e.ambient ? 1 : 0),
            'show_particles': NbtValue.byte(e.visible ? 1 : 0),
          }),
      ]);
    }
    return {
      'minecraft:potion_contents': NbtValue.compound(contents),
      'create:potion_fluid_bottle_type': NbtValue.string(bottle.name),
    };
  }

  static PotionFluidData? fromComponents(Map<String, NbtValue> components) {
    final contents = components.readCompound('minecraft:potion_contents');
    final bottle = BottleType.parse(components.readString('create:potion_fluid_bottle_type'));
    if (contents == null) return null;
    final effects = <PotionEffectData>[];
    for (final e in contents.readList('custom_effects') ?? const <NbtValue>[]) {
      if (e.kind != NbtKind.compound) continue;
      final c = e.asCompound;
      final id = c.readString('id');
      if (id == null) continue;
      effects.add(PotionEffectData(
        id,
        duration: c.readInt('duration') ?? 0,
        amplifier: c.readInt('amplifier') ?? 0,
        ambient: c.readBool('ambient'),
        visible: c.readBool('show_particles', or: true),
      ));
    }
    return PotionFluidData(contents.readString('potion') ?? 'minecraft:water', bottle: bottle, customEffects: effects);
  }
}

/// `PotionFluidHandler` (the fluid side).
abstract final class PotionFluids {
  /// `getFluidFromPotion`: plain water for a regular water bottle, a potion fluid otherwise.
  static FStack fluidFromPotion(PotionFluidData data, int amount) =>
      data.isWater ? FStack(FluidKeys.water, amount) : data.toStack(amount);

  /// The potion data of a fluid stack: a potion fluid's own, water as a water bottle, `null` for
  /// other fluids.
  static PotionFluidData? dataOf(FStack stack) {
    if (stack.isEmpty) return null;
    if (stack.fluid == FluidKeys.water) return const PotionFluidData('minecraft:water');
    if (stack.fluid != FluidKeys.potion) return null;
    return PotionFluidData.decode(stack.data) ?? const PotionFluidData('minecraft:water');
  }

  /// `getRequiredAmountForFilledBottle`.
  static int requiredAmountForFilledBottle() => 250;

  /// `fillBottle`: the item key of the bottle a potion fluid fills.
  static String bottleItemFor(FStack fluid) => (dataOf(fluid)?.bottle ?? BottleType.regular).itemKey;
}
