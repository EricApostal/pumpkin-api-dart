// The data of a `create:potion` fluid (pure): which potion, which bottle. It travels with the
// fluid as `FluidStack.data` (JSON bytes) and as the `minecraft:potion_contents` and
// `create:potion_fluid_bottle_type` components in the NBT Create's client reads.
import 'dart:convert';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show PacketReader, PacketWriter, VanillaIds;

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

/// The `minecraft:potion_contents` component of a bottle item (`PotionContents.STREAM_CODEC`).
///
/// The bytes are the component's network encoding, which is what the host's data component API
/// reads and writes (`item-stack.get-components` / `set-component`), so the potion of a bottle
/// survives the trip through a drain, a spout or a basin instead of being thrown away.
///
/// The port's [PotionFluidData] models the potion and its custom effects, like the component
/// JSON of the fluid the module writes; a custom colour or name of the contents is read past and
/// dropped (it is dropped everywhere in this module, see [PotionFluidData]). The effect ids are
/// registry ids, which [VanillaIds] resolves (the list is generated from Pumpkin's assets, the
/// same ids `PotionContentsImpl` carries on the wire).
abstract final class PotionContentsComponent {
  static const String key = 'minecraft:potion_contents';

  /// The contents of a bottle of the [bottle] type whose component bytes are [bytes].
  ///
  /// A bottle without the component holds vanilla's default, `new PotionContents(Potions.WATER)`
  /// (`Items.POTION`, `SPLASH_POTION` and `LINGERING_POTION` all default to it), and a component
  /// that cannot be read must not be guessed at, so both read as water: the fluid is then plain
  /// water for a regular bottle and a water potion fluid for the other two, which is exactly what
  /// `PotionFluidHandler.getFluidFromPotionItem` returns for those (`PotionFluidHandler.java:63-71`).
  static PotionFluidData read(List<int>? bytes, {required BottleType bottle}) =>
      (bytes == null || bytes.isEmpty ? null : _decode(bytes, bottle)) ??
      PotionFluidData('minecraft:water', bottle: bottle);

  /// The network bytes of [data]'s contents: the potion id, no custom colour, the custom
  /// effects, no custom name (`PotionContents.STREAM_CODEC`).
  ///
  /// Throws an [ArgumentError] for a potion or effect this registry does not know: the host's
  /// potion registry holds the vanilla entries only, so a name outside [VanillaIds] cannot be
  /// written as an id and must not be mislabelled as another potion.
  static List<int> encode(PotionFluidData data) {
    final w = PacketWriter();
    final potion = VanillaIds.potions.idOf(data.potion);
    if (potion == null) {
      throw ArgumentError.value(data.potion, 'potion', 'is not a vanilla potion');
    }
    w.writeBool(true);
    w.writeVarInt(potion);
    w.writeBool(false); // no custom colour
    w.writeVarInt(data.customEffects.length);
    for (final e in data.customEffects) {
      final effect = VanillaIds.mobEffects.idOf(e.effect);
      if (effect == null) {
        throw ArgumentError.value(e.effect, 'effect', 'is not a vanilla mob effect');
      }
      w.writeVarInt(effect);
      w.writeVarInt(e.amplifier);
      w.writeVarInt(e.duration);
      w.writeBool(e.ambient);
      w.writeBool(e.visible);
      w.writeBool(true); // show icon: the port's effect model has no flag for it
      w.writeBool(false); // no hidden effect
    }
    w.writeBool(false); // no custom name
    return w.toBytes();
  }

  /// The components of a bottle filled from a potion fluid (or nothing when [data] is `null`).
  ///
  /// `PotionFluidHandler.fillBottle` sets `POTION_CONTENTS` from the fluid's own contents; a
  /// potion or effect this registry does not know cannot be turned into an id the host accepts,
  /// so the bottle keeps no component rather than a wrong one.
  static List<(String, List<int>)> componentsOf(PotionFluidData? data) {
    if (data == null) return const [];
    try {
      return [(key, encode(data))];
    } on ArgumentError {
      return const [];
    }
  }

  static PotionFluidData? _decode(List<int> bytes, BottleType bottle) {
    try {
      final r = PacketReader(bytes);
      final potion = r.readBool() ? VanillaIds.potions.keyOf(r.readVarInt()) : null;
      if (r.readBool()) r.readInt(); // custom colour
      final effects = <PotionEffectData>[];
      for (var i = 0, count = r.readVarInt(); i < count; i++) {
        final effect = VanillaIds.mobEffects.keyOf(r.readVarInt());
        if (effect == null) return null;
        final amplifier = r.readVarInt();
        final duration = r.readVarInt();
        final ambient = r.readBool();
        final visible = r.readBool();
        r.readBool(); // show icon
        if (r.readBool()) _skipHiddenEffect(r);
        effects.add(
          PotionEffectData(
            effect,
            duration: duration,
            amplifier: amplifier,
            ambient: ambient,
            visible: visible,
          ),
        );
      }
      if (r.readBool()) r.readString(); // custom name
      // A contents without a potion id is nothing the client sends; the model needs a potion
      // name, and water is the default of every bottle item.
      return PotionFluidData(
        potion ?? 'minecraft:water',
        bottle: bottle,
        customEffects: effects,
      );
    } on Object {
      return null;
    }
  }

  /// The nested `MobEffectInstance` of a hidden effect: the host's reader
  /// (`pumpkin-protocol/src/codec/data_component.rs`) skips the same parameters, without an
  /// effect id, until the nested instance has no hidden effect of its own.
  static void _skipHiddenEffect(PacketReader r) {
    for (var depth = 0; ; depth++) {
      if (depth > 32) throw const FormatException('potion effect hidden effect too deep');
      r.readVarInt(); // amplifier
      r.readVarInt(); // duration
      r.readBool(); // ambient
      r.readBool(); // show particles
      r.readBool(); // show icon
      if (!r.readBool()) return;
    }
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
