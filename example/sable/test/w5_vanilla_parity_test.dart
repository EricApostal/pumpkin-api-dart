// W5: vanilla-integration parity. The mixin inventory and gap list, and the
// behaviour of every ported handler. Runs on the VM: no host bindings.
import 'package:create/src/api/block_state.dart' show BState;
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Records what the handlers ask the world to do.
final class RecordingPort implements VanillaActionPort {
  final Map<(int, int, int), SubLevel> blocks = {};
  final Map<String, SubLevel> positions = {};

  final List<String> calls = [];
  bool air = false;

  @override
  SubLevel? containingAt(Vector3d worldPosition) =>
      positions['${worldPosition.x},${worldPosition.y},${worldPosition.z}'];

  @override
  SubLevel? containingBlock((int, int, int) worldBlock) => blocks[worldBlock];

  @override
  void kick(int entityId, SubLevel subLevel) =>
      calls.add('kick:$entityId:${subLevel.uniqueIdOrNull}');

  @override
  void teleport(int entityId, Vector3d worldPosition) => calls.add(
    'teleport:$entityId:${worldPosition.x},${worldPosition.y},${worldPosition.z}',
  );

  @override
  void destroy(int entityId) => calls.add('destroy:$entityId');

  @override
  void playSound(
    Vector3d worldPosition,
    String sound,
    double volume,
    double pitch,
  ) => calls.add('sound:$sound');

  @override
  bool isAir((int, int, int) worldBlock) => air;
}

/// A world for the impact callbacks.
final class RecordingImpactHost implements ImpactHostPort {
  final Map<(int, int, int), BState> states = {};
  final Map<(int, int, int), bool> liquids = {};
  final List<String> calls = [];

  @override
  BState stateAt((int, int, int) plotBlock) => states[plotBlock] ?? BState.air;

  @override
  void destroyBlock((int, int, int) plotBlock, {required bool dropLoot}) =>
      calls.add('destroy:$plotBlock:$dropLoot');

  @override
  void setBlock((int, int, int) plotBlock, BState state) =>
      calls.add('set:$plotBlock:${state.key}');

  @override
  bool isLiquid((int, int, int) plotBlock) => liquids[plotBlock] ?? false;

  @override
  void ringBell((int, int, int) plotBlock, String facing) =>
      calls.add('ring:$plotBlock:$facing');

  @override
  void emptyBeehive((int, int, int) plotBlock) => calls.add('hive:$plotBlock');

  @override
  void spawnPrimedTnt((int, int, int) plotBlock, int fuse) =>
      calls.add('tnt:$plotBlock:$fuse');
}

TestSubLevel makeSubLevel(
  SableLevel level, {
  Vector3d? position,
  Quaterniond? orientation,
  (int, int, int)? boundsMin,
  (int, int, int)? boundsMax,
}) {
  // A sub-level needs a plot container on its level; make one when the test did
  // not register its own.
  if (SubLevelContainer.of(level) == null) {
    SubLevelContainer.register(TestContainer(level, FakeChunkHost(level)));
  }
  final pose = Pose3d.full(
    position ?? Vector3d(),
    orientation ?? Quaterniond(),
    Vector3d(),
    Vector3d(1.0, 1.0, 1.0),
  );
  final subLevel = TestSubLevel(level, 0, 0, pose);
  subLevel.setUniqueId('00000000-0000-4000-8000-000000000001');
  subLevel.updateLastPose();
  if (boundsMin != null && boundsMax != null) {
    subLevel.getPlot().setBoundingBox(
      BoundingBox3i.values(
        boundsMin.$1,
        boundsMin.$2,
        boundsMin.$3,
        boundsMax.$1,
        boundsMax.$2,
        boundsMax.$3,
      ),
    );
  }
  return subLevel;
}

void main() {
  tearDown(SubLevelContainer.clearAll);

  group('mixin inventory', () {
    test('server-side common mixins are all classified', () {
      expect(MixinInventory.commonServerMixins, hasLength(145));
      expect(MixinInventory.commonClientMixins, hasLength(82));
      expect(
        MixinInventory.commonServerMixins.length +
            MixinInventory.commonClientMixins.length,
        227,
        reason: 'the common mixin tree',
      );
    });

    test('mix-interfaces and helpers are accounted for', () {
      expect(MixinInventory.commonMixInterfaces, hasLength(33));
      expect(MixinInventory.commonMixinHelpers, hasLength(15));
    });

    test('neoforge non-Create patches are accounted for', () {
      expect(MixinInventory.neoforgeMixins, hasLength(23));
      expect(MixinInventory.neoforgeSupport, hasLength(19));
      expect(MixinInventory.createCompatibilityFiles, 156);
      expect(MixinInventory.flywheelClientFiles, 19);
    });

    test('paths are unique and every bucket is represented', () {
      final paths = MixinInventory.serverEntries.map((e) => e.path).toList();
      expect(paths.toSet(), hasLength(paths.length));

      for (final bucket in MixinBucket.values) {
        expect(
          MixinInventory.countOf(bucket),
          greaterThan(0),
          reason: bucket.name,
        );
      }
      expect(
        MixinInventory.countOf(MixinBucket.pluginHook) +
            MixinInventory.countOf(MixinBucket.hostFeature) +
            MixinInventory.countOf(MixinBucket.notApplicable),
        MixinInventory.serverEntries.length,
      );
    });

    test('every host-feature entry names a gap that exists', () {
      for (final entry in MixinInventory.serverEntries) {
        if (entry.bucket == MixinBucket.hostFeature) {
          expect(entry.gap, isNotNull, reason: entry.path);
          expect(
            HostGaps.byId(entry.gap!),
            isNotNull,
            reason: '${entry.path} -> ${entry.gap}',
          );
        }
      }
    });

    test('every plugin-hook entry names a hook, and only those do', () {
      for (final entry in MixinInventory.serverEntries) {
        if (entry.bucket == MixinBucket.pluginHook) {
          expect(entry.hook, isNotNull, reason: entry.path);
          expect(entry.hook, isNotEmpty);
          expect(entry.gap, isNull, reason: entry.path);
        } else {
          expect(entry.hook, isNull, reason: entry.path);
        }
      }
    });

    test('no gap is dead: every gap explains at least one patch', () {
      final used = MixinInventory.gapsUsed.keys.toSet();
      for (final gap in HostGaps.all) {
        expect(
          used,
          contains(gap.id),
          reason: 'gap ${gap.id} is not referenced',
        );
      }
      expect(used, hasLength(HostGaps.all.length));
    });

    test('the hook table is not trivially small', () {
      expect(MixinInventory.hooksUsed.length, greaterThanOrEqualTo(15));
      expect(
        MixinInventory.byPath('mixin/entity/projectile/ProjectileMixin.java')
            ?.hook,
        'projectile-launch-event',
      );
      expect(
        MixinInventory.byPath('mixin/explosion/ExplosionMixin.java')?.gap,
        'explosion-ray',
      );
    });
  });

  group('host gaps', () {
    test('ids are unique and the text is not empty', () {
      final ids = HostGaps.all.map((g) => g.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final gap in HostGaps.all) {
        expect(gap.need, isNotEmpty);
        expect(gap.exposure, isNotEmpty);
        expect(
          gap.exposure.toLowerCase(),
          isNot(contains('already available')),
        );
      }
    });

    test('the playability gaps are marked critical', () {
      final critical = HostGaps.atPriority(HostGapPriority.critical)
          .map((g) => g.id)
          .toSet();
      expect(
        critical,
        containsAll([
          'entity-movement-sweep',
          'entity-wire-position',
          'player-move-packet',
          'clip-raycast',
          'chunk-source',
          'chunk-serialization',
        ]),
      );
    });

    test('lookup round-trips', () {
      for (final gap in HostGaps.all) {
        expect(HostGaps.byId(gap.id), same(gap));
      }
      expect(HostGaps.byId('nope'), isNull);
    });
  });

  group('entity tracking rules', () {
    late SableLevel level;
    late TestSubLevel ship;
    late TestSubLevel other;

    setUp(() {
      level = FakeLevel();
      ship = makeSubLevel(level);
      other = makeSubLevel(level)
        ..setUniqueId('00000000-0000-4000-8000-000000000002');
    });

    test('a containing sub-level clears the tracking state', () {
      final result = SubLevelEntityRules.resolve(
        containing: ship,
        vehicleContaining: other,
        vehicleTracking: other,
        currentTracking: ship,
      );
      expect(result.tracking, isNull);
      expect(result.containing, ship);
      expect(result.isTracking, isFalse);
    });

    test('a vehicle inside a sub-level becomes the tracking sub-level', () {
      final result = SubLevelEntityRules.resolve(
        containing: null,
        vehicleContaining: other,
        vehicleTracking: null,
        currentTracking: null,
        hasVehicle: true,
      );
      expect(result.tracking, other);
    });

    test(
      'a vehicle standing on a sub-level becomes the tracking sub-level',
      () {
        final result = SubLevelEntityRules.resolve(
          containing: null,
          vehicleContaining: null,
          vehicleTracking: other,
          currentTracking: null,
          hasVehicle: true,
        );
        expect(result.tracking, other);
      },
    );

    test('a vehicle with no sub-level clears the tracking state', () {
      final result = SubLevelEntityRules.resolve(
        containing: null,
        vehicleContaining: null,
        vehicleTracking: null,
        currentTracking: ship,
        hasVehicle: true,
      );
      expect(result.tracking, isNull);
    });

    test('without a vehicle the previous tracking state is kept', () {
      final result = SubLevelEntityRules.resolve(
        containing: null,
        vehicleContaining: null,
        vehicleTracking: null,
        currentTracking: ship,
      );
      expect(result.tracking, ship);
    });

    test('a removed sub-level is not tracked', () {
      other.markRemoved();
      final result = SubLevelEntityRules.resolve(
        containing: null,
        vehicleContaining: other,
        vehicleTracking: null,
        currentTracking: null,
      );
      expect(result.tracking, isNull);
    });

    test('tracking-or-vehicle prefers the tracking state', () {
      expect(SubLevelEntityRules.trackingOrVehicle(ship, other), ship);
      expect(SubLevelEntityRules.trackingOrVehicle(null, other), other);
      expect(SubLevelEntityRules.trackingOrVehicle(null, null), isNull);
    });

    test(
      'the last tracking id is forgotten once the entity is on the ground',
      () {
        expect(
          SubLevelEntityRules.updatedLastTrackingId(
            tracking: null,
            onGround: true,
            lastTrackingId: 'id',
          ),
          isNull,
        );
        expect(
          SubLevelEntityRules.updatedLastTrackingId(
            tracking: null,
            onGround: false,
            lastTrackingId: 'id',
          ),
          'id',
        );
        expect(
          SubLevelEntityRules.updatedLastTrackingId(
            tracking: ship,
            onGround: true,
            lastTrackingId: 'id',
          ),
          'id',
        );
      },
    );

    test('items tick every tick while on a ship', () {
      expect(SubLevelEntityRules.forceItemEntityTick(ship), isTrue);
      expect(SubLevelEntityRules.forceItemEntityTick(null), isFalse);
    });
  });

  group('destroy when leaving the plot', () {
    late SableLevel level;
    late TestSubLevel ship;
    final tags = {'minecraft:minecart'};

    setUp(() {
      level = FakeLevel();
      ship = makeSubLevel(level, boundsMin: (0, 0, 0), boundsMax: (15, 15, 15));
    });

    test('an entity inside the plot survives', () {
      expect(
        SubLevelEntityRules.shouldDestroyWhenLeavingPlot(
          containing: ship,
          entityBox: BoundingBox3d.full(1, 1, 1, 2, 2, 2),
          destroyWhenLeavingPlot: tags,
          typeId: 'minecraft:minecart',
        ),
        isFalse,
      );
    });

    test('a tagged entity outside the plot is destroyed', () {
      expect(
        SubLevelEntityRules.shouldDestroyWhenLeavingPlot(
          containing: ship,
          entityBox: BoundingBox3d.full(40, 1, 1, 41, 2, 2),
          destroyWhenLeavingPlot: tags,
          typeId: 'minecraft:minecart',
        ),
        isTrue,
      );
    });

    test('an untagged entity is kept', () {
      expect(
        SubLevelEntityRules.shouldDestroyWhenLeavingPlot(
          containing: ship,
          entityBox: BoundingBox3d.full(40, 1, 1, 41, 2, 2),
          destroyWhenLeavingPlot: tags,
          typeId: 'minecraft:cow',
        ),
        isFalse,
      );
    });

    test('no containing sub-level, or an empty plot, never destroys', () {
      expect(
        SubLevelEntityRules.shouldDestroyWhenLeavingPlot(
          containing: null,
          entityBox: BoundingBox3d.full(40, 1, 1, 41, 2, 2),
          destroyWhenLeavingPlot: tags,
          typeId: 'minecraft:minecart',
        ),
        isFalse,
      );

      final empty = makeSubLevel(level);
      expect(
        SubLevelEntityRules.shouldDestroyWhenLeavingPlot(
          containing: empty,
          entityBox: BoundingBox3d.full(40, 1, 1, 41, 2, 2),
          destroyWhenLeavingPlot: tags,
          typeId: 'minecraft:minecart',
        ),
        isFalse,
      );
    });
  });

  group('block positions', () {
    late SableLevel level;

    setUp(() => level = FakeLevel());

    test('the identity pose maps a position to itself', () {
      final ship = makeSubLevel(level);
      expect(
        SubLevelEntityRules.localBlockPos(
          ship,
          Vector3d(4.5, 2.5, 7.5),
          yBias: 0,
        ),
        (4, 2, 7),
      );
      expect(SubLevelEntityRules.globalBlockPos(ship, (4, 2, 7)), (4, 2, 7));
    });

    test('a translated pose is undone by the local query', () {
      final ship = makeSubLevel(level, position: Vector3d(100.0, -20.0, 30.0));
      final local = SubLevelEntityRules.localBlockPos(
        ship,
        Vector3d(104.5, -18.5, 37.5),
        yBias: 0,
      );
      expect(local, (4, 1, 7));
      expect(SubLevelEntityRules.globalBlockPos(ship, local), (104, -19, 37));
    });

    test('a rotated pose round-trips', () {
      final ship = makeSubLevel(
        level,
        position: Vector3d(-50.0, 12.0, 3.0),
        orientation: Quaterniond()..rotateY(0.7),
      );
      const local = (3, 4, 5);
      final global = SubLevelEntityRules.globalBlockPos(ship, local);
      final back = SubLevelEntityRules.localBlockPos(
        ship,
        Vector3d(global.$1 + 0.5, global.$2 + 0.5, global.$3 + 0.5),
        yBias: 0,
      );
      // The block centre lands inside the block it came from.
      expect(back.$1, closeTo(local.$1, 1));
      expect(back.$2, closeTo(local.$2, 1));
      expect(back.$3, closeTo(local.$3, 1));
    });

    test('feet position moves down by the distance', () {
      expect(SubLevelEntityRules.feetPos(Vector3d(1, 5, 1), 0.5).y, 4.5);
    });
  });

  group('distance with sub-levels', () {
    late FakeLevel level;
    late ServerSubLevelContainer container;
    late SubLevel ship;

    setUp(() {
      level = FakeLevel();
      final host = FakeChunkHost(level);
      container = ServerSubLevelContainer(
        level,
        host,
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );
      SubLevelContainer.register(container);
      // Plot (0, 0) covers chunks 160000..160015, so blocks from 2560000.
      ship = container.allocateNewSubLevel(
        Pose3d.full(
          Vector3d(100.0, 0.0, 0.0),
          Quaterniond(),
          Vector3d(),
          Vector3d(1.0, 1.0, 1.0),
        ),
      );
    });

    tearDown(() => SubLevelContainer.unregister(level));

    test('a plot position is projected by the ship pose', () {
      expect(
        SubLevelHelper.projectOutOfSubLevel(
          level,
          Vector3d(2560000.0, 0.0, 2560000.0),
        ),
        Vector3d(2560100.0, 0.0, 2560000.0),
      );
    });

    test('both points are projected out of the ship before the distance', () {
      final a = Vector3d(2560000.0, 0.0, 2560000.0);
      final b = Vector3d(2560100.0, 0.0, 2560000.0);
      // The pose translates both points, so a distance measured between two
      // ship positions is preserved.
      expect(
        SubLevelEntityRules.distanceSquaredWithSubLevels(level, a, b),
        10000.0,
      );
      expect(
        SubLevelEntityRules.rectilinearDistanceWithSubLevels(level, a, b),
        100.0,
      );
    });

    test('two world points are just a distance', () {
      final a = Vector3d(0.0, 0.0, 0.0);
      final b = Vector3d(3.0, 4.0, 0.0);
      expect(
        SubLevelEntityRules.distanceSquaredWithSubLevels(level, a, b),
        25.0,
      );
      expect(
        SubLevelEntityRules.rectilinearDistanceWithSubLevels(level, a, b),
        4.0,
      );
    });

    test('the sub-level is found from a plot position', () {
      expect(
        SubLevelHelper.getContainingPos(
          level,
          Vector3d(2560000.0, 0.0, 2560000.0),
        ),
        same(ship),
      );
    });
  });

  group('projectiles', () {
    late SableLevel level;

    setUp(() => level = FakeLevel());

    test('a shot outside a ship keeps its direction', () {
      expect(
        SubLevelProjectiles.shootDirection(null, Vector3d(0.0, 0.0, 1.0)),
        Vector3d(0.0, 0.0, 1.0),
      );
    });

    test('a shot from a rotated ship leaves along the world direction', () {
      final ship = makeSubLevel(
        level,
        orientation: Quaterniond()..rotateY(1.5707963267948966),
      );
      final direction = SubLevelProjectiles.shootDirection(
        ship,
        Vector3d(0.0, 0.0, 1.0),
      );
      expect(direction.x, closeTo(1.0, 1e-9));
      expect(direction.y, closeTo(0.0, 1e-9));
      expect(direction.z, closeTo(0.0, 1e-9));
    });

    test('the shooter velocity is inherited', () {
      final velocity = SubLevelProjectiles.inheritVelocity(
        Vector3d(0.0, 0.0, 3.0),
        Vector3d(0.1, 0.0, -0.1),
      );
      expect(velocity, Vector3d(0.1, 0.0, 2.9));
      expect(
        SubLevelProjectiles.launch(
          containing: null,
          localDirection: Vector3d(0.0, 0.0, 1.0),
          inheritedVelocity: null,
        ).applyTo(Vector3d(0.0, 0.0, 2.0)),
        Vector3d(0.0, 0.0, 2.0),
      );
    });

    test('an arrow outside a ship is left to the host', () {
      expect(
        SubLevelProjectiles.arrowImpact(
          containing: null,
          arrowPosition: Vector3d(),
          hitPosition: Vector3d(1, 0, 0),
          deltaMovement: Vector3d(1, 0, 0),
          inGround: false,
        ),
        isNull,
      );
    });

    test('an arrow sticks in the ship frame and pushes the body', () {
      final ship = makeSubLevel(level, position: Vector3d(10.0, 0.0, 0.0));
      final impact = SubLevelProjectiles.arrowImpact(
        containing: ship,
        arrowPosition: Vector3d(10.5, 0.5, 0.5),
        hitPosition: Vector3d(11.0, 0.5, 0.5),
        deltaMovement: Vector3d(0.5, 0.0, 0.0),
        inGround: false,
      )!;

      // Local arrow position is (0.5, 0.5, 0.5); the hit is at local x = 1.
      expect(impact.localImpulse, Vector3d(0.5, 0.0, 0.0));
      expect(impact.impulsePoint, Vector3d(0.5, 0.5, 0.5));
      expect(impact.deltaMovement.x, closeTo(0.5, 1e-9));
      expect(impact.localPosition.x, closeTo(0.45, 1e-9));
      expect(impact.yaw, closeTo(90.0, 1e-9));
      expect(impact.pitch, 0.0);
    });

    test('an arrow already in the ground does not push', () {
      final ship = makeSubLevel(level);
      final impact = SubLevelProjectiles.arrowImpact(
        containing: ship,
        arrowPosition: Vector3d(0.5, 0.5, 0.5),
        hitPosition: Vector3d(1.0, 0.5, 0.5),
        deltaMovement: Vector3d(0.5, 0.0, 0.0),
        inGround: true,
      )!;
      expect(impact.localImpulse, Vector3d(0.0, 0.0, 0.0));
    });

    test('a dispenser recoils backwards', () {
      expect(
        SubLevelProjectiles.dispenserRecoil(Vector3d(0.0, 0.0, 1.0)),
        Vector3d(0.0, 0.0, -1.5),
      );
    });
  });

  group('explosions', () {
    late SableLevel level;
    late TestSubLevel ship;

    setUp(() {
      level = FakeLevel();
      ship = makeSubLevel(level, position: Vector3d(100.0, 0.0, 0.0));
    });

    test('a blast centre outside a ship is unchanged', () {
      expect(
        SubLevelExplosions.projectCentre(null, Vector3d(1, 2, 3)),
        Vector3d(1, 2, 3),
      );
    });

    test('a blast centre inside a ship is projected out', () {
      expect(
        SubLevelExplosions.projectCentre(ship, Vector3d(1, 2, 3)),
        Vector3d(101, 2, 3),
      );
    });

    test('with no sub-levels the power is untouched', () {
      final result = SubLevelExplosions.walk(
        rayPoint: Vector3d(),
        centre: Vector3d(),
        subLevels: const [],
        power: 4.0,
        resistance: (_, _) => null,
        shouldBlockExplode: (_, _, _) => true,
      );
      expect(result.power, 4.0);
      expect(result.destroyed, isEmpty);
      expect(result.impulses, isEmpty);
    });

    test('resistance is subtracted and the block is destroyed', () {
      final result = SubLevelExplosions.walk(
        rayPoint: Vector3d(100.5, 0.5, 0.5),
        centre: Vector3d(100.5, 0.5, 0.5),
        subLevels: [ship],
        power: 4.0,
        resistance: (_, _) => 3.0,
        shouldBlockExplode: (_, _, _) => true,
      );
      expect(result.power, closeTo(4.0 - (3.3 * 0.3), 1e-9));
      expect(result.destroyed, [(0, 0, 0)]);
      expect(result.impulses, isEmpty);
    });

    test('a ray that dies pushes the body', () {
      final result = SubLevelExplosions.walk(
        rayPoint: Vector3d(100.5, 0.5, 0.5),
        centre: Vector3d(90.5, 0.5, 0.5),
        subLevels: [ship],
        power: 0.1,
        resistance: (_, _) => 4.0,
        shouldBlockExplode: (_, _, _) => true,
      );
      expect(result.power, lessThan(0.0));
      expect(result.destroyed, isEmpty);
      expect(result.impulses, hasLength(1));
      // The push points away from the centre, in the ship frame.
      expect(result.impulses.single.force, Vector3d(5.0, 0.0, 0.0));
      expect(result.impulses.single.position, Vector3d(0.5, 0.5, 0.5));
    });

    test('a wind charge destroys the block it dies on', () {
      final result = SubLevelExplosions.walk(
        rayPoint: Vector3d(100.5, 0.5, 0.5),
        centre: Vector3d(100.5, 0.5, 0.5),
        subLevels: [ship],
        power: 0.1,
        resistance: (_, _) => null,
        shouldBlockExplode: (_, _, _) => true,
        wind: true,
      );
      expect(result.destroyed, [(0, 0, 0)]);
      expect(result.impulses, hasLength(1));
      expect(result.impulses.single.force, Vector3d(0.0, 0.0, 0.0));
    });

    test('a block is only pushed once', () {
      final exploded = <(SubLevel, int, int, int)>{};
      for (var i = 0; i < 3; i++) {
        SubLevelExplosions.walk(
          rayPoint: Vector3d(100.5, 0.5, 0.5),
          centre: Vector3d(100.5, 0.5, 0.5),
          subLevels: [ship],
          power: 0.1,
          resistance: (_, _) => null,
          shouldBlockExplode: (_, _, _) => true,
          wind: true,
          exploded: exploded,
        );
      }
      expect(exploded, hasLength(1));
    });

    test('power is carried through several sub-levels', () {
      final second = makeSubLevel(level, position: Vector3d(100.0, 0.0, 0.0))
        ..setUniqueId('00000000-0000-4000-8000-000000000003');
      final result = SubLevelExplosions.walk(
        rayPoint: Vector3d(100.5, 0.5, 0.5),
        centre: Vector3d(100.5, 0.5, 0.5),
        subLevels: [ship, second],
        power: 1.0,
        resistance: (_, _) => 0.0,
        shouldBlockExplode: (_, _, _) => true,
      );
      expect(result.power, closeTo(1.0 - 2 * 0.09, 1e-9));
      expect(result.destroyed, hasLength(2));
    });
  });

  group('block event handlers', () {
    late SableLevel level;
    late TestSubLevel ship;
    late RecordingPort port;

    setUp(() {
      level = FakeLevel();
      ship = makeSubLevel(level, boundsMin: (0, 0, 0), boundsMax: (15, 15, 15));
      port = RecordingPort();
    });

    test('a drop from a ship block is kicked out', () {
      port.blocks[(4, 5, 6)] = ship;
      expect(
        DropKicker.onBlockDrop(port, itemEntityId: 7, blockPos: (4, 5, 6)),
        isTrue,
      );
      expect(port.calls, ['kick:7:00000000-0000-4000-8000-000000000001']);
    });

    test('a drop outside a ship is left alone', () {
      expect(
        DropKicker.onBlockDrop(port, itemEntityId: 7, blockPos: (4, 5, 6)),
        isFalse,
      );
      expect(port.calls, isEmpty);
    });

    test('an entity spawned inside a plot is kicked out', () {
      port.positions['1.0,2.0,3.0'] = ship;
      expect(
        SpawnKicker.onEntityAdded(
          port,
          entityId: 9,
          typeId: 'minecraft:item',
          position: Vector3d(1, 2, 3),
          retainInSubLevel: const {},
        ),
        isTrue,
      );
      expect(port.calls, hasLength(1));
    });

    test('a retained entity type stays inside the ship', () {
      port.positions['1.0,2.0,3.0'] = ship;
      expect(
        SpawnKicker.onEntityAdded(
          port,
          entityId: 9,
          typeId: 'minecraft:item',
          position: Vector3d(1, 2, 3),
          retainInSubLevel: const {'minecraft:item'},
        ),
        isFalse,
      );
      expect(port.calls, isEmpty);
    });

    test('a minecart outside the plot is removed', () {
      expect(
        PlotLeash.sweep(
          port,
          entityId: 3,
          typeId: 'minecraft:minecart',
          containing: ship,
          entityBox: BoundingBox3d.full(40, 0, 0, 41, 1, 1),
          destroyWhenLeavingPlot: const {'minecraft:minecart'},
        ),
        isTrue,
      );
      expect(port.calls, ['destroy:3']);
    });

    test('a minecart inside the plot is kept', () {
      expect(
        PlotLeash.sweep(
          port,
          entityId: 3,
          typeId: 'minecraft:minecart',
          containing: ship,
          entityBox: BoundingBox3d.full(1, 0, 0, 2, 1, 1),
          destroyWhenLeavingPlot: const {'minecraft:minecart'},
        ),
        isFalse,
      );
    });

    test('a fluid may flow while there is a block under it in the plot', () {
      final isAir = <(int, int, int)>{};
      expect(
        FluidSpreadGuard.allowSpread(
          containing: ship,
          toPos: (5, 10, 5),
          plotBounds: ship.getPlot().getBoundingBox(),
          isAir: (pos) => !isAir.contains(pos),
        ),
        isTrue,
      );
    });

    test('a fluid may not flow off the edge of the plot', () {
      expect(
        FluidSpreadGuard.allowSpread(
          containing: ship,
          toPos: (5, 3, 5),
          plotBounds: BoundingBox3i.values(0, 4, 0, 15, 15, 15),
          isAir: (_) => true,
        ),
        isFalse,
      );
    });

    test('a fluid outside a ship spreads normally', () {
      expect(
        FluidSpreadGuard.allowSpread(
          containing: null,
          toPos: (5, 3, 5),
          plotBounds: BoundingBox3i.values(0, 4, 0, 15, 15, 15),
          isAir: (_) => true,
        ),
        isTrue,
      );
    });

    test('vines do not spread inside a ship, other blocks do', () {
      expect(
        OvergrowthGuard.shouldCancel(
          containingTarget: ship,
          newBlock: 'minecraft:vine',
        ),
        isTrue,
      );
      expect(
        OvergrowthGuard.shouldCancel(
          containingTarget: ship,
          newBlock: 'minecraft:stone',
        ),
        isFalse,
      );
      expect(
        OvergrowthGuard.shouldCancel(
          containingTarget: null,
          newBlock: 'minecraft:vine',
        ),
        isFalse,
      );
    });

    test('lightning is cancelled in the plot yard', () {
      expect(
        LightningGuard.shouldCancel(inPlotYard: true, containing: null),
        isTrue,
      );
      expect(
        LightningGuard.shouldCancel(inPlotYard: false, containing: ship),
        isTrue,
      );
      expect(
        LightningGuard.shouldCancel(inPlotYard: false, containing: null),
        isFalse,
      );
    });
  });

  group('player handlers', () {
    late SableLevel level;
    late TestSubLevel ship;

    setUp(() {
      level = FakeLevel();
      ship = makeSubLevel(level, position: Vector3d(0.0, 100.0, 0.0));
    });

    test('a teleport target inside a ship is projected out', () {
      expect(
        PlayerProjection.projectOut(null, Vector3d(1, 2, 3)),
        Vector3d(1, 2, 3),
      );
      expect(
        PlayerProjection.projectOut(ship, Vector3d(1, 2, 3)),
        Vector3d(1, 102, 3),
      );
      expect(
        PlayerProjection.projectRespawn(ship, Vector3d(1, 2, 3)),
        Vector3d(1, 102, 3),
      );
    });

    test('waking up moves the player down by half their height', () {
      final position = PlayerProjection.standUpPosition(
        ship,
        Vector3d(1, 2, 3),
        0.9,
      );
      expect(position, Vector3d(1, 101.1, 3));
    });

    test(
      'the fall message names the ship only when it is no longer tracked',
      () {
        expect(
          FallDeathMessage.message(
            subLevelName: 'Airship',
            stillTracking: false,
          ),
          'death.attack.fall.from_sublevel',
        );
        expect(
          FallDeathMessage.message(
            subLevelName: 'Airship',
            stillTracking: true,
          ),
          isNull,
        );
        expect(
          FallDeathMessage.message(subLevelName: null, stillTracking: false),
          isNull,
        );
        expect(
          FallDeathMessage.message(subLevelName: '', stillTracking: false),
          isNull,
        );
      },
    );

    test('a respawn anchor is generated and replaced', () {
      final removed = <String>[];
      var generated = 0;
      final anchor = RespawnAnchor();

      anchor.onSpawnChanged(
        containing: ship,
        remove: removed.add,
        generate: () => 'point-${generated++}',
      );
      expect(anchor.pointId, 'point-0');
      expect(anchor.isOnSubLevel, isTrue);

      anchor.onSpawnChanged(
        containing: ship,
        remove: removed.add,
        generate: () => 'point-${generated++}',
      );
      expect(removed, ['point-0']);
      expect(anchor.pointId, 'point-1');

      anchor.onSpawnChanged(
        containing: null,
        remove: removed.add,
        generate: () => 'nope',
      );
      expect(removed, ['point-0', 'point-1']);
      expect(anchor.isOnSubLevel, isFalse);
    });

    test('the respawn anchor survives a save/load round-trip', () {
      final anchor = RespawnAnchor('11111111-2222-4333-8444-555555555555');
      final saved = anchor.savedValue()!;
      expect(RespawnAnchor.fromSavedValue(saved).pointId, anchor.pointId);
      expect(RespawnAnchor.fromSavedValue(null).pointId, isNull);
    });

    test('a frozen player expires after 160 ticks', () {
      final frozen = FrozenPlayer()..freezeTo('ship', Vector3d(1, 2, 3));
      expect(frozen.isFrozen, isTrue);
      expect(frozen.needsJoinPayload, isTrue);

      for (var i = 0; i < FrozenPlayer.timeoutTicks; i++) {
        expect(frozen.tick(), isFalse);
      }
      expect(frozen.tick(), isTrue);
      expect(frozen.isFrozen, isFalse);
    });

    test('refreshing a freeze resets the timer', () {
      final frozen = FrozenPlayer()..freezeTo('ship', Vector3d(1, 2, 3));
      for (var i = 0; i < 100; i++) {
        frozen.tick();
      }
      frozen.freezeTo('ship', Vector3d(1, 2, 3));
      expect(frozen.ticks, 0);
      expect(frozen.isFrozen, isTrue);
    });

    test('the frozen player follows the ship pose', () {
      final frozen = FrozenPlayer()..freezeTo('ship', Vector3d(1, 2, 3));
      expect(frozen.teleportTarget(ship), Vector3d(1, 102, 3));

      ship.pose.position().set(0.0, 200.0, 0.0);
      ship.updateLastPose();
      expect(frozen.teleportTarget(ship), Vector3d(1, 202, 3));

      frozen.clear();
      expect(frozen.teleportTarget(ship), isNull);
    });
  });

  group('collision effects', () {
    test('drag stops the inherited velocity on the ground', () {
      final velocity = CollisionEffects.drag(
        Vector3d(1.0, 1.0, 1.0),
        verticalCollision: true,
        onGround: true,
        horizontalCollision: false,
        flying: false,
        touchingWater: false,
      );
      expect(velocity.y, 0.0);
      expect(velocity.x, closeTo(0.7 * 0.99, 1e-9));
    });

    test('drag applies every factor', () {
      final velocity = CollisionEffects.drag(
        Vector3d(1.0, 1.0, 1.0),
        verticalCollision: false,
        onGround: false,
        horizontalCollision: true,
        flying: true,
        touchingWater: true,
      );
      expect(velocity.x, closeTo(0.8 * 0.9 * 0.9 * 0.99, 1e-9));
      expect(velocity.y, closeTo(0.6 * 0.9 * 0.9 * 0.99, 1e-9));
    });

    test('a tiny inherited velocity is zeroed', () {
      expect(
        CollisionEffects.clampInherited(Vector3d(1e-5, 1e-5, 0)).lengthSquared,
        0.0,
      );
      expect(CollisionEffects.clampInherited(Vector3d(0.1, 0, 0)).x, 0.1);
    });

    test('a slow contact does nothing', () {
      final impact = CollisionEffects.evaluate(
        entityVelocity: Vector3d(0.1, 0.0, 0.0),
        pointVelocity: Vector3d(),
        direction: Vector3d(-1.0, 0.0, 0.0),
        bouncy: false,
        trackingShip: false,
      );
      expect(impact.bounce, isNull);
      expect(impact.damage, isNull);
    });

    test('a bouncy block pushes back and plays the fall sound', () {
      final impact = CollisionEffects.evaluate(
        entityVelocity: Vector3d(1.0, 0.0, 0.0),
        pointVelocity: Vector3d(),
        direction: Vector3d(-1.0, 0.0, 0.0),
        bouncy: true,
        trackingShip: true,
      );
      expect(impact.playFallSound, isTrue);
      expect(impact.bounce, isNotNull);
      // The push follows the contact normal, which points away from the ship.
      expect(impact.bounce!.x, closeTo(-0.65, 1e-9));
      expect(impact.damage, isNull);
    });

    test('a hard contact deals fly-into-wall damage', () {
      final impact = CollisionEffects.evaluate(
        entityVelocity: Vector3d(1.0, 0.0, 0.0),
        pointVelocity: Vector3d(),
        direction: Vector3d(-1.0, 0.0, 0.0),
        bouncy: false,
        trackingShip: false,
      );
      expect(impact.bounce, isNull);
      expect(impact.damage, closeTo(12.0 - 8.0, 1e-9));
    });
  });

  group('standing on a ship', () {
    late SableLevel level;
    late TestSubLevel ship;

    setUp(() {
      level = FakeLevel();
      ship = makeSubLevel(level);
      ship.globalBounds.setValues(-8.0, -8.0, -8.0, 8.0, 8.0, 8.0);
    });

    test('a block under the entity is found', () {
      final result = SubLevelStanding.canFallAtLeast(
        entityBox: BoundingBox3d.full(-0.3, 1.0, -0.3, 0.3, 1.8, 0.3),
        subLevels: [ship],
        shapesAt: (subLevel, block) => block == (0, 0, 0)
            ? [BoundingBox3d.full(0.0, 0.0, 0.0, 1.0, 1.0, 1.0)]
            : const [],
      );
      expect(result, isNotNull);
    });

    test('nothing under the entity means it can fall', () {
      final result = SubLevelStanding.canFallAtLeast(
        entityBox: BoundingBox3d.full(-0.3, 1.0, -0.3, 0.3, 1.8, 0.3),
        subLevels: [ship],
        shapesAt: (subLevel, block) => const [],
      );
      expect(result, isNull);
    });

    test('an entity outside every ship falls', () {
      final result = SubLevelStanding.canFallAtLeast(
        entityBox: BoundingBox3d.full(40.0, 1.0, 40.0, 40.6, 1.8, 40.6),
        subLevels: [ship],
        shapesAt: (subLevel, block) => [
          BoundingBox3d.full(0.0, 0.0, 0.0, 1.0, 1.0, 1.0),
        ],
      );
      expect(result, isNull);
    });

    test('edge back-off leaves a flying player alone', () {
      expect(
        SubLevelStanding.backOffFromEdge(
          movement: Vector3d(0.2, 0.0, 0.0),
          pose: ship.lastPose,
          flying: true,
          stayingOnGroundSurface: true,
          aboveGround: true,
          wouldSlideOff: (_, _, _) => true,
        ),
        isNull,
      );
    });

    test('edge back-off keeps a safe movement', () {
      final result = SubLevelStanding.backOffFromEdge(
        movement: Vector3d(0.2, 0.0, 0.0),
        pose: ship.lastPose,
        flying: false,
        stayingOnGroundSurface: true,
        aboveGround: true,
        wouldSlideOff: (_, _, _) => false,
      );
      expect(result, isNotNull);
      expect(result!.x, closeTo(0.2, 1e-9));
      expect(result.y, 0.0);
    });

    test('edge back-off stops a movement that would slide off', () {
      final result = SubLevelStanding.backOffFromEdge(
        movement: Vector3d(0.2, 0.0, 0.0),
        pose: ship.lastPose,
        flying: false,
        stayingOnGroundSurface: true,
        aboveGround: true,
        wouldSlideOff: (_, _, _) => true,
      );
      expect(result, isNotNull);
      expect(result!.x, 0.0);
    });

    test('would-slide-off is the inverse of the block query', () {
      final bounds = BoundingBox3d.full(-0.3, 1.0, -0.3, 0.3, 1.8, 0.3);
      final frame = Quaterniond();

      expect(
        SubLevelStanding.wouldSlideOff(
          bounds: bounds,
          localX: 0.0,
          localZ: 0.0,
          fallDistance: 0.6,
          frame: frame,
          subLevels: [ship],
          shapesAt: (_, block) => block == (0, 0, 0)
              ? [BoundingBox3d.full(0.0, 0.0, 0.0, 1.0, 1.0, 1.0)]
              : const [],
        ),
        isFalse,
      );

      expect(
        SubLevelStanding.wouldSlideOff(
          bounds: bounds,
          localX: 5.0,
          localZ: 0.0,
          fallDistance: 0.6,
          frame: frame,
          subLevels: [ship],
          shapesAt: (_, block) => block == (0, 0, 0)
              ? [BoundingBox3d.full(0.0, 0.0, 0.0, 1.0, 1.0, 1.0)]
              : const [],
        ),
        isTrue,
      );
    });
  });

  group('impact callbacks', () {
    late RecordingImpactHost host;

    setUp(() => host = RecordingImpactHost());
    tearDown(() {
      BlockWithSubLevelCollisionCallback.fragileCallback = null;
      for (final key in [
        'minecraft:beehive',
        'minecraft:bee_nest',
        'minecraft:bell',
        'minecraft:tnt',
      ]) {
        BlockWithSubLevelCollisionCallback.unregister(key);
      }
    });

    test('a soft impact does nothing', () {
      final callback = FragileBlockCallback(host);
      final result = callback.handle(
        hitBlockPos: (1, 2, 3),
        impactPosition: Vector3d(),
        impactVelocity: 2.0,
        fragileFlag: true,
      );
      expect(result.removeCollision, isFalse);
      expect(host.calls, isEmpty);
    });

    test('a hard impact breaks a fragile block', () {
      final callback = FragileBlockCallback(host);
      final result = callback.handle(
        hitBlockPos: (1, 2, 3),
        impactPosition: Vector3d(),
        impactVelocity: 5.0,
        fragileFlag: true,
      );
      expect(result.removeCollision, isTrue);
      expect(host.calls, ['destroy:(1, 2, 3):true']);
    });

    test('a non-fragile block is not broken by the fallback', () {
      final callback = FragileBlockCallback(host);
      final result = callback.handle(
        hitBlockPos: (1, 2, 3),
        impactPosition: Vector3d(),
        impactVelocity: 5.0,
        fragileFlag: false,
      );
      expect(result.removeCollision, isFalse);
      expect(host.calls, isEmpty);
    });

    test('persistent leaves survive a hard impact', () {
      host.states[(1, 2, 3)] = const BState('minecraft:leaves', {
        'persistent': 'true',
      });
      final callback = FragileBlockCallback(host);
      final result = callback.handle(
        hitBlockPos: (1, 2, 3),
        impactPosition: Vector3d(),
        impactVelocity: 9.0,
        fragileFlag: true,
      );
      expect(result.removeCollision, isFalse);
      expect(host.calls, isEmpty);
    });

    test('ice over water melts instead of vanishing', () {
      host.states[(1, 2, 3)] = const BState('minecraft:ice');
      host.liquids[(1, 1, 3)] = true;
      final callback = FragileBlockCallback(host);
      callback.handle(
        hitBlockPos: (1, 2, 3),
        impactPosition: Vector3d(),
        impactVelocity: 5.0,
        fragileFlag: true,
      );
      expect(host.calls, [
        'destroy:(1, 2, 3):true',
        'set:(1, 2, 3):minecraft:water',
      ]);
    });

    test('a beehive empties itself above its own trigger speed', () {
      host.states[(1, 2, 3)] = const BState('minecraft:beehive');
      final callback = BeehiveBlockCallback(host);
      expect(
        callback
            .handle(
              hitBlockPos: (1, 2, 3),
              impactPosition: Vector3d(),
              impactVelocity: 9.5,
              fragileFlag: true,
            )
            .removeCollision,
        isFalse,
      );
      expect(host.calls, ['hive:(1, 2, 3)']);

      host.calls.clear();
      callback.handle(
        hitBlockPos: (1, 2, 3),
        impactPosition: Vector3d(),
        impactVelocity: 8.9,
        fragileFlag: true,
      );
      expect(host.calls, isEmpty);
    });

    test('a bell rings away from the impact', () {
      host.states[(1, 2, 3)] = const BState('minecraft:bell', {
        'facing': 'north',
        'attachment': 'ceiling',
      });
      final callback = BellBlockCallback(host);

      // Hit from the east: the ring direction is the opposite of the nearest
      // direction to the hit, i.e. east.
      callback.handle(
        hitBlockPos: (1, 2, 3),
        impactPosition: Vector3d(3.0, 2.5, 3.5),
        impactVelocity: 5.0,
        fragileFlag: true,
      );
      expect(host.calls, ['ring:(1, 2, 3):east']);
    });

    test('a ceiling bell rings on both axes', () {
      final state = const BState('minecraft:bell', {
        'facing': 'north',
        'attachment': 'ceiling',
      });
      expect(
        BellBlockCallback.bellRingDirection(
          (0, 0, 0),
          state,
          Vector3d(3.0, 0.5, 0.5),
        ),
        'east',
      );
      expect(
        BellBlockCallback.bellRingDirection(
          (0, 0, 0),
          state,
          Vector3d(0.5, 0.5, -2.0),
        ),
        'north',
      );
    });

    test('a floor bell ignores the axis it does not face', () {
      final state = const BState('minecraft:bell', {
        'facing': 'east',
        'attachment': 'floor',
      });
      // A hit from the north only has a z component, which an east-facing bell
      // zeroes; the x component decides.
      expect(
        BellBlockCallback.bellRingDirection(
          (0, 0, 0),
          state,
          Vector3d(-2.0, 0.5, -2.0),
        ),
        'west',
      );
    });

    test('TNT lights and removes itself', () {
      host.states[(1, 2, 3)] = const BState('minecraft:tnt');
      final callback = ExplosiveBlockCallback(host);
      final result = callback.handle(
        hitBlockPos: (1, 2, 3),
        impactPosition: Vector3d(),
        impactVelocity: 6.0,
        fragileFlag: true,
      );
      expect(result.removeCollision, isTrue);
      expect(host.calls, ['tnt:(1, 2, 3):4', 'set:(1, 2, 3):minecraft:air']);
    });

    test('registration installs the callbacks the registry looks up', () {
      registerVanillaImpactCallbacks(host);
      expect(
        BlockWithSubLevelCollisionCallback.sable$getCallbackFor(
          const BState('minecraft:bell'),
        ),
        isA<BellBlockCallback>(),
      );
      expect(
        BlockWithSubLevelCollisionCallback.sable$getCallbackFor(
          const BState('minecraft:bee_nest'),
        ),
        isA<BeehiveBlockCallback>(),
      );
      expect(
        BlockWithSubLevelCollisionCallback.sable$getCallbackFor(
          const BState('minecraft:tnt'),
        ),
        isA<ExplosiveBlockCallback>(),
      );
      expect(
        BlockWithSubLevelCollisionCallback.sable$getCallbackFor(
          const BState('minecraft:glass', {'fragile': 'true'}),
        ),
        isA<FragileBlockCallback>(),
      );
      expect(
        BlockWithSubLevelCollisionCallback.sable$getCallbackFor(
          const BState('minecraft:stone'),
        ),
        isNull,
      );
    });
  });
}
