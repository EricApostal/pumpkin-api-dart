// `MassTracker` / `MergedMassTracker`: the mass, centre of mass and inertia
// tensor of a sub-level, built from its plot bounds and updated block by block.
//
// Java: `sable/common/.../api/physics/mass/MassTracker.java` and
// `MergedMassTracker.java`. The per-block inputs (mass, inertia, centre) are
// injected through the static hooks on [MassTracker], so these tests also pin
// the defaults the plugin replaces.
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A contraption with a fixed pose and mass, mounted on a sub-level.
final class FakeContraption implements KinematicContraption {
  final Vector3d position;
  final Quaterniond orientation;
  final MassTracker tracker;

  FakeContraption(this.position, this.orientation, this.tracker);

  @override
  void sable$getLocalBounds(BoundingBox3i bounds) =>
      bounds.setFrom(BoundingBox3i.values(0, 0, 0, 0, 0, 0));

  @override
  Pose3d sable$getLocalPose(Pose3d dest, double partialTick) => dest
    ..position().setFrom(position)
    ..orientation().setFrom(orientation);

  @override
  Object sable$blockGetter() => throw UnimplementedError();

  @override
  MassData sable$getMassTracker() => tracker;

  @override
  Vector3d sable$getPosition(double partialTick) => position;

  @override
  Quaterniond sable$getOrientation(double partialTick) => orientation;

  @override
  Map<(int, int, int), Object> sable$liftProviders() => const {};

  @override
  bool sable$shouldCollide() => false;

  @override
  bool sable$isValid() => true;
}

/// A sub-level of a fresh container whose plot holds [blocks] at plot-local
/// coordinates.
ServerSubLevel _subLevelWith(Map<(int, int, int), String> blocks) {
  SubLevelContainer.clearAll();
  final level = FakeLevel();
  final host = FakeChunkHost(level);
  final container = ServerSubLevelContainer(
    level,
    host,
    3,
    4,
    SubLevelContainer.defaultOrigin,
    SubLevelContainer.defaultOrigin,
  );
  SubLevelContainer.register(container);
  final subLevel = container.allocateSubLevel(
    '00000000-0000-0000-0000-000000000001',
    0,
    0,
    Pose3d(),
  ) as ServerSubLevel;

  final plot = subLevel.getPlot();
  final chunk = plot.toGlobal((0, 0));
  plot.newEmptyChunk(chunk);
  blocks.forEach((pos, state) {
    host.setBlock((chunk.$1 << 4) + pos.$1, pos.$2, (chunk.$2 << 4) + pos.$3, state);
  });
  // `PlotChunkHolder` caches its bounding box from the scan at creation time,
  // so the blocks placed above only reach the plot bounds after a rescan.
  for (final holder in plot.getLoadedChunks()) {
    holder.buildBoundingBox();
  }
  plot.updateBoundingBox();
  return subLevel;
}

void main() {
  tearDown(() {
    SubLevelContainer.clearAll();
    MassTracker.blockMass = (_, _) => 1.0;
    MassTracker.blockInertia = (_, _) => null;
    MassTracker.isSolid = (_, state) => state != 'minecraft:air';
    MassTracker.blockCenterOfMass = (_, _) => Vector3d(0.5, 0.5, 0.5);
    ServerSubLevel.massTrackerFactory = MassTracker.build;
  });

  group('MassTracker', () {
    test('two blocks weigh 2 kg and put the centre of mass between them', () {
      final subLevel = _subLevelWith({
        (0, 0, 0): 'minecraft:stone',
        (2, 0, 0): 'minecraft:stone',
      });

      final tracker = MassTracker.build(subLevel);

      expect(tracker.isInvalid(), isFalse);
      expect(tracker.getMass(), closeTo(2.0, 1e-9));
      expect(tracker.getInverseMass(), closeTo(0.5, 1e-9));

      final bounds = subLevel.getPlot().getBoundingBox();
      final center = tracker.getCenterOfMass();
      // Block centres are at (x + 0.5, y + 0.5, z + 0.5); the plot origin is
      // the yard's distant origin, so compare relative to the bounds.
      expect(center.x, closeTo(bounds.minX + 1.5, 1e-9));
      expect(center.y, closeTo(0.5, 1e-9));
      expect(center.z, closeTo(bounds.minZ + 0.5, 1e-9));
    });

    test('the inertia tensor is the cube term plus the parallel-axis term', () {
      final subLevel = _subLevelWith({
        (0, 0, 0): 'minecraft:stone',
        (2, 0, 0): 'minecraft:stone',
      });

      final tracker = MassTracker.build(subLevel);
      final inertia = tracker.getInertiaTensor();

      // Each block: a 1 kg cube (I = m/6 on the diagonal) at r = (±1, 0, 0).
      // `m(|r|²·I − r·rᵀ)` contributes nothing to x and 1 to y and z.
      expect(inertia.m00, closeTo(2.0 / 6.0, 1e-9));
      expect(inertia.m11, closeTo(2.0 / 6.0 + 2.0, 1e-9));
      expect(inertia.m22, closeTo(2.0 / 6.0 + 2.0, 1e-9));
      expect(inertia.m01, closeTo(0.0, 1e-12));

      // The inverse is the true inverse of the tensor.
      final inverse = tracker.getInverseInertiaTensor();
      final product = Matrix3d.copy(inertia)..mulLocal(inverse);
      expect(product.m00, closeTo(1.0, 1e-9));
      expect(product.m11, closeTo(1.0, 1e-9));
      expect(product.m22, closeTo(1.0, 1e-9));
      expect(product.m01, closeTo(0.0, 1e-9));
    });

    test('a block change moves the centre of mass', () {
      final subLevel = _subLevelWith({(0, 0, 0): 'minecraft:stone'});
      final tracker = MassTracker.build(subLevel);
      final bounds = subLevel.getPlot().getBoundingBox();
      expect(tracker.getCenterOfMass().x, closeTo(bounds.minX + 0.5, 1e-9));

      tracker.addBlockMass('minecraft:stone', (bounds.minX + 4, 0, 0), 1.0, null);

      expect(tracker.getMass(), closeTo(2.0, 1e-9));
      expect(tracker.getCenterOfMass().x, closeTo(bounds.minX + 2.5, 1e-9));
    });

    test('removing the last block makes the tracker invalid', () {
      final subLevel = _subLevelWith({(0, 0, 0): 'minecraft:stone'});
      final tracker = MassTracker.build(subLevel);
      final bounds = subLevel.getPlot().getBoundingBox();

      tracker.addBlockMass('minecraft:stone', (bounds.minX, 0, 0), -1.0, null);

      expect(tracker.getMass(), closeTo(0.0, 1e-12));
      expect(tracker.isInvalid(), isTrue);
      expect(() => tracker.getCenterOfMass(), throwsStateError);
    });

    test('an empty plot yields an invalid tracker', () {
      final subLevel = _subLevelWith({});
      final tracker = MassTracker.build(subLevel);

      expect(tracker.isInvalid(), isTrue);
      expect(tracker.getMass(), 0.0);
    });

    test('the block hooks supply mass and inertia', () {
      MassTracker.blockMass = (_, state) => state == 'minecraft:iron_block' ? 4.0 : 1.0;
      MassTracker.blockInertia = (_, state) =>
          state == 'minecraft:iron_block' ? (0.5, 0.5, 0.5) : null;
      final subLevel = _subLevelWith({(0, 0, 0): 'minecraft:iron_block'});

      final tracker = MassTracker.build(subLevel);

      expect(tracker.getMass(), closeTo(4.0, 1e-9));
      // `sable:inertia` is used as the diagonal, scaled by the mass.
      expect(tracker.getInertiaTensor().m00, closeTo(0.5 * 4.0, 1e-9));
    });
  });

  group('MergedMassTracker', () {
    test('buildMassTracker installs a merged tracker by default', () {
      final subLevel = _subLevelWith({(0, 0, 0): 'minecraft:stone'});

      // The default factory is installed, so the first assembled sub-level no
      // longer throws.
      expect(() => subLevel.buildMassTracker(), returnsNormally);
      expect(subLevel.massTracker, isA<MergedMassTracker>());
      expect(subLevel.getSelfMassTracker(), isA<MassTracker>());
      // The merged tracker is filled in by the first update, which the physics
      // system runs before every substep.
      expect(subLevel.updateMergedMassData(0.0), isTrue);
      expect(subLevel.getMassTracker().getMass(), closeTo(1.0, 1e-9));
    });

    test('a mounted contraption is merged into the mass and the inertia', () {
      final subLevel = _subLevelWith({(0, 0, 0): 'minecraft:stone'});
      subLevel.buildMassTracker();
      final merged = subLevel.massTracker! as MergedMassTracker;
      final bounds = subLevel.getPlot().getBoundingBox();

      final contraptionTracker = MassTracker()
        ..addBlockMass('minecraft:stone', (0, 0, 0), 1.0, null);
      subLevel.getPlot().addContraption(
        FakeContraption(
          Vector3d(bounds.minX + 2.5, 0.5, bounds.minZ + 0.5),
          Quaterniond(),
          contraptionTracker,
        ),
      );

      expect(merged.update(0.0), isTrue);

      expect(merged.getMass(), closeTo(2.0, 1e-9));
      // The two 1 kg masses sit at x = minX + 0.5 and minX + 2.5.
      expect(merged.getCenterOfMass().x, closeTo(bounds.minX + 1.5, 1e-9));
      expect(merged.getInertiaTensor().m11, closeTo(2.0 / 6.0 + 2.0, 1e-9));

      // No contraption and no block change: the properties did not move.
      subLevel.getPlot().removeContraption(subLevel.getPlot().getContraptions().first);
      expect(merged.update(0.0), isTrue);
      expect(merged.getMass(), closeTo(1.0, 1e-9));
      expect(merged.update(0.0), isFalse);
    });

    test('a sub-level without blocks never reports a merged mass', () {
      final subLevel = _subLevelWith({});
      subLevel.buildMassTracker();
      final merged = subLevel.massTracker! as MergedMassTracker;

      expect(merged.update(0.0), isFalse);
      expect(merged.isInvalid(), isTrue);
    });
  });
}
