// `dev.ryanhcode.sable.index`: the two attributes and the seven tags Sable
// registers, as data.
//
// Java registers them into the loader's registries (`SableAttributes.register`
// patches the player attribute supplier, `SableTags` is a bag of `TagKey`s).
// The Dart host owns the registries, so this file is the single source of the
// ids, the attribute definitions and the one pure rule that reads an attribute:
// `getPushCooldownTicks`.
//
// Pure: no host imports.
import 'dart:math' as math;

/// `dev.ryanhcode.sable.index.SableAttributes`: the player attributes Sable
/// adds.
abstract final class SableAttributes {
  /// `PUNCH_STRENGTH_NAME` (`SableAttributes.java:15`).
  static const String punchStrengthName = 'player.sub_level_punch_strength';

  /// `PUNCH_COOLDOWN_NAME` (`SableAttributes.java:18`).
  static const String punchCooldownName = 'player.sub_level_punch_cooldown';

  /// The translation key of the strength attribute
  /// (`"attribute.name." + PUNCH_STRENGTH_NAME`, `SableAttributes.java:16`).
  static const String punchStrengthTranslationKey = 'attribute.name.$punchStrengthName';

  /// The translation key of the cooldown attribute (`SableAttributes.java:19`).
  static const String punchCooldownTranslationKey = 'attribute.name.$punchCooldownName';

  /// `PUNCH_STRENGTH_ATTRIBUTE`: `RangedAttribute(name, 1.0, -100.0, 100.0)`,
  /// syncable (`SableAttributes.java:16`).
  static const RangedAttributeDefinition punchStrength = RangedAttributeDefinition(
    name: punchStrengthName,
    defaultValue: 1.0,
    minValue: -100.0,
    maxValue: 100.0,
    syncable: true,
  );

  /// `PUNCH_COOLDOWN_ATTRIBUTE`: `RangedAttribute(name, 0.0, 0, 10)`, syncable
  /// (`SableAttributes.java:19`).
  static const RangedAttributeDefinition punchCooldown = RangedAttributeDefinition(
    name: punchCooldownName,
    defaultValue: 0.0,
    minValue: 0.0,
    maxValue: 10.0,
    syncable: true,
  );

  /// Every attribute, in registration order (`SableAttributes.register`).
  static const List<RangedAttributeDefinition> all = [punchStrength, punchCooldown];

  /// `getPushCooldownTicks(entity)` (`SableAttributes.java:41-43`):
  /// `Mth.ceil(value * 20)`.
  ///
  /// The Java value is a `double` attribute; `Mth.ceil` is
  /// `MathHelper.ceil`, i.e. `(int) Math.ceil(value)`.
  static int getPushCooldownTicks(double cooldownValue) => (cooldownValue * 20.0).ceil();

}

/// One `RangedAttribute` as data: name, default, range and syncability.
final class RangedAttributeDefinition {
  /// The attribute's name, `player.sub_level_punch_strength`.
  ///
  /// TODO(parity): `SableAttributes.java:21-25` leaves the registry id to the
  /// loader (`PUNCH_STRENGTH` / `PUNCH_COOLDOWN` are assigned by loader code and
  /// the common tree never names the `ResourceLocation`). The ids a NeoForge
  /// build registers are therefore not visible in this tree; the plugin must
  /// take them from the built jar, not from a guess here.
  final String name;

  final double defaultValue;
  final double minValue;
  final double maxValue;

  /// `setSyncable(true)`: both Sable attributes are synced to the client.
  final bool syncable;

  const RangedAttributeDefinition({
    required this.name,
    required this.defaultValue,
    required this.minValue,
    required this.maxValue,
    required this.syncable,
  });

  /// `RangedAttribute.sanitizeValue`: clamps into the range.
  double clamp(double value) => math.min(math.max(value, minValue), maxValue);

  @override
  String toString() => 'RangedAttributeDefinition[$name, default=$defaultValue, '
      '[$minValue, $maxValue], syncable=$syncable]';
}

/// `dev.ryanhcode.sable.index.SableTags`: the tags Sable declares.
///
/// The ids are `sable:<path>` (`Sable.sablePath`); the registry each one
/// belongs to is what the Java `TagKey.create` call names.
abstract final class SableTags {
  /// Entity types kept inside a sub-level when it moves
  /// (`SableTags.java:11-14`).
  static const String retainInSubLevel = 'sable:retain_in_sub_level';

  /// Entity types destroyed with the sub-level (`SableTags.java:15-18`).
  static const String destroyWithSubLevel = 'sable:destroy_with_sub_level';

  /// Entity types destroyed when they leave the plot (`SableTags.java:19-22`).
  static const String destroyWhenLeavingPlot = 'sable:destroy_when_leaving_plot';

  /// Blocks always chunk-rendered on a sub-level (`SableTags.java:24-27`).
  static const String alwaysChunkRendering = 'sable:always_chunk_rendering';

  /// Blocks an entity bounces off (`SableTags.java:29-32`).
  static const String bouncy = 'sable:bouncy';

  /// Items that paddle a sub-level (`SableTags.java:34-37`).
  static const String paddles = 'sable:paddles';

  /// Blocks removed without the assembly sound/particles
  /// (`SableTags.java:39-42`).
  static const String silentAssemblyRemoval = 'sable:silent_assembly_removal';

  /// The entity-type tags, in declaration order.
  static const List<String> entityTypeTags = [
    retainInSubLevel,
    destroyWithSubLevel,
    destroyWhenLeavingPlot,
  ];

  /// The block tags, in declaration order.
  static const List<String> blockTags = [alwaysChunkRendering, bouncy, silentAssemblyRemoval];

  /// The item tags, in declaration order.
  static const List<String> itemTags = [paddles];
}

/// `dev.ryanhcode.sable.index.SableToasts`: the client toast tokens.
///
/// Java has three bare `new SystemToast.SystemToastId()` instances
/// (`SableToasts.java:9-11`) — no id, no name, only identity, because the
/// toast id is what deduplicates a repeated toast on screen. The Dart port
/// keeps three distinct tokens for the same reason; they are not registry ids
/// and never go on the wire.
abstract final class SableToasts {
  /// `SUB_LEVEL_LOAD_FAILURE` (`SableToasts.java:9`).
  static const Object subLevelLoadFailure = _ToastToken('sub_level_load_failure');

  /// `SUB_LEVEL_SAVE_FAILURE` (`SableToasts.java:10`).
  static const Object subLevelSaveFailure = _ToastToken('sub_level_save_failure');

  /// `SUB_LEVEL_PHYSICS_FAILURE` (`SableToasts.java:11`).
  static const Object subLevelPhysicsFailure = _ToastToken('sub_level_physics_failure');

  /// Every toast token, in declaration order.
  static const List<Object> all = [
    subLevelLoadFailure,
    subLevelSaveFailure,
    subLevelPhysicsFailure,
  ];
}

/// One toast token; the label is for logs only (Java has none).
final class _ToastToken {
  final String label;

  const _ToastToken(this.label);

  @override
  String toString() => 'SystemToastId[$label]';
}
