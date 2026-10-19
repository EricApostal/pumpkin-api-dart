/// Create's damage types (`AllDamageTypes` + `CreateDamageSources`), registered by the
/// `content` module. Call the functions from any module:
///
/// ```dart
/// await CreateDamage.crush.hurt(entity, 4);          // CreateDamageSources.crush(level)
/// await CreateDamage.potatoCannon.hurt(entity, 2, causingEntity: owner);
/// ```
///
/// The host only knows a damage type by key (`damageByKey`): the causing and direct entity of the
/// Java `DamageSource` are not expressible in the host API yet, so [hurt] with an attacker is a
/// plain hurt with that damage type (documented host gap).
library;

import 'package:pumpkin_api/pumpkin_api.dart';

/// One Create damage type.
final class CreateDamageType {
  /// `create:<path>`.
  final String key;

  /// `AllDamageTypes` constant name.
  final String javaConstant;

  const CreateDamageType(this.key, this.javaConstant);

  /// Hurts a living entity (`entity.hurt(CreateDamageSources.x(level), amount)`).
  Future<void> hurt(LivingEntity entity, double amount) => entity.damageWith(key, amount);

  /// Hurts a player.
  Future<void> hurtPlayer(Player player, double amount) => player.damageWith(key, amount);

  /// Hurts any entity that is living; returns false for others (items, projectiles).
  Future<bool> hurtEntity(Entity entity, double amount) async {
    final living = entity.asLiving();
    if (living == null) return false;
    await living.damageWith(key, amount);
    return true;
  }

  /// Whether a damage type key (as reported by `entity-damage` events) is this one.
  bool matches(String damageTypeKey) => damageTypeKey == key || damageTypeKey == key.substring(key.indexOf(':') + 1);

  @override
  String toString() => key;
}

/// `AllDamageTypes` / `CreateDamageSources`.
abstract final class CreateDamage {
  static const crush = CreateDamageType('create:crush', 'CRUSH');
  static const cuckooSurprise = CreateDamageType('create:cuckoo_surprise', 'CUCKOO_SURPRISE');
  static const fanFire = CreateDamageType('create:fan_fire', 'FAN_FIRE');
  static const fanLava = CreateDamageType('create:fan_lava', 'FAN_LAVA');
  static const drill = CreateDamageType('create:mechanical_drill', 'DRILL');
  static const roller = CreateDamageType('create:mechanical_roller', 'ROLLER');
  static const saw = CreateDamageType('create:mechanical_saw', 'SAW');
  static const potatoCannon = CreateDamageType('create:potato_cannon', 'POTATO_CANNON');
  static const runOver = CreateDamageType('create:run_over', 'RUN_OVER');

  static const List<CreateDamageType> all = [
    crush,
    cuckooSurprise,
    fanFire,
    fanLava,
    drill,
    roller,
    saw,
    potatoCannon,
    runOver,
  ];
}
