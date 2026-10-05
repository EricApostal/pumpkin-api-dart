// Encodes data components given as vanilla-format JSON (the format of the
// data generator and of item JSON: `{"minecraft:tool": {"rules": [...]}}`)
// into the network bytes Pumpkin's host accepts for
// `data-component-value.value` in `item-registry.register-item` and
// `item-stack.set-component`.
//
// The host decodes these bytes with `pumpkin_protocol::codec::data_component::
// deserialize`, one `DataComponentCodec::deserialize` per component
// (crates/pumpkin-protocol/src/codec/data_component.rs). Every encoder below
// is the inverse of that reader, and its field order is vanilla's network
// StreamCodec for 26.x, which the reader mirrors. Notes per component say
// where the reader reads but then discards a field (so the host never sees
// it) and where it differs from vanilla.
//
// Free of host imports, so it is unit-tested on the Dart VM.
import 'dart:typed_data';

import 'packet_buffer.dart';
import 'registry_ids.dart';

/// Thrown when a component cannot be encoded: it is malformed, refers to a
/// registry entry that does not exist, or has no encoder.
final class ComponentEncodeException implements Exception {
  /// The component, `minecraft:tool`.
  final String component;
  final String message;

  const ComponentEncodeException(this.component, this.message);

  @override
  String toString() => 'ComponentEncodeException($component): $message';
}

/// One encoded component: its name (`minecraft:tool`) and the bytes for
/// `data-component-value.value`.
final class EncodedComponent {
  final String name;
  final Uint8List bytes;

  const EncodedComponent(this.name, this.bytes);

  /// The name of the case in the WIT `data-component` enum (kebab-case),
  /// `max-stack-size` for `minecraft:max_stack_size`. Resolve it with the
  /// generated `DataComponent.fromWireName`.
  String get wireName => DataComponentCodec.wireNameOf(name);

  @override
  String toString() => 'EncodedComponent($name, ${bytes.length} bytes)';
}

/// A component that was left out, and why.
final class SkippedComponent {
  final String name;
  final String reason;

  const SkippedComponent(this.name, this.reason);

  @override
  String toString() => '$name: $reason';
}

/// The result of [DataComponentCodec.encodeAll].
final class EncodedComponents {
  final List<EncodedComponent> encoded;
  final List<SkippedComponent> skipped;

  const EncodedComponents(this.encoded, this.skipped);

  /// The encoded bytes by component name.
  Map<String, Uint8List> get byName => {
    for (final c in encoded) c.name: c.bytes,
  };
}

/// Where the codec finds the numeric ids of registry entries. Every lookup
/// returns `null` for an unknown key; the codec then throws. The default is
/// [VanillaIds] (generated from Pumpkin's assets); replace [item] to resolve
/// custom items through the host (`get-item-id`).
final class ComponentRegistries {
  final int? Function(String key) item;
  final int? Function(String key) block;
  final int? Function(String key) sound;
  final int? Function(String key) attribute;
  final int? Function(String key) damageType;
  final int? Function(String key) mobEffect;
  final int? Function(String key) entityType;
  final int? Function(String key) enchantment;
  final int? Function(String key) dataComponentType;

  const ComponentRegistries({
    required this.item,
    required this.block,
    required this.sound,
    required this.attribute,
    required this.damageType,
    required this.mobEffect,
    required this.entityType,
    required this.enchantment,
    required this.dataComponentType,
  });

  /// The vanilla registries; [item] may be overridden to know custom items.
  factory ComponentRegistries.vanilla({int? Function(String key)? item}) =>
      ComponentRegistries(
        item: item ?? VanillaIds.items.idOf,
        block: VanillaIds.blocks.idOf,
        sound: VanillaIds.sounds.idOf,
        attribute: VanillaIds.attributes.idOf,
        damageType: VanillaIds.damageTypes.idOf,
        mobEffect: VanillaIds.mobEffects.idOf,
        entityType: VanillaIds.entityTypes.idOf,
        enchantment: VanillaIds.enchantments.idOf,
        dataComponentType: VanillaIds.dataComponentTypes.idOf,
      );
}

typedef _Json = Map<String, Object?>;

/// JSON -> network bytes for data components.
abstract final class DataComponentCodec {
  /// Components of Minecraft 26.3 that Pumpkin has a name for but **no network
  /// reader**: `register-item` fails with "Unimplemented data component" for
  /// them (and `set-component` ignores them), so they are never encoded.
  /// `interact_animation` and `block_transformer` are the ones that matter for
  /// tools: Pumpkin matches axes, hoes and shovels through static item tags.
  ///
  /// Taken from the `deserialize` match in `data_component.rs`; extend it when
  /// the host gains a reader.
  static const Map<String, String> notReadByHost = {
    'minecraft:interact_animation': 'the host has no reader for it',
    'minecraft:block_transformer':
        'the host has no reader for it (axes, hoes and shovels are matched '
            'through the static item tags instead)',
    'minecraft:villager_food': 'the host has no reader for it',
    'minecraft:compostable': 'the host has no reader for it',
    'minecraft:cooking_fuel': 'the host has no reader for it',
    'minecraft:brewing_fuel': 'the host has no reader for it',
    'minecraft:mob_visibility': 'the host has no reader for it',
    'minecraft:provides_pottery_pattern': 'the host has no reader for it',
    'minecraft:sign_text_front': 'the host has no reader for it',
    'minecraft:sign_text_back': 'the host has no reader for it',
    'minecraft:waxed': 'the host has no reader for it',
    'minecraft:cushion/color': 'the host has no reader for it',
  };

  /// The components [encode] supports.
  static Set<String> get supported => _encoders.keys.toSet();

  /// The WIT `data-component` case for a component name:
  /// `minecraft:max_stack_size` is `max-stack-size`,
  /// `minecraft:cushion/color` is `cushion-color`.
  static String wireNameOf(String name) {
    final bare = name.startsWith('minecraft:')
        ? name.substring('minecraft:'.length)
        : name;
    return bare.replaceAll('_', '-').replaceAll('/', '-');
  }

  /// Encodes the component [name] (`minecraft:tool`) with the vanilla JSON
  /// [value]. Throws a [ComponentEncodeException] if it is invalid or
  /// unsupported.
  static Uint8List encode(
    String name,
    Object? value, {
    ComponentRegistries? registries,
  }) {
    final encoder = _encoders[name];
    if (encoder == null) {
      throw ComponentEncodeException(
        name,
        notReadByHost.containsKey(name)
            ? 'the host cannot read it (${notReadByHost[name]})'
            : 'no encoder for it',
      );
    }
    final writer = PacketWriter();
    try {
      encoder(_Ctx(name, registries ?? ComponentRegistries.vanilla()), value, writer);
    } on ComponentEncodeException {
      rethrow;
    } on ArgumentError catch (e) {
      // Includes RangeError (a number that does not fit the wire type).
      throw ComponentEncodeException(name, '${e.message}');
    } on PacketException catch (e) {
      throw ComponentEncodeException(name, e.message);
    }
    return writer.toBytes();
  }

  /// Encodes a whole component map. Components the host cannot read are
  /// returned in [EncodedComponents.skipped] (the reason says why); every
  /// other component must encode, or a [ComponentEncodeException] is thrown.
  static EncodedComponents encodeAll(
    Map<String, Object?> components, {
    ComponentRegistries? registries,
  }) {
    final regs = registries ?? ComponentRegistries.vanilla();
    final encoded = <EncodedComponent>[];
    final skipped = <SkippedComponent>[];
    for (final entry in components.entries) {
      final reason = notReadByHost[entry.key];
      if (reason != null) {
        skipped.add(SkippedComponent(entry.key, reason));
        continue;
      }
      encoded.add(
        EncodedComponent(
          entry.key,
          encode(entry.key, entry.value, registries: regs),
        ),
      );
    }
    return EncodedComponents(encoded, skipped);
  }
}

// ---------------------------------------------------------------------------
// Encoders
// ---------------------------------------------------------------------------

final class _Ctx {
  final String component;
  final ComponentRegistries registries;

  _Ctx(this.component, this.registries);

  Never fail(String message) => throw ComponentEncodeException(component, message);

  _Json object(Object? value, [String what = 'the value']) {
    if (value is Map) {
      return value.cast<String, Object?>();
    }
    fail('$what must be an object, got ${_describe(value)}');
  }

  List<Object?> list(Object? value, String what) {
    if (value is List) return value.cast<Object?>();
    fail('$what must be a list, got ${_describe(value)}');
  }

  String string(Object? value, String what) {
    if (value is String) return value;
    fail('$what must be a string, got ${_describe(value)}');
  }

  int integer(Object? value, String what) {
    if (value is int) return value;
    if (value is double && value == value.truncateToDouble()) return value.toInt();
    fail('$what must be an integer, got ${_describe(value)}');
  }

  double number(Object? value, String what) {
    if (value is num) return value.toDouble();
    fail('$what must be a number, got ${_describe(value)}');
  }

  bool boolean(Object? value, String what) {
    if (value is bool) return value;
    fail('$what must be a boolean, got ${_describe(value)}');
  }

  /// Reads `json[key]` or [fallback] when absent.
  T field<T>(_Json json, String key, T fallback, T Function(Object?, String) read) =>
      json.containsKey(key) ? read(json[key], key) : fallback;

  int intField(_Json json, String key, int fallback) =>
      field(json, key, fallback, integer);

  double numField(_Json json, String key, double fallback) =>
      field(json, key, fallback, number);

  bool boolField(_Json json, String key, bool fallback) =>
      field(json, key, fallback, boolean);

  /// Rejects keys the encoder does not know, so a misspelled field is not
  /// silently dropped.
  void only(_Json json, Set<String> known, [String what = 'the value']) {
    for (final key in json.keys) {
      if (!known.contains(key)) fail('unknown field `$key` in $what');
    }
  }

  int idOf(int? Function(String) lookup, String key, String registry) =>
      lookup(key) ?? fail('`$key` is not a known $registry');

  /// `Holder<SoundEvent>`: a VarInt of id + 1 (0 would start an inline sound
  /// event, which this codec does not write).
  void soundHolder(PacketWriter w, Object? value, String what) {
    final key = string(value, what);
    w.writeVarInt(idOf(registries.sound, key, 'sound event') + 1);
  }

  void optionalSound(PacketWriter w, Object? value, String what) {
    if (value == null) {
      w.writeBool(false);
    } else {
      w.writeBool(true);
      soundHolder(w, value, what);
    }
  }

  /// A `HolderSet`: `"#namespace:tag"` is VarInt 0 and the tag name; one id or
  /// a list of ids is VarInt (count + 1) and the ids.
  void holderSet(
    PacketWriter w,
    Object? value,
    String what,
    int? Function(String) lookup,
    String registry,
  ) {
    if (value is String && value.startsWith('#')) {
      w.writeVarInt(0);
      w.writeString(value.substring(1));
      return;
    }
    final keys = switch (value) {
      final String s => [s],
      final List<Object?> l => [for (final e in l) string(e, '$what entry')],
      _ => fail('$what must be a #tag, an id or a list of ids, got ${_describe(value)}'),
    };
    w.writeVarInt(keys.length + 1);
    for (final key in keys) {
      if (key.startsWith('#')) fail('$what: a tag cannot be inside a list');
      w.writeVarInt(idOf(lookup, key, registry));
    }
  }
}

String _describe(Object? value) =>
    value == null ? 'null' : '${value.runtimeType} ($value)';

typedef _Encoder = void Function(_Ctx c, Object? value, PacketWriter w);

/// A component with no payload (`{}` in JSON).
void _empty(_Ctx c, Object? v, PacketWriter w) {
  final json = c.object(v);
  c.only(json, const {});
}

const _rarities = ['common', 'uncommon', 'rare', 'epic'];

// Slot ids of `EquipmentSlot::get_slot_index` (Equippable.slot).
const _equipmentSlots = {
  'mainhand': 0,
  'feet': 1,
  'legs': 2,
  'chest': 3,
  'head': 4,
  'offhand': 5,
  'body': 6,
  'saddle': 7,
};

// `AttributeModifierSlot` of attribute modifiers (EquipmentSlotGroup ids).
const _attributeSlots = {
  'any': 0,
  'mainhand': 1,
  'offhand': 2,
  'hand': 3,
  'feet': 4,
  'legs': 5,
  'chest': 6,
  'head': 7,
  'armor': 8,
  'body': 9,
  'saddle': 10,
};

const _operations = {
  'add_value': 0,
  'add_multiplied_base': 1,
  'add_multiplied_total': 2,
};

// Pumpkin's `SwingAnimationType::from_id`: whack 0, stab 1, none 2.
const _swingTypes = {'whack': 0, 'stab': 1, 'none': 2};

final Map<String, _Encoder> _encoders = {
  // MaxStackSizeImpl::deserialize: VarInt, must fit a u8.
  'minecraft:max_stack_size': (c, v, w) {
    final n = c.integer(v, 'the value');
    if (n < 1 || n > 99) c.fail('max_stack_size must be 1 to 99, got $n');
    w.writeVarInt(n);
  },
  // MaxDamageImpl, DamageImpl, RepairCostImpl: one VarInt.
  'minecraft:max_damage': (c, v, w) {
    final n = c.integer(v, 'the value');
    if (n < 1) c.fail('max_damage must be positive, got $n');
    w.writeVarInt(n);
  },
  'minecraft:damage': (c, v, w) {
    final n = c.integer(v, 'the value');
    if (n < 0) c.fail('damage cannot be negative, got $n');
    w.writeVarInt(n);
  },
  'minecraft:repair_cost': (c, v, w) {
    final n = c.integer(v, 'the value');
    if (n < 0) c.fail('repair_cost cannot be negative, got $n');
    w.writeVarInt(n);
  },
  // EnchantableImpl: VarInt `value`.
  'minecraft:enchantable': (c, v, w) {
    final json = c.object(v);
    c.only(json, {'value'});
    final n = c.integer(json['value'], 'value');
    if (n < 1) c.fail('enchantable value must be positive, got $n');
    w.writeVarInt(n);
  },
  // RarityImpl: VarInt id (common 0 ... epic 3).
  'minecraft:rarity': (c, v, w) {
    final name = c.string(v, 'the value');
    final id = _rarities.indexOf(name);
    if (id < 0) c.fail('unknown rarity `$name`');
    w.writeVarInt(id);
  },
  // ItemModelImpl: the model id as a string.
  'minecraft:item_model': (c, v, w) => w.writeString(c.string(v, 'the value')),
  // ItemNameImpl::deserialize reads a plain string: the translation key
  // (its `serialize` writes `{"translate": key}` as NBT, so the host's own
  // reader is not the inverse of its writer). Vanilla JSON is a text
  // component; only `{"translate": key}` can be represented.
  'minecraft:item_name': (c, v, w) {
    final json = c.object(v);
    c.only(json, {'translate'});
    if (!json.containsKey('translate')) {
      c.fail('only {"translate": key} item names can be registered');
    }
    w.writeString(c.string(json['translate'], 'translate'));
  },
  // LoreImpl: VarInt count, then one NBT text component per line. Only the
  // empty list is supported.
  'minecraft:lore': (c, v, w) {
    final lines = c.list(v, 'the value');
    if (lines.isNotEmpty) c.fail('only an empty lore can be encoded');
    w.writeVarInt(0);
  },
  // EnchantmentsImpl: VarInt count, then (enchantment id VarInt, level VarInt).
  'minecraft:enchantments': (c, v, w) {
    var json = c.object(v);
    if (json.containsKey('levels')) {
      c.only(json, {'levels', 'show_in_tooltip'});
      json = c.object(json['levels'], 'levels');
    }
    w.writeVarInt(json.length);
    for (final e in json.entries) {
      w.writeVarInt(c.idOf(c.registries.enchantment, e.key, 'enchantment'));
      final level = c.integer(e.value, 'level of ${e.key}');
      if (level < 1) c.fail('level of ${e.key} must be at least 1');
      w.writeVarInt(level);
    }
  },
  // RepairableImpl: HolderSet<Item>.
  'minecraft:repairable': (c, v, w) {
    final json = c.object(v);
    c.only(json, {'items'});
    c.holderSet(w, json['items'], 'items', c.registries.item, 'item');
  },
  // ToolImpl: rules, default speed, damage per block, creative flag.
  'minecraft:tool': (c, v, w) {
    final json = c.object(v);
    c.only(json, {
      'rules',
      'default_mining_speed',
      'damage_per_block',
      'can_destroy_blocks_in_creative',
    });
    final rules = c.list(json['rules'] ?? const <Object?>[], 'rules');
    w.writeVarInt(rules.length);
    for (final r in rules) {
      final rule = c.object(r, 'a rule');
      c.only(rule, {'blocks', 'speed', 'correct_for_drops'}, 'a rule');
      if (!rule.containsKey('blocks')) c.fail('a rule has no `blocks`');
      c.holderSet(w, rule['blocks'], 'blocks', c.registries.block, 'block');
      final speed = rule['speed'];
      w.writeOptional<Object>(speed, (w, s) => w.writeFloat(c.number(s, 'speed')));
      final drops = rule['correct_for_drops'];
      w.writeOptional<Object>(
        drops,
        (w, d) => w.writeBool(c.boolean(d, 'correct_for_drops')),
      );
    }
    w.writeFloat(c.numField(json, 'default_mining_speed', 1.0));
    final perBlock = c.intField(json, 'damage_per_block', 1);
    if (perBlock < 0) c.fail('damage_per_block cannot be negative');
    w.writeVarInt(perBlock);
    w.writeBool(c.boolField(json, 'can_destroy_blocks_in_creative', true));
  },
  // WeaponImpl: VarInt item_damage_per_attack, f32 disable_blocking_for_seconds
  // (read and discarded by the host).
  'minecraft:weapon': (c, v, w) {
    final json = c.object(v);
    c.only(json, {'item_damage_per_attack', 'disable_blocking_for_seconds'});
    final damage = c.intField(json, 'item_damage_per_attack', 1);
    if (damage < 0) c.fail('item_damage_per_attack cannot be negative');
    w.writeVarInt(damage);
    w.writeFloat(c.numField(json, 'disable_blocking_for_seconds', 0.0));
  },
  // EquippableImpl.
  'minecraft:equippable': (c, v, w) {
    final json = c.object(v);
    c.only(json, {
      'slot',
      'equip_sound',
      'asset_id',
      'camera_overlay',
      'allowed_entities',
      'dispensable',
      'swappable',
      'damage_on_hurt',
      'equip_on_interact',
      'can_be_sheared',
      'shearing_sound',
    });
    final slot = c.string(json['slot'], 'slot');
    final slotId = _equipmentSlots[slot];
    if (slotId == null) c.fail('unknown equipment slot `$slot`');
    w.writeVarInt(slotId);
    c.soundHolder(
      w,
      json['equip_sound'] ?? 'minecraft:item.armor.equip_generic',
      'equip_sound',
    );
    w.writeOptional<Object>(
      json['asset_id'],
      (w, a) => w.writeString(c.string(a, 'asset_id')),
    );
    w.writeOptional<Object>(
      json['camera_overlay'],
      (w, a) => w.writeString(c.string(a, 'camera_overlay')),
    );
    w.writeOptional<Object>(
      json['allowed_entities'],
      (w, a) =>
          c.holderSet(w, a, 'allowed_entities', c.registries.entityType, 'entity type'),
    );
    w.writeBool(c.boolField(json, 'dispensable', true));
    w.writeBool(c.boolField(json, 'swappable', true));
    w.writeBool(c.boolField(json, 'damage_on_hurt', true));
    w.writeBool(c.boolField(json, 'equip_on_interact', false));
    w.writeBool(c.boolField(json, 'can_be_sheared', false));
    c.soundHolder(
      w,
      json['shearing_sound'] ?? 'minecraft:item.shears.snip',
      'shearing_sound',
    );
  },
  // AttributeModifiersImpl. NOTE: the host's reader parses all of this and
  // then DISCARDS it (`attribute_modifiers: Cow::Borrowed(&[])`), so the
  // registered item has no attribute modifiers on the server until the host
  // keeps them. The bytes are vanilla's network format.
  'minecraft:attribute_modifiers': (c, v, w) {
    final modifiers = c.list(v, 'the value');
    w.writeVarInt(modifiers.length);
    for (final m in modifiers) {
      final json = c.object(m, 'a modifier');
      c.only(json, {'type', 'id', 'amount', 'operation', 'slot', 'display'}, 'a modifier');
      w.writeVarInt(
        c.idOf(
          c.registries.attribute,
          c.string(json['type'], 'type'),
          'attribute',
        ),
      );
      w.writeString(c.string(json['id'], 'id'));
      w.writeDouble(c.number(json['amount'], 'amount'));
      final op = c.string(json['operation'], 'operation');
      final opId = _operations[op];
      if (opId == null) c.fail('unknown operation `$op`');
      w.writeVarInt(opId);
      final slot = c.field<String>(json, 'slot', 'any', c.string);
      final slotId = _attributeSlots[slot];
      if (slotId == null) c.fail('unknown attribute slot `$slot`');
      w.writeVarInt(slotId);
      // Display: default 0, hidden 1 (override 2 needs a text component).
      final display = json['display'];
      if (display == null) {
        w.writeVarInt(0);
      } else {
        final type = c.string(c.object(display, 'display')['type'], 'display.type');
        switch (type) {
          case 'default':
            w.writeVarInt(0);
          case 'hidden':
            w.writeVarInt(1);
          default:
            c.fail('display type `$type` is not supported');
        }
      }
    }
  },
  // UseEffectsImpl: bool can_sprint, bool interact_vibrations, f32
  // speed_multiplier (all read and discarded by the host).
  'minecraft:use_effects': (c, v, w) {
    final json = c.object(v);
    c.only(json, {'can_sprint', 'interact_vibrations', 'speed_multiplier'});
    w.writeBool(c.boolField(json, 'can_sprint', false));
    w.writeBool(c.boolField(json, 'interact_vibrations', true));
    w.writeFloat(c.numField(json, 'speed_multiplier', 0.2));
  },
  // TooltipDisplayImpl: bool hide_tooltip, VarInt count and the component
  // type ids (read and discarded by the host).
  'minecraft:tooltip_display': (c, v, w) {
    final json = c.object(v);
    c.only(json, {'hide_tooltip', 'hidden_components'});
    w.writeBool(c.boolField(json, 'hide_tooltip', false));
    final hidden = c.list(json['hidden_components'] ?? const <Object?>[], 'hidden_components');
    w.writeVarInt(hidden.length);
    for (final h in hidden) {
      w.writeVarInt(
        c.idOf(
          c.registries.dataComponentType,
          c.string(h, 'a hidden component'),
          'data component type',
        ),
      );
    }
  },
  // BreakSoundImpl: reads one VarInt and discards it: a Holder<SoundEvent>
  // (id + 1).
  'minecraft:break_sound': (c, v, w) => c.soundHolder(w, v, 'the value'),
  // SwingAnimationImpl (attack_animation): VarInt type, VarInt duration.
  // The ids are Pumpkin's `SwingAnimationType::from_id`: whack 0, stab 1,
  // none 2.
  'minecraft:attack_animation': (c, v, w) {
    final json = c.object(v);
    c.only(json, {'type', 'duration'});
    final type = c.field<String>(json, 'type', 'whack', c.string);
    final id = _swingTypes[type];
    if (id == null) c.fail('unknown animation type `$type`');
    w.writeVarInt(id);
    w.writeVarInt(c.intField(json, 'duration', 6));
  },
  // AttackRangeImpl: six f32.
  'minecraft:attack_range': (c, v, w) {
    final json = c.object(v);
    c.only(json, {
      'min_reach',
      'max_reach',
      'min_creative_reach',
      'max_creative_reach',
      'hitbox_margin',
      'mob_factor',
    });
    w.writeFloat(c.numField(json, 'min_reach', 0.0));
    w.writeFloat(c.numField(json, 'max_reach', 3.0));
    w.writeFloat(c.numField(json, 'min_creative_reach', 0.0));
    w.writeFloat(c.numField(json, 'max_creative_reach', 5.0));
    w.writeFloat(c.numField(json, 'hitbox_margin', 0.3));
    w.writeFloat(c.numField(json, 'mob_factor', 1.0));
  },
  // MinimumAttackChargeImpl: f32.
  'minecraft:minimum_attack_charge': (c, v, w) =>
      w.writeFloat(c.number(v, 'the value')),
  // DamageTypeImpl: VarInt id (a u8 in the host).
  'minecraft:damage_type': (c, v, w) => w.writeVarInt(
    c.idOf(c.registries.damageType, c.string(v, 'the value'), 'damage type'),
  ),
  // PiercingWeaponImpl: bool deals_knockback, bool dismounts, optional
  // sound, optional hit_sound.
  'minecraft:piercing_weapon': (c, v, w) {
    final json = c.object(v);
    c.only(json, {'deals_knockback', 'dismounts', 'sound', 'hit_sound'});
    w.writeBool(c.boolField(json, 'deals_knockback', true));
    w.writeBool(c.boolField(json, 'dismounts', false));
    c.optionalSound(w, json['sound'], 'sound');
    c.optionalSound(w, json['hit_sound'], 'hit_sound');
  },
  // KineticWeaponImpl.
  'minecraft:kinetic_weapon': (c, v, w) {
    final json = c.object(v);
    c.only(json, {
      'contact_cooldown_ticks',
      'delay_ticks',
      'dismount_conditions',
      'knockback_conditions',
      'damage_conditions',
      'forward_movement',
      'damage_multiplier',
      'sound',
      'hit_sound',
    });
    w.writeVarInt(c.intField(json, 'contact_cooldown_ticks', 10));
    w.writeVarInt(c.intField(json, 'delay_ticks', 0));
    for (final key in const [
      'dismount_conditions',
      'knockback_conditions',
      'damage_conditions',
    ]) {
      w.writeOptional<Object>(json[key], (w, cond) {
        final condition = c.object(cond, key);
        c.only(condition, {'max_duration_ticks', 'min_speed', 'min_relative_speed'}, key);
        if (!condition.containsKey('max_duration_ticks')) {
          c.fail('$key has no max_duration_ticks');
        }
        w.writeVarInt(c.integer(condition['max_duration_ticks'], 'max_duration_ticks'));
        w.writeFloat(c.numField(condition, 'min_speed', 0.0));
        w.writeFloat(c.numField(condition, 'min_relative_speed', 0.0));
      });
    }
    w.writeFloat(c.numField(json, 'forward_movement', 0.0));
    w.writeFloat(c.numField(json, 'damage_multiplier', 1.0));
    c.optionalSound(w, json['sound'], 'sound');
    c.optionalSound(w, json['hit_sound'], 'hit_sound');
  },
  // UnbreakableImpl, GliderImpl: no payload.
  'minecraft:unbreakable': _empty,
  'minecraft:glider': _empty,
  // TooltipStyleImpl: the style id as a string.
  'minecraft:tooltip_style': (c, v, w) => w.writeString(c.string(v, 'the value')),
};
