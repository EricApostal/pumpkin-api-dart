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

  static BottleType parse(String? name) => BottleType.values.firstWhere(
    (b) => b.name == name,
    orElse: () => BottleType.regular,
  );
}

/// A custom effect of a potion (`MobEffectInstance`).
@MappableClass()
class PotionEffectData with PotionEffectDataMappable {
  final String effect;
  final int duration;
  final int amplifier;
  final bool ambient;
  final bool visible;

  const PotionEffectData(
    this.effect, {
    this.duration = 0,
    this.amplifier = 0,
    this.ambient = false,
    this.visible = true,
  });
}

/// The `PotionContents` of a potion fluid plus its bottle type.
@MappableClass()
class PotionFluidData with PotionFluidDataMappable {
  /// The potion (`minecraft:healing`); `minecraft:water` for a plain water bottle.
  final String potion;
  final BottleType bottle;
  final List<PotionEffectData> customEffects;

  const PotionFluidData(
    this.potion, {
    this.bottle = BottleType.regular,
    this.customEffects = const [],
  });

  /// `Potions.WATER` with no custom effects in a regular bottle: this is plain water.
  bool get isWater =>
      potion == 'minecraft:water' &&
      customEffects.isEmpty &&
      bottle == BottleType.regular;

  /// The data bytes of a [FStack].
  List<int> encode() => utf8.encode(jsonEncode(toMap()));

  /// The data of a stack, `null` for stacks without (or with other) data.
  static PotionFluidData? decode(List<int>? data) {
    if (data == null || data.isEmpty) return null;
    try {
      return PotionFluidDataMapper.fromMap(
        jsonDecode(utf8.decode(data)) as Map<String, dynamic>,
      );
    } on Object {
      return null;
    }
  }

  /// `PotionFluid.of(amount, contents, bottleType)`.
  FStack toStack(int amount) => FStack(FluidKeys.potion, amount, encode());

  /// The components of the fluid as the processing module's `PFluid.comps` pairs, the form a
  /// recipe's `neoforge:components` fluid ingredient is compared against
  /// (`FluidIngredient.testFluid`).
  ///
  /// The host's `FluidStack` has no component codec (it carries only plugin `data`), so the
  /// value of every entry is the UTF-8 JSON of the component's codec form — the form
  /// Create's own recipes write.
  List<(String, List<int>)> componentEntries() => [
    ('minecraft:potion_contents', utf8.encode(jsonEncode(contentsJson))),
    (
      'create:potion_fluid_bottle_type',
      utf8.encode(jsonEncode(bottle.name)),
    ),
  ];

  /// `PotionContents.CODEC` form: `{potion, custom_effects?}`.
  Map<String, Object?> get contentsJson => {
    'potion': potion,
    if (customEffects.isNotEmpty)
      'custom_effects': [
        for (final e in customEffects)
          {
            'id': e.effect,
            'duration': e.duration,
            'amplifier': e.amplifier,
            'ambient': e.ambient,
            'show_particles': e.visible,
          },
      ],
  };

  /// The data of the potion fluid of [comps] (`componentEntries`), `null` when they are not a
  /// potion's components.
  static PotionFluidData? fromComponentEntries(
    List<(String, List<int>)> comps,
  ) {
    Map<String, Object?>? contents;
    String? bottle;
    for (final (name, bytes) in comps) {
      try {
        final value = jsonDecode(utf8.decode(bytes));
        if (name == 'minecraft:potion_contents' && value is Map) {
          contents = value.cast<String, Object?>();
        } else if (name == 'create:potion_fluid_bottle_type' &&
            value is String) {
          bottle = value;
        }
      } on Object {
        // a component the plugin did not write as JSON
      }
    }
    final potion = contents?['potion'];
    if (potion is! String) return null;
    return PotionFluidData(
      potion,
      bottle: BottleType.parse(bottle),
      customEffects: _effectsOf(contents!['custom_effects']),
    );
  }

  static List<PotionEffectData> _effectsOf(Object? raw) {
    if (raw is! List) return const [];
    final effects = <PotionEffectData>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final id = e['id'];
      if (id is! String) continue;
      effects.add(
        PotionEffectData(
          id,
          duration: (e['duration'] as num?)?.toInt() ?? 0,
          amplifier: (e['amplifier'] as num?)?.toInt() ?? 0,
          ambient: e['ambient'] == true,
          visible: e['show_particles'] != false,
        ),
      );
    }
    return effects;
  }

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
    final bottle = BottleType.parse(
      components.readString('create:potion_fluid_bottle_type'),
    );
    if (contents == null) return null;
    final effects = <PotionEffectData>[];
    for (final e in contents.readList('custom_effects') ?? const <NbtValue>[]) {
      if (e.kind != NbtKind.compound) continue;
      final c = e.asCompound;
      final id = c.readString('id');
      if (id == null) continue;
      effects.add(
        PotionEffectData(
          id,
          duration: c.readInt('duration') ?? 0,
          amplifier: c.readInt('amplifier') ?? 0,
          ambient: c.readBool('ambient'),
          visible: c.readBool('show_particles', or: true),
        ),
      );
    }
    return PotionFluidData(
      contents.readString('potion') ?? 'minecraft:water',
      bottle: bottle,
      customEffects: effects,
    );
  }
}

/// The effects a potion fluid applies: the effects of the vanilla potion it names
/// (`PotionContents.getAllEffects`) plus its custom effects. The host exposes no potion
/// registry, so the vanilla effects are the fixed table of the base game.
abstract final class PotionEffects {
  /// The effects of [data], in the order the potion applies them.
  static List<PotionEffectData> of(PotionFluidData data) {
    if (data.isWater) return const [];
    return [...?_vanilla[data.potion], ...data.customEffects];
  }

  static const Map<String, List<PotionEffectData>> _vanilla = {
    'minecraft:night_vision': [
      PotionEffectData('minecraft:night_vision', duration: 3600),
    ],
    'minecraft:long_night_vision': [
      PotionEffectData('minecraft:night_vision', duration: 9600),
    ],
    'minecraft:invisibility': [
      PotionEffectData('minecraft:invisibility', duration: 3600),
    ],
    'minecraft:long_invisibility': [
      PotionEffectData('minecraft:invisibility', duration: 9600),
    ],
    'minecraft:leaping': [
      PotionEffectData('minecraft:jump_boost', duration: 3600),
    ],
    'minecraft:long_leaping': [
      PotionEffectData('minecraft:jump_boost', duration: 9600),
    ],
    'minecraft:strong_leaping': [
      PotionEffectData('minecraft:jump_boost', duration: 1800, amplifier: 1),
    ],
    'minecraft:fire_resistance': [
      PotionEffectData('minecraft:fire_resistance', duration: 3600),
    ],
    'minecraft:long_fire_resistance': [
      PotionEffectData('minecraft:fire_resistance', duration: 9600),
    ],
    'minecraft:swiftness': [
      PotionEffectData('minecraft:speed', duration: 3600),
    ],
    'minecraft:long_swiftness': [
      PotionEffectData('minecraft:speed', duration: 9600),
    ],
    'minecraft:strong_swiftness': [
      PotionEffectData('minecraft:speed', duration: 1800, amplifier: 1),
    ],
    'minecraft:slowness': [
      PotionEffectData('minecraft:slowness', duration: 1800),
    ],
    'minecraft:long_slowness': [
      PotionEffectData('minecraft:slowness', duration: 4800),
    ],
    'minecraft:strong_slowness': [
      PotionEffectData('minecraft:slowness', duration: 400, amplifier: 3),
    ],
    'minecraft:water_breathing': [
      PotionEffectData('minecraft:water_breathing', duration: 3600),
    ],
    'minecraft:long_water_breathing': [
      PotionEffectData('minecraft:water_breathing', duration: 9600),
    ],
    'minecraft:healing': [
      PotionEffectData('minecraft:instant_health', duration: 1),
    ],
    'minecraft:strong_healing': [
      PotionEffectData('minecraft:instant_health', duration: 1, amplifier: 1),
    ],
    'minecraft:harming': [
      PotionEffectData('minecraft:instant_damage', duration: 1),
    ],
    'minecraft:strong_harming': [
      PotionEffectData('minecraft:instant_damage', duration: 1, amplifier: 1),
    ],
    'minecraft:poison': [PotionEffectData('minecraft:poison', duration: 900)],
    'minecraft:long_poison': [
      PotionEffectData('minecraft:poison', duration: 1800),
    ],
    'minecraft:strong_poison': [
      PotionEffectData('minecraft:poison', duration: 432, amplifier: 1),
    ],
    'minecraft:regeneration': [
      PotionEffectData('minecraft:regeneration', duration: 900),
    ],
    'minecraft:long_regeneration': [
      PotionEffectData('minecraft:regeneration', duration: 1800),
    ],
    'minecraft:strong_regeneration': [
      PotionEffectData('minecraft:regeneration', duration: 450, amplifier: 1),
    ],
    'minecraft:strength': [
      PotionEffectData('minecraft:strength', duration: 3600),
    ],
    'minecraft:long_strength': [
      PotionEffectData('minecraft:strength', duration: 9600),
    ],
    'minecraft:strong_strength': [
      PotionEffectData('minecraft:strength', duration: 1800, amplifier: 1),
    ],
    'minecraft:weakness': [
      PotionEffectData('minecraft:weakness', duration: 1800),
    ],
    'minecraft:long_weakness': [
      PotionEffectData('minecraft:weakness', duration: 4800),
    ],
    'minecraft:luck': [PotionEffectData('minecraft:luck', duration: 6000)],
    'minecraft:slow_falling': [
      PotionEffectData('minecraft:slow_falling', duration: 1800),
    ],
    'minecraft:long_slow_falling': [
      PotionEffectData('minecraft:slow_falling', duration: 4800),
    ],
    'minecraft:turtle_master': [
      PotionEffectData('minecraft:resistance', duration: 400, amplifier: 2),
      PotionEffectData('minecraft:slowness', duration: 400, amplifier: 3),
    ],
    'minecraft:long_turtle_master': [
      PotionEffectData('minecraft:resistance', duration: 800, amplifier: 2),
      PotionEffectData('minecraft:slowness', duration: 800, amplifier: 3),
    ],
    'minecraft:strong_turtle_master': [
      PotionEffectData('minecraft:resistance', duration: 400, amplifier: 3),
      PotionEffectData('minecraft:slowness', duration: 400, amplifier: 5),
    ],
    'minecraft:wind_charged': [
      PotionEffectData('minecraft:wind_charged', duration: 3600),
    ],
    'minecraft:weaving': [
      PotionEffectData('minecraft:weaving', duration: 3600),
    ],
    'minecraft:oozing': [PotionEffectData('minecraft:oozing', duration: 3600)],
    'minecraft:infested': [
      PotionEffectData('minecraft:infested', duration: 3600),
    ],
  };
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
    if (stack.fluid == FluidKeys.water)
      return const PotionFluidData('minecraft:water');
    if (stack.fluid != FluidKeys.potion) return null;
    return PotionFluidData.decode(stack.data) ??
        const PotionFluidData('minecraft:water');
  }

  /// `getRequiredAmountForFilledBottle`.
  static int requiredAmountForFilledBottle() => 250;

  /// `fillBottle`: the item key of the bottle a potion fluid fills.
  static String bottleItemFor(FStack fluid) =>
      (dataOf(fluid)?.bottle ?? BottleType.regular).itemKey;
}
