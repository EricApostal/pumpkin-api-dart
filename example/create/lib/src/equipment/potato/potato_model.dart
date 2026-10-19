// Port of `api/equipment/potatoCannon/PotatoCannonProjectileType`, the hit actions of
// `content/equipment/potatoCannon/*` as data, and the shot / flight maths of
// `PotatoCannonItem.use` and `PotatoProjectileEntity`. Pure.
import 'dart:convert';
import 'dart:typed_data';

import '../model/dir.dart';
import '../model/knockback.dart';
import '../model/vec.dart';

/// `PotatoProjectileEntityHitAction`s (data only; the host layer executes them).
sealed class PotatoEntityHitAction {
  const PotatoEntityHitAction();

  static PotatoEntityHitAction? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = json['type'] as String?;
    switch (type) {
      case 'create:set_on_fire':
        return SetOnFire((json['ticks'] as num).toInt());
      case 'create:potion_effect':
        return PotionEffectAction(
          effect: json['effect'] as String,
          level: (json['level'] as num).toInt(),
          ticks: (json['ticks'] as num).toInt(),
          recoverable: json['recoverable'] as bool,
        );
      case 'create:food_effects':
        final food = json['food_property'] as Map;
        return FoodEffectsAction(
          effects: [
            for (final e in (food['effects'] as List? ?? const []))
              if (e is Map && e['effect'] is Map)
                FoodEffect(
                  effect: (e['effect'] as Map).cast<String, Object?>(),
                  probability: ((e['probability'] as num?) ?? 1).toDouble(),
                ),
          ],
          recoverable: json['recoverable'] as bool,
        );
      case 'create:chorus_teleport':
        return ChorusTeleport((json['teleport_diameter'] as num).toDouble());
      case 'create:cure_zombie_villager':
        return const CureZombieVillager();
      case 'create:suspicious_stew':
        return const SuspiciousStewAction();
    }
    return null;
  }
}

final class SetOnFire extends PotatoEntityHitAction {
  final int ticks;
  const SetOnFire(this.ticks);
}

final class PotionEffectAction extends PotatoEntityHitAction {
  final String effect;

  /// 1-based level (`amplifier = level - 1`).
  final int level;
  final int ticks;
  final bool recoverable;

  const PotionEffectAction({required this.effect, required this.level, required this.ticks, required this.recoverable});
}

/// One `FoodProperties.PossibleEffect`: an effect instance json and its probability.
final class FoodEffect {
  final Map<String, Object?> effect;
  final double probability;
  const FoodEffect({required this.effect, required this.probability});
}

final class FoodEffectsAction extends PotatoEntityHitAction {
  final List<FoodEffect> effects;
  final bool recoverable;
  const FoodEffectsAction({required this.effects, required this.recoverable});
}

final class ChorusTeleport extends PotatoEntityHitAction {
  final double teleportDiameter;
  const ChorusTeleport(this.teleportDiameter);
}

final class CureZombieVillager extends PotatoEntityHitAction {
  const CureZombieVillager();
}

final class SuspiciousStewAction extends PotatoEntityHitAction {
  const SuspiciousStewAction();
}

/// `PotatoProjectileBlockHitAction`s.
sealed class PotatoBlockHitAction {
  const PotatoBlockHitAction();

  static PotatoBlockHitAction? fromJson(Object? json) {
    if (json is! Map) return null;
    return switch (json['type']) {
      'create:plant_crop' => PlantCrop(json['block'] as String),
      'create:place_block_on_ground' => PlaceBlockOnGround(json['block'] as String),
      _ => null,
    };
  }
}

final class PlantCrop extends PotatoBlockHitAction {
  final String cropBlock;
  const PlantCrop(this.cropBlock);
}

final class PlaceBlockOnGround extends PotatoBlockHitAction {
  final String block;
  const PlaceBlockOnGround(this.block);
}

/// A `PotatoCannonProjectileType` (see `data/create/create/potato_projectile/type`).
final class PotatoType {
  final String key;

  /// Item keys (`minecraft:potato`) and `#tag`s that count as this projectile.
  final List<String> items;
  final int reloadTicks;
  final int damage;
  final int split;
  final double knockback;
  final double drag;
  final double velocityMultiplier;
  final double gravityMultiplier;
  final double soundPitch;
  final bool sticky;

  /// The `drop_stack` item key (e.g. `minecraft:bowl`), or null for an empty stack.
  final String? dropStack;
  final PotatoEntityHitAction? preEntityHit;
  final PotatoEntityHitAction? onEntityHit;
  final PotatoBlockHitAction? onBlockHit;

  /// The `render_mode` `type` (`create:tumble`, `create:toward_motion`, `create:billboard`).
  final String renderMode;

  const PotatoType({
    required this.key,
    required this.items,
    this.reloadTicks = 10,
    this.damage = 1,
    this.split = 1,
    this.knockback = 1,
    this.drag = 0.99,
    this.velocityMultiplier = 1,
    this.gravityMultiplier = 1,
    this.soundPitch = 1,
    this.sticky = false,
    this.dropStack,
    this.preEntityHit,
    this.onEntityHit,
    this.onBlockHit,
    this.renderMode = 'create:billboard',
  });

  /// Parses the json of a type file (the codec defaults of Java are the defaults here).
  factory PotatoType.fromJson(String key, String rawJson) {
    final m = jsonDecode(rawJson) as Map<String, dynamic>;
    final items = m['items'];
    final dropStack = m['drop_stack'];
    return PotatoType(
      key: key,
      items: switch (items) {
        final String s => [s],
        final List<Object?> l => [for (final i in l) i as String],
        _ => const [],
      },
      reloadTicks: (m['reload_ticks'] as num?)?.toInt() ?? 10,
      damage: (m['damage'] as num?)?.toInt() ?? 1,
      split: (m['split'] as num?)?.toInt() ?? 1,
      knockback: _f32((m['knockback'] as num?)?.toDouble() ?? 1),
      drag: _f32((m['drag'] as num?)?.toDouble() ?? 0.99),
      velocityMultiplier: _f32((m['velocity_multiplier'] as num?)?.toDouble() ?? 1),
      gravityMultiplier: _f32((m['gravity_multiplier'] as num?)?.toDouble() ?? 1),
      soundPitch: _f32((m['sound_pitch'] as num?)?.toDouble() ?? 1),
      sticky: m['sticky'] as bool? ?? false,
      dropStack: dropStack is Map ? dropStack['id'] as String? : (dropStack is String ? dropStack : null),
      preEntityHit: PotatoEntityHitAction.fromJson(m['pre_entity_hit']),
      onEntityHit: PotatoEntityHitAction.fromJson(m['on_entity_hit']),
      onBlockHit: PotatoBlockHitAction.fromJson(m['on_block_hit']),
      renderMode: ((m['render_mode'] as Map?)?['type'] as String?) ?? 'create:billboard',
    );
  }

  @override
  String toString() => 'PotatoType($key)';
}

final Float32List _f32buf = Float32List(1);

/// Rounds a double to float32 precision (Java stores these values as `float`).
double _f32(double v) {
  _f32buf[0] = v;
  return _f32buf[0];
}

/// All projectile types, in registry order; look-up by item.
final class PotatoTypes {
  final List<PotatoType> types;

  PotatoTypes(this.types);

  /// `PotatoCannonProjectileType.getTypeForItem`: the first type listing [itemKey]
  /// (`minecraft:` prefix required) either directly or through a tag [tagMembers] resolves.
  PotatoType? forItem(String itemKey, {bool Function(String tag, String itemKey)? inTag}) {
    for (final t in types) {
      for (final i in t.items) {
        if (i.startsWith('#')) {
          if (inTag != null && inTag(i.substring(1), itemKey)) return t;
        } else if (i == itemKey) {
          return t;
        }
      }
    }
    return null;
  }

  PotatoType? byKey(String key) {
    for (final t in types) {
      if (t.key == key) return t;
    }
    return null;
  }

  PotatoType get fallback => byKey('fallback') ?? const PotatoType(key: 'fallback', items: [], damage: 0);
}

// ---------------------------------------------------------------------------------
// Shot maths (PotatoCannonItem.use)
// ---------------------------------------------------------------------------------

/// One projectile of a shot.
final class PotatoShot {
  final V3 motion;

  /// `recoveryChance` is zeroed for every projectile but the first of a split shot.
  final bool keepsRecovery;
  const PotatoShot(this.motion, this.keepsRecovery);
}

/// The outcome of `use` before anything is spawned.
final class PotatoVolley {
  final List<PotatoShot> shots;
  final double soundPitch;
  const PotatoVolley(this.shots, this.soundPitch);
}

abstract final class PotatoMath {
  /// Computes the motion of every projectile the way `PotatoCannonItem.use` does.
  /// [lookVec] is `player.getLookAngle()`, [correction] the barrel correction vector,
  /// [nextFloat] `level.getRandom().nextFloat()` (called in the same order as Java).
  static PotatoVolley volley({
    required PotatoType type,
    required V3 lookVec,
    required V3 correction,
    required double Function() nextFloat,
  }) {
    final motion = lookVec.vplus(correction).vnorm.vscale(2).vscale(type.velocityMultiplier);
    final soundPitch = type.soundPitch + (nextFloat() - .5) / 4;
    final spray = type.split > 1;
    final sprayBase = rotateVec((0.0, 0.1, 0.0), 360 * nextFloat(), Ax.z);
    final sprayChange = 360 / type.split;
    final shots = <PotatoShot>[];
    for (var i = 0; i < type.split; i++) {
      var splitMotion = motion;
      if (spray) {
        final imperfection = 40 * (nextFloat() - 0.5);
        final sprayOffset = rotateVec(sprayBase, i * sprayChange + imperfection, Ax.z);
        splitMotion = splitMotion.vplus(lookAtVec(sprayOffset, motion));
      }
      shots.add(PotatoShot(splitMotion, i == 0));
    }
    return PotatoVolley(shots, soundPitch);
  }

  /// The correction vector of `use`: barrel at `(-.05, 0, 0)` minus the eye position.
  static V3 correction({
    required V3 eyePos,
    required double yRotDeg,
    required double xRotDeg,
    required bool mainHand,
    required bool rightArmMain,
  }) {
    final b = gunBarrelVec(
      eyePos: eyePos,
      yRotDeg: yRotDeg,
      xRotDeg: xRotDeg,
      mainHand: mainHand,
      rightArmMain: rightArmMain,
      rightHandForward: (-.05, 0, 0),
    );
    return b.vminus(eyePos);
  }

  /// `PotatoCannonItem.use` barrel position (`(.75, -.15, 1.5)`).
  static V3 barrel({
    required V3 eyePos,
    required double yRotDeg,
    required double xRotDeg,
    required bool mainHand,
    required bool rightArmMain,
  }) => gunBarrelVec(
    eyePos: eyePos,
    yRotDeg: yRotDeg,
    xRotDeg: xRotDeg,
    mainHand: mainHand,
    rightArmMain: rightArmMain,
    rightHandForward: (.75, -.15, 1.5),
  );

  /// The recovery chance from the cannon's `create:potato_recovery` level.
  static double recoveryChance(int level) => level > 0 ? .125 + level * .125 : 0;

  /// `onHitEntity`: damage.
  static double damage(PotatoType type, double additionalDamageMult) => type.damage * additionalDamageMult;

  /// `onHitEntity`: knockback.
  static double knockback(PotatoType type, double additionalKnockback) => type.knockback + additionalKnockback;

  /// The tooltip / Power enchantment: `additionalDamageMult = 1 + power * .2`.
  static double powerDamageMult(int power) => 1 + power * .2;

  /// Punch: `additionalKnockback = punch * .5`.
  static double punchKnockback(int punch) => punch * .5;
}

/// Free flight of a projectile (the non-stuck branch of `PotatoProjectileEntity.tick`).
final class PotatoFlight {
  V3 pos;
  V3 motion;
  final PotatoType type;
  int tickCount = 0;

  /// Stuck state (`setStuckEntity`).
  bool stuck = false;
  V3 stuckOffset = vzero;
  double stuckFallSpeed = 0;

  PotatoFlight(this.pos, this.motion, this.type);

  /// Applies gravity and drag and returns the displacement to test for hits this tick
  /// (`setDeltaMovement(delta.add(0, -0.05 * g, 0).vscale(drag))` then the hurting
  /// projectile moves by the new delta, inertia 1).
  V3 stepFree() {
    motion = motion.vplus((0.0, -0.05 * type.gravityMultiplier, 0.0)).vscale(type.drag);
    return motion;
  }

  /// The stuck branch: returns the new offset from the stuck entity, or `null` when the
  /// projectile should pop (`getY() < stuckEntity.getY() - 0.1`).
  V3? stepStuck(V3 stuckEntityPos) {
    if (pos.$2 < stuckEntityPos.$2 - 0.1) return null;
    stuckFallSpeed += 0.007 * type.gravityMultiplier;
    stuckOffset = (stuckOffset.$1, stuckOffset.$2 - stuckFallSpeed, stuckOffset.$3);
    return stuckEntityPos.vplus(stuckOffset);
  }

  void stickTo(V3 entityPos) {
    stuck = true;
    stuckOffset = pos.vminus(entityPos);
    stuckFallSpeed = 0;
    motion = vzero;
  }
}

/// `LivingEntity.knockback(strength * 0.6, -appliedMotion.x, -appliedMotion.z)` where
/// `appliedMotion` is the projectile's horizontal motion, normalised. Returns the target's new
/// velocity, or `null` when nothing is applied (no horizontal motion, or resistance leaves no strength).
V3? knockbackVelocity({
  required double strength,
  required V3 projectileMotion,
  required V3 current,
  required bool onGround,
  double knockbackResistance = 0,
}) {
  final horizontal = (projectileMotion.$1, 0.0, projectileMotion.$3);
  if (horizontal.vlenSqr <= 0) return null;
  final applied = horizontal.vnorm;
  return knockbackResult(
    strength: strength * 0.6,
    x: -applied.$1,
    z: -applied.$3,
    current: current,
    onGround: onGround,
    knockbackResistance: knockbackResistance,
  );
}
