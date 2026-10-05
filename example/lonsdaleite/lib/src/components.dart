/// Typed views of the data components the mod's items carry, in the JSON
/// shape of the vanilla data generator (defaults omitted). They hold plain
/// values only: nothing here depends on the host bindings.
library;

/// A JSON object.
typedef Json = Map<String, Object?>;

T _field<T extends Object>(Json json, String key, T fallback) {
  final value = json[key];
  if (value == null) return fallback;
  return _cast<T>(value, key);
}

T _required<T extends Object>(Json json, String key) {
  final value = json[key];
  if (value == null) throw FormatException('Missing `$key`');
  return _cast<T>(value, key);
}

T _cast<T extends Object>(Object value, String key) {
  if (value is T) return value;
  if (value is int && 0.0 is T) return value.toDouble() as T;
  throw FormatException('Expected $T for `$key`, got ${value.runtimeType}');
}

/// One entry of `minecraft:attribute_modifiers`.
final class AttributeModifierSpec {
  /// The attribute, e.g. `minecraft:attack_damage`.
  final String attribute;

  /// The modifier id, e.g. `minecraft:base_attack_damage`.
  final String id;
  final double amount;

  /// `add_value`, `add_multiplied_base` or `add_multiplied_total`.
  final String operation;

  /// `mainhand`, `head`, `chest`, `legs`, `feet`, ...
  final String slot;

  const AttributeModifierSpec({
    required this.attribute,
    required this.id,
    required this.amount,
    required this.operation,
    required this.slot,
  });

  factory AttributeModifierSpec.fromJson(Json json) => AttributeModifierSpec(
    attribute: _required(json, 'type'),
    id: _required(json, 'id'),
    amount: _required(json, 'amount'),
    operation: _required(json, 'operation'),
    slot: _required(json, 'slot'),
  );

  Json toJson() => {
    'type': attribute,
    'id': id,
    'amount': amount,
    'operation': operation,
    'slot': slot,
  };
}

/// One rule of a [ToolComponent].
final class ToolRule {
  /// A block id or a `#tag`.
  final String blocks;

  /// Mining speed on matching blocks, if the rule sets one.
  final double? speed;

  /// Whether matching blocks drop with this tool, if the rule decides that.
  final bool? correctForDrops;

  const ToolRule({required this.blocks, this.speed, this.correctForDrops});

  factory ToolRule.fromJson(Json json) => ToolRule(
    blocks: _required(json, 'blocks'),
    speed: (json['speed'] as num?)?.toDouble(),
    correctForDrops: json['correct_for_drops'] as bool?,
  );

  Json toJson() => {
    'blocks': blocks,
    if (speed != null) 'speed': speed,
    if (correctForDrops != null) 'correct_for_drops': correctForDrops,
  };
}

/// `minecraft:tool`.
final class ToolComponent {
  final List<ToolRule> rules;

  /// Durability lost per mined block with non-zero hardness.
  final int damagePerBlock;
  final bool canDestroyBlocksInCreative;

  const ToolComponent({
    required this.rules,
    this.damagePerBlock = 1,
    this.canDestroyBlocksInCreative = true,
  });

  factory ToolComponent.fromJson(Json json) => ToolComponent(
    rules: [
      for (final r in _required<List<Object?>>(json, 'rules'))
        ToolRule.fromJson(r! as Json),
    ],
    damagePerBlock: _field(json, 'damage_per_block', 1),
    canDestroyBlocksInCreative: _field(
      json,
      'can_destroy_blocks_in_creative',
      true,
    ),
  );

  /// The mining speed on a block that matches the given tags (the first rule
  /// with a speed that matches wins, as in the game), or 1.0.
  double miningSpeed(bool Function(String blocks) matches) {
    for (final rule in rules) {
      if (rule.speed != null && matches(rule.blocks)) return rule.speed!;
    }
    return 1.0;
  }

  /// Whether the tool is the right one to get drops from a block.
  bool isCorrectForDrops(bool Function(String blocks) matches) {
    for (final rule in rules) {
      if (rule.correctForDrops != null && matches(rule.blocks)) {
        return rule.correctForDrops!;
      }
    }
    return false;
  }

  Json toJson() => {
    'rules': [for (final r in rules) r.toJson()],
    if (damagePerBlock != 1) 'damage_per_block': damagePerBlock,
    if (!canDestroyBlocksInCreative) 'can_destroy_blocks_in_creative': false,
  };
}

/// `minecraft:equippable`.
final class EquippableComponent {
  final String slot;
  final String equipSound;

  /// The equipment asset (`lonsdaleite:lonsdaleite`), a client resource.
  final String assetId;
  final bool damageOnHurt;
  final bool dispensable;
  final bool swappable;
  final bool equipOnInteract;

  const EquippableComponent({
    required this.slot,
    required this.equipSound,
    required this.assetId,
    this.damageOnHurt = true,
    this.dispensable = true,
    this.swappable = true,
    this.equipOnInteract = false,
  });

  factory EquippableComponent.fromJson(Json json) => EquippableComponent(
    slot: _required(json, 'slot'),
    equipSound: _required(json, 'equip_sound'),
    assetId: _required(json, 'asset_id'),
    damageOnHurt: _field(json, 'damage_on_hurt', true),
    dispensable: _field(json, 'dispensable', true),
    swappable: _field(json, 'swappable', true),
    equipOnInteract: _field(json, 'equip_on_interact', false),
  );

  Json toJson() => {
    'slot': slot,
    'equip_sound': equipSound,
    'asset_id': assetId,
    if (!damageOnHurt) 'damage_on_hurt': false,
    if (!dispensable) 'dispensable': false,
    if (!swappable) 'swappable': false,
    if (equipOnInteract) 'equip_on_interact': true,
  };
}

/// `minecraft:weapon`.
final class WeaponComponent {
  final int itemDamagePerAttack;
  final double disableBlockingForSeconds;

  const WeaponComponent({
    this.itemDamagePerAttack = 1,
    this.disableBlockingForSeconds = 0,
  });

  factory WeaponComponent.fromJson(Json json) => WeaponComponent(
    itemDamagePerAttack: _field(json, 'item_damage_per_attack', 1),
    disableBlockingForSeconds: _field(
      json,
      'disable_blocking_for_seconds',
      0.0,
    ),
  );

  Json toJson() => {
    if (itemDamagePerAttack != 1) 'item_damage_per_attack': itemDamagePerAttack,
    if (disableBlockingForSeconds != 0)
      'disable_blocking_for_seconds': disableBlockingForSeconds,
  };
}

/// A `dismount_conditions`, `knockback_conditions` or `damage_conditions`
/// entry of [KineticWeaponComponent].
final class KineticCondition {
  final int maxDurationTicks;

  /// The speed the user must have (`min_speed`), or the speed relative to the
  /// target (`min_relative_speed`) for the damage condition.
  final double speed;

  /// Whether [speed] is relative to the target.
  final bool relative;

  const KineticCondition({
    required this.maxDurationTicks,
    required this.speed,
    this.relative = false,
  });

  factory KineticCondition.fromJson(Json json) {
    final relative = json.containsKey('min_relative_speed');
    return KineticCondition(
      maxDurationTicks: _required(json, 'max_duration_ticks'),
      speed: _required(json, relative ? 'min_relative_speed' : 'min_speed'),
      relative: relative,
    );
  }

  Json toJson() => {
    'max_duration_ticks': maxDurationTicks,
    relative ? 'min_relative_speed' : 'min_speed': speed,
  };
}

/// `minecraft:kinetic_weapon`: the charged lunge of a spear.
final class KineticWeaponComponent {
  final int delayTicks;
  final KineticCondition dismount;
  final KineticCondition knockback;
  final KineticCondition damage;
  final double forwardMovement;
  final double damageMultiplier;
  final String sound;
  final String hitSound;

  const KineticWeaponComponent({
    required this.delayTicks,
    required this.dismount,
    required this.knockback,
    required this.damage,
    required this.forwardMovement,
    required this.damageMultiplier,
    required this.sound,
    required this.hitSound,
  });

  factory KineticWeaponComponent.fromJson(Json json) => KineticWeaponComponent(
    delayTicks: _required(json, 'delay_ticks'),
    dismount: KineticCondition.fromJson(_required(json, 'dismount_conditions')),
    knockback: KineticCondition.fromJson(
      _required(json, 'knockback_conditions'),
    ),
    damage: KineticCondition.fromJson(_required(json, 'damage_conditions')),
    forwardMovement: _required(json, 'forward_movement'),
    damageMultiplier: _required(json, 'damage_multiplier'),
    sound: _required(json, 'sound'),
    hitSound: _required(json, 'hit_sound'),
  );

  Json toJson() => {
    'delay_ticks': delayTicks,
    'dismount_conditions': dismount.toJson(),
    'knockback_conditions': knockback.toJson(),
    'damage_conditions': damage.toJson(),
    'forward_movement': forwardMovement,
    'damage_multiplier': damageMultiplier,
    'sound': sound,
    'hit_sound': hitSound,
  };
}

/// `minecraft:piercing_weapon`.
final class PiercingWeaponComponent {
  final String sound;
  final String hitSound;

  const PiercingWeaponComponent({required this.sound, required this.hitSound});

  factory PiercingWeaponComponent.fromJson(Json json) =>
      PiercingWeaponComponent(
        sound: _required(json, 'sound'),
        hitSound: _required(json, 'hit_sound'),
      );

  Json toJson() => {'sound': sound, 'hit_sound': hitSound};
}

/// An item's default components: the raw JSON plus typed views of the ones the
/// server acts on. The raw map is the source of truth and keeps components this
/// class has no view for.
final class ItemComponents {
  /// Components by id (`minecraft:tool`, ...).
  final Json raw;

  const ItemComponents(this.raw);

  bool has(String component) => raw.containsKey(component);

  Json? _object(String component) => raw[component] as Json?;

  int? get maxStackSize => raw['minecraft:max_stack_size'] as int?;
  int? get maxDamage => raw['minecraft:max_damage'] as int?;
  String get rarity => (raw['minecraft:rarity'] as String?) ?? 'common';
  int? get enchantable => _object('minecraft:enchantable')?['value'] as int?;

  /// The `#tag` or item id that repairs this item.
  String? get repairable =>
      _object('minecraft:repairable')?['items'] as String?;

  String? get blockTransformer => raw['minecraft:block_transformer'] as String?;

  ToolComponent? get tool => _typed('minecraft:tool', ToolComponent.fromJson);

  WeaponComponent? get weapon =>
      _typed('minecraft:weapon', WeaponComponent.fromJson);

  EquippableComponent? get equippable =>
      _typed('minecraft:equippable', EquippableComponent.fromJson);

  KineticWeaponComponent? get kineticWeapon =>
      _typed('minecraft:kinetic_weapon', KineticWeaponComponent.fromJson);

  PiercingWeaponComponent? get piercingWeapon =>
      _typed('minecraft:piercing_weapon', PiercingWeaponComponent.fromJson);

  List<AttributeModifierSpec> get attributeModifiers => [
    for (final m
        in (raw['minecraft:attribute_modifiers'] as List<Object?>?) ?? const [])
      AttributeModifierSpec.fromJson(m! as Json),
  ];

  /// The first modifier of [attribute], or `null`.
  AttributeModifierSpec? modifier(String attribute) {
    for (final m in attributeModifiers) {
      if (m.attribute == attribute) return m;
    }
    return null;
  }

  T? _typed<T>(String component, T Function(Json) parse) {
    final json = _object(component);
    return json == null ? null : parse(json);
  }

  /// These components with [overrides] replacing the ones they name.
  ItemComponents merged(Json overrides) =>
      ItemComponents({...raw, ...overrides});
}
