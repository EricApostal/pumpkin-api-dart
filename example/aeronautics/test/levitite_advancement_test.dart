// The advancement a crystallised levitite blend awards nearby.
//
// Java: `LevititeCrystalPropagationContext.onCrystallize` (`LevititeCrystalPropagationContext.java:36`)
// and `LevititeSoulCrystalPropagationContext.onCrystallize`
// (`LevititeSoulCrystalPropagationContext.java:36`) both end with
// `AeroAdvancements.X.awardToNearby(pos, level)`. The crystallisation is pure, so the world it
// writes is a fake that records the award; the host side of that interface
// (`_LevititeWorld.awardAdvancementNearby`) forwards it to `AeroRuntime.awardNearby`.
import 'dart:math' as math;

import 'package:aeronautics/aeronautics.dart';
import 'package:create/src/common/pos.dart' show Pos;
import 'package:test/test.dart';

/// A world of two maps that records the advancements awarded next to a crystal.
final class RecordingLevititeWorld implements LevititeWorld {
  RecordingLevititeWorld({Map<Pos, String>? blocks, Map<Pos, String>? fluids})
    : blocks = blocks ?? {},
      fluids = fluids ?? {};

  final Map<Pos, String> blocks;
  final Map<Pos, String> fluids;

  /// The `(advancement, pos)` pairs the crystallisation awarded.
  final List<(String, Pos)> awards = [];

  @override
  String get id => 'world';

  @override
  final math.Random random = math.Random(1);

  @override
  String blockKeyAt(Pos pos) => blocks[pos] ?? 'minecraft:air';

  @override
  String fluidKeyAt(Pos pos) => fluids[pos] ?? 'minecraft:empty';

  @override
  void setBlock(Pos pos, String blockKey) => blocks[pos] = blockKey;

  @override
  bool blockHasTag(Pos pos, String tag) => false;

  @override
  String? blockPropertyAt(Pos pos, String name) => null;

  @override
  void playSound(String soundKey, Pos pos, {double volume = 1, double pitch = 1}) {}

  @override
  void spawnParticles(String particle, Pos pos, int count) {}

  @override
  void awardAdvancementNearby(String advancement, Pos pos) => awards.add((advancement, pos));

  @override
  void destroyBlock(Pos pos) => blocks[pos] = 'minecraft:air';

  @override
  void markDirty() {}
}

/// Rolls 0 every time, so `shouldCrystallize` (`random < attempts / maxAttempts`) succeeds.
final class _CertainRandom implements math.Random {
  @override
  bool nextBool() => true;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}

void main() {
  const pos = (4, 65, -3);

  setUp(LevititeCrystallizerManager.clear);
  tearDown(LevititeCrystallizerManager.clear);

  test('a standard crystallisation awards UNIDENTIFIED_FLOATING_OBJECT nearby', () {
    final world = RecordingLevititeWorld(fluids: {pos: levititeBlendFluid});

    crystallizeLevititeBlend(world, pos, const StandardCrystalPropagationContext(), world.random);

    expect(world.blockKeyAt(pos), 'aeronautics:levitite');
    expect(world.awards, [('aeronautics:unidentified_floating_object', pos)]);
  });

  test('a soul crystallisation awards NOW_AVAILABLE_IN_PINK nearby', () {
    final world = RecordingLevititeWorld(fluids: {pos: levititeBlendFluid});

    crystallizeLevititeBlend(world, pos, const SoulCrystalPropagationContext(), world.random);

    expect(world.blockKeyAt(pos), 'aeronautics:pearlescent_levitite');
    expect(world.awards, [('aeronautics:now_available_in_pink', pos)]);
  });

  test('a ticker that succeeds awards it on the manager path too', () {
    final world = RecordingLevititeWorld(fluids: {pos: levititeBlendFluid});
    LevititeCrystallizerManager.tickersOf(world.id).add(
      LevititeBlendTicker(
        pos,
        const StandardCrystalPropagationContext(),
        age: 0,
        attempts: 1,
        isDormant: true,
        requiresCatalyst: false,
      ),
    );

    LevititeCrystallizerManager.tick(world, _CertainRandom());

    expect(world.awards, [('aeronautics:unidentified_floating_object', pos)]);
  });
}