import 'bindings.g.dart' as generated;
import 'bindings.g.dart';
import 'host_result.dart';

/// A damage type to register (`damage-types.wit`).
///
/// ```dart
/// DamageTypeRegistries.register(
///   const DamageTypeSpec(key: 'my_plugin:crush', messageId: 'my_plugin.crush'),
/// );
/// await player.damageWith('my_plugin:crush', 4);
/// ```
final class DamageTypeSpec {
  /// `namespace:path`; the `minecraft` namespace is reserved.
  final String key;

  /// Death message translation key suffix, `death.attack.<messageId>`. Clients
  /// need a resource pack for the translation.
  final String messageId;

  final DamageScaling scaling;

  /// The hunger a player loses when hurt by it.
  final double exhaustion;

  /// Sound and animation, `null` for the default.
  final DamageEffects? effects;

  final DeathMessageType deathMessageType;

  const DamageTypeSpec({
    required this.key,
    required this.messageId,
    this.scaling = DamageScaling.whenCausedByLivingNonPlayer,
    this.exhaustion = 0.0,
    this.effects,
    this.deathMessageType = DeathMessageType.default_,
  });

  generated.DamageTypeDefinition toWire() => generated.DamageTypeDefinition(
    key: key,
    messageId: messageId,
    scaling: scaling,
    exhaustion: exhaustion,
    effects: effects,
    deathMessageType: deathMessageType,
  );
}

/// The host's damage type registry. Registration needs
/// [Permissions.registryDamageTypes] and only works while the server loads.
abstract final class DamageTypeRegistries {
  /// Registers [type] and returns its id (the same definition again returns the
  /// id it has). Throws a [HostException] on failure.
  static int register(DamageTypeSpec type) => unwrapHost(
    generated.damageTypes.registerDamageType(definition: type.toWire()),
    'Registering the damage type ${type.key}',
  );

  /// The id of the damage type [key], vanilla or plugin.
  static int? idOf(String key) => generated.damageTypes.getDamageTypeId(key: key);

  /// The number of vanilla damage types (the id of the first plugin type).
  static int get vanillaCount => generated.damageTypes.getVanillaDamageTypeCount();

  /// All plugin damage types in id order.
  static List<DamageTypeEntry> get registered =>
      generated.damageTypes.getRegisteredDamageTypes();
}

/// Hurting a living entity with a registered damage type.
extension LivingDamageWith on LivingEntity {
  /// Damages the entity by [amount] with the damage type [key]. Throws a
  /// [HostException] for an unknown key.
  Future<void> damageWith(String key, double amount) => unwrapHostAsync(
    damageByKey(amount: amount, damageTypeKey: key),
    'Damaging with $key',
  );
}

/// Hurting a player with a registered damage type.
extension PlayerDamageWith on Player {
  /// Damages the player by [amount] with the damage type [key]. Throws a
  /// [HostException] for an unknown key.
  Future<void> damageWith(String key, double amount) => unwrapHostAsync(
    damageByKey(amount: amount, damageTypeKey: key),
    'Damaging with $key',
  );
}
