import 'package:create/src/equipment/model/dir.dart';
import 'package:create/src/equipment/model/knockback.dart';
import 'package:create/src/equipment/model/vec.dart';
import 'package:create/src/equipment/potato/potato_model.dart';
import 'package:create/src/manifest/manifest.dart';
import 'package:test/test.dart';

void main() {
  final types = PotatoTypes([for (final t in kPotatoProjectileTypes) PotatoType.fromJson(t.key, t.rawJson)]);

  test('all 25 types parse', () {
    expect(types.types.length, 25);
    final potato = types.byKey('potato')!;
    expect(potato.damage, 5);
    expect(potato.reloadTicks, 15);
    expect(potato.velocityMultiplier, 1.25);
    expect(potato.knockback, 1.5);
    expect(potato.onBlockHit, isA<PlantCrop>());
    expect((potato.onBlockHit as PlantCrop).cropBlock, 'minecraft:potatoes');
    expect(potato.drag, closeTo(0.99, 1e-6));
    final fallback = types.fallback;
    expect(fallback.damage, 0);
    expect(fallback.items, isEmpty);
  });

  test('lookup by item', () {
    expect(types.forItem('minecraft:potato')!.key, 'potato');
    expect(types.forItem('minecraft:cod')!.key, 'fish');
    expect(types.forItem('minecraft:sweet_berries')!.split, 3);
    expect(types.forItem('minecraft:stone'), isNull);
  });

  test('hit actions', () {
    expect(types.byKey('baked_potato')!.preEntityHit, isA<SetOnFire>());
    expect((types.byKey('blaze_cake')!.preEntityHit as SetOnFire).ticks, 240);
    final poison = types.byKey('poison_potato')!.onEntityHit as PotionEffectAction;
    expect(poison.effect, 'minecraft:poison');
    expect(poison.ticks, 160);
    expect(poison.recoverable, isTrue);
    expect(types.byKey('chorus_fruit')!.onEntityHit, isA<ChorusTeleport>());
    expect(types.byKey('golden_apple')!.onEntityHit, isA<CureZombieVillager>());
    expect(types.byKey('suspicious_stew')!.onEntityHit, isA<SuspiciousStewAction>());
    final egap = types.byKey('enchanted_golden_apple')!.onEntityHit as FoodEffectsAction;
    expect(egap.effects.length, 4);
    expect(types.byKey('melon_block')!.onBlockHit, isA<PlaceBlockOnGround>());
    expect(types.byKey('pumpkin_pie')!.sticky, isTrue);
    expect(types.byKey('suspicious_stew')!.dropStack, 'minecraft:bowl');
  });

  test('single shot motion', () {
    final potato = types.byKey('potato')!;
    final v = PotatoMath.volley(
      type: potato,
      lookVec: (0, 0, 1),
      correction: (0, 0, 0),
      nextFloat: () => 0.5,
    );
    expect(v.shots.length, 1);
    // normalize * 2 * 1.25
    expect(v.shots[0].motion.$3, closeTo(2.5, 1e-9));
    expect(v.soundPitch, closeTo(1.0, 1e-9));
  });

  test('sweet berries spray in three directions', () {
    final berry = types.byKey('sweet_berry')!;
    var i = 0;
    final seq = [0.5, 0.25, 0.5, 0.5, 0.5];
    final v = PotatoMath.volley(
      type: berry,
      lookVec: (0, 0, 1),
      correction: (0, 0, 0),
      nextFloat: () => seq[i++ % seq.length],
    );
    expect(v.shots.length, 3);
    expect(v.shots.first.keepsRecovery, isTrue);
    expect(v.shots.skip(1).every((s) => !s.keepsRecovery), isTrue);
    // spray offsets are perpendicular to the motion: the z component is unchanged
    for (final s in v.shots) {
      expect(s.motion.$3, closeTo(2.1, 1e-6));
    }
    // all three differ
    expect(v.shots.map((s) => s.motion).toSet().length, 3);
  });

  test('flight: gravity and drag', () {
    final f = PotatoFlight((0, 0, 0), (0, 0, 2), types.byKey('potato')!);
    final step = f.stepFree();
    expect(step.$2, closeTo(-0.05 * 0.99, 1e-6));
    expect(step.$3, closeTo(2 * 0.99, 1e-6));
  });

  test('stuck projectile falls then pops', () {
    final f = PotatoFlight((0, 1.0, 0), (0, 0, 0), types.byKey('cake')!);
    f.stickTo((0, 0, 0));
    expect(f.stuck, isTrue);
    final p = f.stepStuck((0, 0, 0));
    expect(p!.$2, closeTo(1.0 - 0.007, 1e-9));
    f.pos = (0, -1, 0);
    expect(f.stepStuck((0, 0, 0)), isNull);
  });

  test('recovery chance and enchantment maths', () {
    expect(PotatoMath.recoveryChance(0), 0);
    expect(PotatoMath.recoveryChance(1), 0.25);
    expect(PotatoMath.recoveryChance(3), 0.5);
    expect(PotatoMath.powerDamageMult(5), closeTo(2.0, 1e-9));
    expect(PotatoMath.damage(types.byKey('potato')!, 1.4), closeTo(7, 1e-9));
  });

  test('knockback velocity', () {
    final k = knockbackVelocity(
      strength: 1.5,
      projectileMotion: (0, 0, 2),
      current: (0, 0, 0),
      onGround: true,
    )!;
    expect(k.$3, closeTo(0.9, 1e-9));
    expect(k.$2, closeTo(0.4, 1e-9));
    expect(knockbackVelocity(strength: 1, projectileMotion: (0, 1, 0), current: (0, 0, 0), onGround: false), isNull);
    // existing motion halves
    final h = knockbackVelocity(strength: 1, projectileMotion: (1, 0, 0), current: (2, 1, 0), onGround: false)!;
    expect(h.$1, closeTo(1 + 0.6, 1e-9));
    expect(h.$2, 1);
    expect(knockbackResult(strength: 1, x: 0, z: 1, current: (0, 0, 0), onGround: true, knockbackResistance: 1), isNull);
  });

  test('vector helpers', () {
    final r = rotateVec((0, 0.1, 0), 90, Ax.z);
    expect(r.$1, closeTo(-0.1, 1e-9));
    final l = lookAtVec((1, 0, 0), (0, 0, 1));
    expect(l.vlen, closeTo(1, 1e-9));
    final look = lookVector(0, 0);
    expect(look.$3, closeTo(1, 1e-9));
  });
}
