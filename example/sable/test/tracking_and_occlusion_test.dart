// Tracking points, water occlusion and the plain config: the remaining pure
// pieces of the sub-level model.
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('tracking points', () {
    test('save and load round trip', () {
      final store = TrackingPointStore();
      store.setTrackingPoint(
        '00000000-0000-4000-8000-000000000001',
        TrackingPoint(
          true,
          '00000000-0000-4000-8000-000000000002',
          const GlobalSavedSubLevelPointer(1, 2, 3, 4),
          Vector3d(1.5, 2.5, 3.5),
          Vector3d(9, 9, 9),
        ),
      );

      final restored = TrackingPointStore.load(store.save());
      final point = restored.getTrackingPoint('00000000-0000-4000-8000-000000000001')!;
      expect(point.inSubLevel, isTrue);
      expect(point.subLevelId, '00000000-0000-4000-8000-000000000002');
      expect(point.lastSavedSubLevelPointer, const GlobalSavedSubLevelPointer(1, 2, 3, 4));
      expect(point.point, isA<Vector3d>());
      expect(point.point.x, 1.5);
      expect(point.globalPlaceholderPosition!.z, 9);
    });

    test('a world point resolves to itself', () {
      final store = TrackingPointStore();
      store.setTrackingPoint('p', TrackingPoint.inWorld(Vector3d(1, 2, 3)));
      final taken = store.take('p')!;
      expect(taken.position.x, 1);
      expect(taken.subLevelId, isNull);
      expect(store.getTrackingPoint('p'), isNotNull);
    });

    test('a live sub-level transforms the local anchor', () {
      final store = TrackingPointStore();
      store.setTrackingPoint(
        'p',
        TrackingPoint(true, 's', null, Vector3d(1, 0, 0), Vector3d(0, 0, 0)),
      );

      final pose = Pose3d()..position().set(100, 0, 0);
      final taken = store.take('p', containing: (_) => (pose: pose, id: 's'))!;
      expect(taken.position.x, 101);
      expect(taken.subLevelId, 's');
      expect(taken.localAnchor!.x, 1);
    });

    test('a holding sub-level resolves without a live one', () {
      final store = TrackingPointStore();
      store.setTrackingPoint(
        'p',
        TrackingPoint(true, 's', null, Vector3d(0, 1, 0), null),
      );

      final data = SubLevelData(
        's',
        BoundingBox3d.full(0, 0, 0, 1, 1, 1),
        Pose3d()..position().set(0, 50, 0),
        const [],
        const {},
      );
      final taken = store.take('p', holdingSubLevel: (_) => HoldingSubLevel(data, null))!;
      expect(taken.position.y, 51);
      expect(taken.subLevelId, 's');
    });

    test('a removed point is gone', () {
      final store = TrackingPointStore();
      store.setTrackingPoint('p', TrackingPoint.inWorld(Vector3d()));
      expect(store.take('p', remove: true), isNotNull);
      expect(store.take('p'), isNull);
    });

    test('generated points use the player position in local space', () {
      final store = TrackingPointStore();
      final player = FakePlayer('u', (10, 20, 30));
      final pose = Pose3d()..position().set(5, 20, 30);

      final key = store.generateTrackingPoint(
        player,
        subLevelId: 's',
        pose: pose,
        pointer: const GlobalSavedSubLevelPointer(0, 0, 0, 0),
      );
      expect(key, 'u');
      final point = store.getTrackingPoint('u')!;
      expect(point.point.x, 5);
      expect(point.globalPlaceholderPosition, isNull);
    });
  });

  group('water occlusion', () {
    test('a point inside a region is occluded, through the sub-level pose', () {
      final volume = BoundedBitVolume3i(0, 0, 0, 1, 1, 1);
      volume.setOccupied(1, 1, 1, true);

      final subLevelPose = Pose3d()..position().set(100, 0, 0);
      final lookup = _Lookup(subLevelPose);
      final container = ServerWaterOcclusionContainer('minecraft:overworld', lookup, poseOf: (s) => (s as Pose3d));
      container.addRegion(volume);

      // The region's min block is local (0,0,0); the sub-level sits at x=100,
      // so world x=101 is local x=1.
      expect(container.isOccluded((101.5, 1.5, 1.5)), isTrue);
      expect(container.isOccluded((100.5, 1.5, 1.5)), isFalse);
    });

    test('markDirty touches neighbouring regions', () {
      final volume = BoundedBitVolume3i(0, 0, 0, 2, 2, 2);
      volume.setOccupied(1, 1, 1, true);
      final container = ServerWaterOcclusionContainer('minecraft:overworld', _Lookup(null));
      final region = container.addRegion(volume);

      container.markDirty((2, 1, 1));
      expect(region.isDirty(), isTrue);
      region.clearDirty();
      container.markDirty((9, 9, 9));
      expect(region.isDirty(), isFalse);
    });
  });

  group('config', () {
    test('defaults match the Java config', () {
      final config = SableConfig();
      expect(config.subLevelSplitting, isTrue);
      expect(config.subLevelTrackingRange, 320.0);
      expect(config.subLevelRemoveMin, -10000.0);
      expect(config.subLevelRemoveMax, 100000.0);
      expect(config.velocityRetainedOnLoad, 0.9);
      expect(config.subLevelPunchCooldownTicks, 3);
    });

    test('fromMap reads and clamps', () {
      final config = SableConfig.fromMap({
        'sub_level_splitting': false,
        'sub_level_velocity_retained_on_load': 5.0,
        'sub_level_splitting_heatmap_steps': 0,
        'sub_level_remove_min': -5,
      });
      expect(config.subLevelSplitting, isFalse);
      expect(config.velocityRetainedOnLoad, 1.0);
      expect(config.subLevelSplittingHeatmapSteps, 1);
      expect(config.subLevelRemoveMin, -5.0);
    });

    test('toMap has every key', () {
      final map = SableConfig().toMap();
      expect(map.length, 14);
      expect(map['attempt_udp_networking'], isTrue);
    });
  });
}

final class _Lookup implements SubLevelLookup {
  final Pose3d? pose;

  _Lookup(this.pose);

  @override
  Object? containing(String dimensionId, (double, double, double) position) => pose;

  @override
  Object? trackingSubLevel(SablePlayer player) => pose;
}
