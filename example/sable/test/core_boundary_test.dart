// Tests for the Sable core's physics boundary and lifecycle glue: the
// `ServerSubLevel.prePhysicsTick` orchestration, the sub-level name payload,
// the tracking-point projection on removal, the force-load dependency chain,
// the container's close path and the snapshot batching.
//
// Everything here is pure: the host is the in-memory fake from `support.dart`.
import 'dart:typed_data';

// create's block-state type is not exported from its public barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:sable/sable.dart';
// The plot stores its own lift-provider context (a block state string plus the
// lift normal), which the barrel hides behind the API's BState-based one.
import 'package:sable/src/sublevel/model/server_level_plot.dart' as plot;
import 'package:test/test.dart';

import 'support.dart';

/// A body that records every impulse it is given.
final class RecordingHandle implements RigidBodyHandle {
  final List<(Vector3d, Vector3d, bool)> impulses = [];
  final List<ForceTotal> forceTotals = [];
  Vector3d linearVelocity = Vector3d();
  Vector3d angularVelocity = Vector3d();

  @override
  Vector3d getLinearVelocity([Vector3d? dest]) =>
      (dest ?? Vector3d()).set(linearVelocity.x, linearVelocity.y, linearVelocity.z);

  @override
  Vector3d getAngularVelocity([Vector3d? dest]) =>
      (dest ?? Vector3d()).set(angularVelocity.x, angularVelocity.y, angularVelocity.z);

  @override
  void applyLinearAndAngularImpulse(Vector3d linear, Vector3d angular, bool wakeUp) =>
      impulses.add((Vector3d.copy(linear), Vector3d.copy(angular), wakeUp));

  @override
  void applyForcesAndReset(ForceTotal forceTotal) => forceTotals.add(forceTotal);

  @override
  void applyImpulseAtPoint(Vector3d position, Vector3d force) {}

  @override
  void teleport(Vector3d position, Quaterniond orientation) {}

  @override
  void addLinearAndAngularVelocity(Vector3d linear, Vector3d angular) {}

  @override
  bool get isValid => true;
}

/// A mass tracker whose blocks are gone.
final class InvalidMass implements MassData {
  @override
  Vector3d getCenterOfMass() => Vector3d();

  @override
  double getInverseMass() => 0;

  @override
  double getMass() => 0;

  @override
  Matrix3d getInertiaTensor() => Matrix3d.zero();

  @override
  Matrix3d getInverseInertiaTensor() => Matrix3d.zero();

  @override
  bool isInvalid() => true;

  @override
  BoundingBox3ic? getBounds() => null;
}

/// A mass tracker with a fixed centre of mass and inertia.
final class FixedMass implements MassData {
  @override
  Vector3d getCenterOfMass() => Vector3d(0, 0.5, 0);

  @override
  double getInverseMass() => 1.0;

  @override
  double getMass() => 1.0;

  @override
  Matrix3d getInertiaTensor() => Matrix3d.identity();

  @override
  Matrix3d getInverseInertiaTensor() => Matrix3d.identity();

  @override
  bool isInvalid() => false;

  @override
  BoundingBox3ic? getBounds() => null;
}

/// A lift provider that records the velocity it was handed and adds a fixed
/// impulse, so the test can tell the ordering apart.
final class RecordingLiftProvider implements BlockSubLevelLiftProvider {
  final Vector3d force;
  final List<Vector3d> seenLinearVelocity = [];
  final List<Pose3d?> seenLocalPose = [];

  RecordingLiftProvider(this.force);

  @override
  Direction sable$getNormal(BState state) => Direction.up;

  @override
  double sable$getParallelDragScalar() => 0;

  @override
  double sable$getDirectionlessDragScalar() => 0;

  @override
  double sable$getLiftScalar() => 0;

  @override
  void sable$contributeLiftAndDrag(
    LiftProviderContext ctx,
    ServerSubLevel subLevel,
    Pose3d? localPose,
    double timeStep,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
    Vector3d linearImpulse,
    Vector3d angularImpulse, [
    LiftProviderGroup? group,
  ]) {
    seenLinearVelocity.add(Vector3d.copy(linearVelocity));
    seenLocalPose.add(localPose == null ? null : Pose3d.copy(localPose));
    linearImpulse.add(force);
  }
}

/// A kinematic contraption that contributes one lift provider.
final class FakeContraption implements KinematicContraption {
  final Map<(int, int, int), Object> providers;

  FakeContraption(this.providers);

  @override
  void sable$getLocalBounds(BoundingBox3i bounds) {}

  @override
  Object sable$blockGetter() => Object();

  @override
  MassData sable$getMassTracker() => FixedMass();

  @override
  Vector3d sable$getPosition(double partialTick) => Vector3d();

  @override
  Quaterniond sable$getOrientation(double partialTick) => Quaterniond();

  @override
  Map<(int, int, int), Object> sable$liftProviders() => providers;

  @override
  bool sable$shouldCollide() => false;

  @override
  bool sable$isValid() => true;

  @override
  Pose3d sable$getLocalPose(Pose3d dest, double partialTick) {
    dest.rotationPoint().setFrom(sable$getMassTracker().getCenterOfMass());
    dest.position().setFrom(sable$getPosition(partialTick));
    dest.orientation().setFrom(sable$getOrientation(partialTick));
    dest.scale().set(1.0, 1.0, 1.0);
    return dest;
  }
}

/// A pipeline that records the calls the container's `close` makes.
final class ClosingPipeline implements PhysicsPipeline {
  bool disposed = false;

  @override
  void dispose() => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ServerSubLevel addServerSubLevel(
  ServerSubLevelContainer container,
  int x,
  int z,
  String uuid, {
  SableConfigLike? config,
}) {
  SubLevelContainer.register(container);
  final subLevel = container.allocateSubLevel(uuid, x, z, Pose3d()) as ServerSubLevel;
  subLevel.massTracker = FixedMass();
  return subLevel;
}

ServerSubLevelContainer makeContainer(FakeLevel level, FakeChunkHost host) =>
    ServerSubLevelContainer(
      level,
      host,
      3,
      4,
      SubLevelContainer.defaultOrigin,
      SubLevelContainer.defaultOrigin,
    );

void main() {
  setUp(() {
    SubLevelContainer.clearAll();
    ServerSubLevel.packetSink = null;
    BlockSubLevelLiftProvider.lookup = null;
    DimensionPhysicsData.clearPhysics();
    DimensionPhysicsData.clearDefaults();
  });

  group('the declared channels', () {
    test('every payload of the table is declared, and nothing else', () {
      // `neoforge:register` answers with `sableChannels`; a payload missing from
      // it is never negotiated, and a channel with no codec would be accepted
      // and then dropped on arrival.
      final declared = {for (final channel in sableChannels) channel.id};
      final registered = {
        for (final codec in SablePackets.allClientbound) codec.id,
        for (final codec in SablePackets.allServerbound) codec.id,
      };
      expect(declared, registered);
    });

    test('the channel version is the Veil manager version', () {
      for (final channel in sableChannels) {
        expect(channel.version, '1', reason: channel.id);
      }
    });

    test('the flow of each channel is the payload direction', () {
      final clientbound = {for (final codec in SablePackets.allClientbound) codec.id};
      for (final channel in sableChannels) {
        expect(
          channel.serverbound,
          !clientbound.contains(channel.id),
          reason: channel.id,
        );
      }
    });
  });

  group('SableAttributes', () {
    test('the two attribute names are the Java strings', () {
      expect(SableAttributes.punchStrengthName, 'player.sub_level_punch_strength');
      expect(SableAttributes.punchCooldownName, 'player.sub_level_punch_cooldown');
      expect(SableAttributes.punchStrengthTranslationKey,
          'attribute.name.player.sub_level_punch_strength');
      expect(SableAttributes.all, hasLength(2));
    });

    test('the ranges and defaults are the Java RangedAttribute arguments', () {
      expect(SableAttributes.punchStrength.defaultValue, 1.0);
      expect(SableAttributes.punchStrength.minValue, -100.0);
      expect(SableAttributes.punchStrength.maxValue, 100.0);
      expect(SableAttributes.punchStrength.syncable, isTrue);

      expect(SableAttributes.punchCooldown.defaultValue, 0.0);
      expect(SableAttributes.punchCooldown.minValue, 0.0);
      expect(SableAttributes.punchCooldown.maxValue, 10.0);
      expect(SableAttributes.punchCooldown.syncable, isTrue);
    });

    test('clamp follows RangedAttribute.sanitizeValue', () {
      expect(SableAttributes.punchCooldown.clamp(-1), 0.0);
      expect(SableAttributes.punchCooldown.clamp(20), 10.0);
      expect(SableAttributes.punchCooldown.clamp(2.5), 2.5);
      expect(SableAttributes.punchStrength.clamp(-500), -100.0);
    });

    test('getPushCooldownTicks is ceil(value * 20)', () {
      expect(SableAttributes.getPushCooldownTicks(0.0), 0);
      expect(SableAttributes.getPushCooldownTicks(0.05), 1);
      expect(SableAttributes.getPushCooldownTicks(0.01), 1);
      expect(SableAttributes.getPushCooldownTicks(1.0), 20);
      expect(SableAttributes.getPushCooldownTicks(1.001), 21);
      expect(SableAttributes.getPushCooldownTicks(-1.0), -20);
    });
  });

  group('SableTags and SableToasts', () {
    test('every tag id is sable:<path> in the Java registry split', () {
      expect(SableTags.retainInSubLevel, 'sable:retain_in_sub_level');
      expect(SableTags.destroyWithSubLevel, 'sable:destroy_with_sub_level');
      expect(SableTags.destroyWhenLeavingPlot, 'sable:destroy_when_leaving_plot');
      expect(SableTags.alwaysChunkRendering, 'sable:always_chunk_rendering');
      expect(SableTags.bouncy, 'sable:bouncy');
      expect(SableTags.paddles, 'sable:paddles');
      expect(SableTags.silentAssemblyRemoval, 'sable:silent_assembly_removal');

      expect(SableTags.entityTypeTags, hasLength(3));
      expect(SableTags.blockTags, hasLength(3));
      expect(SableTags.itemTags, hasLength(1));
      expect(
        [...SableTags.entityTypeTags, ...SableTags.blockTags, ...SableTags.itemTags],
        hasLength(7),
      );
    });

    test('the three toast tokens are distinct', () {
      expect(SableToasts.all, hasLength(3));
      expect(
        SableToasts.all.toSet(),
        hasLength(3),
        reason: 'the Java ids are distinct objects; that identity is the point',
      );
    });
  });

  group('BlockSubLevelLiftProvider.parseState', () {
    test('a bare id has no properties', () {
      final state = BlockSubLevelLiftProvider.parseState('create:white_sail');
      expect(state.key, 'create:white_sail');
      expect(state.props, isEmpty);
    });

    test('a property list is split on commas and the first equals', () {
      final state = BlockSubLevelLiftProvider.parseState('create:white_sail[facing=north,waterlogged=false]');
      expect(state.key, 'create:white_sail');
      expect(state.props, {'facing': 'north', 'waterlogged': 'false'});
    });

    test('a malformed list is treated as no properties', () {
      expect(BlockSubLevelLiftProvider.parseState('create:white_sail[facing=north').props, isEmpty);
      expect(BlockSubLevelLiftProvider.parseState('create:white_sail]').props, isEmpty);
    });
  });

  group('ServerSubLevel.prePhysicsTick', () {
    late FakeLevel level;
    late FakeChunkHost host;
    late ServerSubLevelContainer container;
    late ServerSubLevel subLevel;

    setUp(() {
      level = FakeLevel();
      host = FakeChunkHost(level);
      container = makeContainer(level, host);
      subLevel = addServerSubLevel(container, 0, 0, '00000000-0000-0000-0000-0000000000c1');
    });

    test('a sub-level with nothing to simulate applies no impulse', () {
      final handle = RecordingHandle();
      subLevel.prePhysicsTick(1.0, handle, 0.05);

      expect(handle.impulses, isEmpty);
    });

    test('a lift provider contributes its impulse and sees the gravity-adjusted velocity', () {
      final provider = RecordingLiftProvider(Vector3d(0, 2, 0));
      BlockSubLevelLiftProvider.lookup = (state) =>
          state.key == 'test:sail' ? provider : null;

      subLevel.getPlot().liftProviders[packBlockPos((1, 2, 3))] =
          plot.LiftProviderContext((1, 2, 3), 'test:sail[facing=north]', (0.0, 1.0, 0.0));

      final handle = RecordingHandle();
      subLevel.prePhysicsTick(1.0, handle, 0.05);

      expect(handle.impulses, hasLength(1));
      expect(handle.impulses.single.$1.y, closeTo(2.0, 1e-9));
      expect(handle.impulses.single.$3, isFalse, reason: 'Java passes wakeUp = false');

      // Java applies the gravity term *after* the lift providers run
      // (`ServerSubLevel.java:390`), so a provider sees the body's raw velocity.
      expect(provider.seenLinearVelocity, hasLength(1));
      expect(provider.seenLinearVelocity.single.y, closeTo(0.0, 1e-9));
    });

    test('an unknown block state contributes no force but still applies an empty impulse', () {
      subLevel.getPlot().liftProviders[packBlockPos((0, 0, 0))] =
          plot.LiftProviderContext((0, 0, 0), 'minecraft:stone', (0.0, 1.0, 0.0));

      final handle = RecordingHandle();
      subLevel.prePhysicsTick(1.0, handle, 0.05);

      // Java enters the block because the provider list is not empty, then
      // applies the (zero) impulse pair.
      expect(handle.impulses, hasLength(1));
      expect(handle.impulses.single.$1, Vector3d());
      expect(handle.impulses.single.$2, Vector3d());
    });

    test('a contraption provider receives the contraption local pose', () {
      final provider = RecordingLiftProvider(Vector3d(1, 0, 0));
      BlockSubLevelLiftProvider.lookup = (state) =>
          state.key == 'test:sail' ? provider : null;

      subLevel.getPlot().addContraption(
        FakeContraption({
          (0, 0, 0): plot.LiftProviderContext((0, 0, 0), 'test:sail', (0.0, 1.0, 0.0)),
        }),
      );

      final handle = RecordingHandle();
      subLevel.prePhysicsTick(1.0, handle, 0.05);

      expect(provider.seenLocalPose, hasLength(1));
      expect(provider.seenLocalPose.single, isNotNull);
      expect(handle.impulses.single.$1.x, closeTo(1.0, 1e-9));
    });

    test('the partial tick is read from the physics system', () {
      final provider = RecordingLiftProvider(Vector3d());
      BlockSubLevelLiftProvider.lookup = (state) => provider;

      final contraption = _TickRecordingContraption({
        (0, 0, 0): plot.LiftProviderContext((0, 0, 0), 'test:sail', (0.0, 1.0, 0.0)),
      });
      subLevel.getPlot().addContraption(contraption);

      subLevel.prePhysicsTick(_PartialTick(0.75), RecordingHandle(), 0.05);

      expect(contraption.seenPartialTick, 0.75);
    });

    test('tracked forces record the group lift in the lift force group', () {
      subLevel.enableIndividualQueuedForcesTracking(true);

      // The default sail provider produces lift from the air pressure; the
      // recorded total must appear in `sable:lift`.
      final provider = _GroupingLiftProvider();
      BlockSubLevelLiftProvider.lookup = (state) => provider;
      subLevel.getPlot().liftProviders[packBlockPos((0, 0, 0))] =
          plot.LiftProviderContext((0, 0, 0), 'test:sail', (0.0, 1.0, 0.0));

      subLevel.prePhysicsTick(1.0, RecordingHandle(), 0.05);

      final liftGroup = subLevel.getQueuedForceGroups()?[ForceGroup.lift];
      expect(liftGroup, isNotNull);
      expect(liftGroup!.getRecordedPointForces(), hasLength(1));
    });
  });

  group('ServerSubLevel.setName', () {
    test('a change is sent to the tracking players before the name is set', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final subLevel = addServerSubLevel(container, 0, 0, '00000000-0000-0000-0000-0000000000c2');

      final sent = <(ServerSubLevel, Object)>[];
      ServerSubLevel.packetSink = (target, payload) => sent.add((target, payload));

      subLevel.setName('Boat');

      expect(sent, hasLength(1));
      expect(sent.single.$1, same(subLevel));
      final packet = sent.single.$2;
      expect(packet, isA<ClientboundChangeSubLevelNamePacket>());
      expect((packet as ClientboundChangeSubLevelNamePacket).subLevelId, subLevel.uniqueId);
      expect(packet.name, 'Boat');
      expect(subLevel.name, 'Boat');
    });

    test('setting the same name sends nothing', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final subLevel = addServerSubLevel(container, 0, 0, '00000000-0000-0000-0000-0000000000c3');
      subLevel.setName('Boat');

      var count = 0;
      ServerSubLevel.packetSink = (_, _) => count++;
      subLevel.setName('Boat');

      expect(count, 0);
    });

    test('clearing the name writes an absent optional', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final subLevel = addServerSubLevel(container, 0, 0, '00000000-0000-0000-0000-0000000000c4');
      subLevel.setName('Boat');

      final sent = <Object>[];
      ServerSubLevel.packetSink = (_, payload) => sent.add(payload);
      subLevel.setName(null);

      expect((sent.single as ClientboundChangeSubLevelNamePacket).name, isNull);
    });

    test('a sub-level without an id has nobody to tell', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      SubLevelContainer.register(makeContainer(level, host));
      final subLevel = ServerSubLevel(level, 10000, 10000, Pose3d(), runtimeId: 1);

      var count = 0;
      ServerSubLevel.packetSink = (_, _) => count++;
      subLevel.setName('Boat');

      expect(count, 0);
      expect(subLevel.name, 'Boat');
    });
  });

  group('SubLevelTrackingPointObserver', () {
    late FakeLevel level;
    late FakeChunkHost host;
    late ServerSubLevelContainer container;
    late ServerSubLevel subLevel;
    late TrackingPointStore store;

    setUp(() {
      level = FakeLevel();
      host = FakeChunkHost(level);
      container = makeContainer(level, host);
      subLevel = addServerSubLevel(container, 0, 0, '00000000-0000-0000-0000-0000000000c5');
      subLevel.logicalPose.position().set(100, 64, -100);
      store = TrackingPointStore();
    });

    test('a point saved with the removed sub-level is projected to world space', () {
      final pointer = const GlobalSavedSubLevelPointer(3, -4, 0, 1);
      subLevel.setLastSerializationPointer(pointer);
      store.setTrackingPoint(
        'p1',
        TrackingPoint(true, subLevel.uniqueId, pointer, Vector3d(1, 2, 3), null),
      );

      SubLevelTrackingPointObserver(store).onSubLevelRemoved(subLevel, SubLevelRemovalReason.removed);

      final point = store.getTrackingPoint('p1')!;
      expect(point.inSubLevel, isFalse);
      expect(point.subLevelId, isNull);
      expect(point.lastSavedSubLevelPointer, isNull);
      expect(point.point.x, closeTo(101, 1e-9));
      expect(point.point.y, closeTo(66, 1e-9));
      expect(point.point.z, closeTo(-97, 1e-9));
      expect(point.globalPlaceholderPosition, isNull);
    });

    test('a point of another sub-level is left alone', () {
      subLevel.setLastSerializationPointer(const GlobalSavedSubLevelPointer(0, 0, 0, 0));
      final other = TrackingPoint(
        true,
        'other',
        const GlobalSavedSubLevelPointer(1, 1, 0, 0),
        Vector3d(1, 2, 3),
        null,
      );
      store.setTrackingPoint('p1', other);

      SubLevelTrackingPointObserver(store).onSubLevelRemoved(subLevel, SubLevelRemovalReason.removed);

      expect(store.getTrackingPoint('p1')!.inSubLevel, isTrue);
    });

    test('a point without a save pointer keeps its placeholder', () {
      store.setTrackingPoint('p1', TrackingPoint(true, subLevel.uniqueId, null, Vector3d(1, 2, 3), null));

      SubLevelTrackingPointObserver(store).onSubLevelRemoved(subLevel, SubLevelRemovalReason.removed);

      expect(store.getTrackingPoint('p1')!.inSubLevel, isTrue);
    });

    test('an unload does not project the point', () {
      final pointer = const GlobalSavedSubLevelPointer(0, 0, 0, 0);
      subLevel.setLastSerializationPointer(pointer);
      store.setTrackingPoint(
        'p1',
        TrackingPoint(true, subLevel.uniqueId, pointer, Vector3d(1, 2, 3), null),
      );

      SubLevelTrackingPointObserver(store).onSubLevelRemoved(subLevel, SubLevelRemovalReason.unloaded);

      expect(store.getTrackingPoint('p1')!.inSubLevel, isTrue);
    });
  });

  group('ServerSubLevelContainer force loading', () {
    test('the dependency chain includes the sub-levels it intersects', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);

      final a = addServerSubLevel(container, 0, 0, '00000000-0000-0000-0000-0000000000d1');
      final b = addServerSubLevel(container, 0, 1, '00000000-0000-0000-0000-0000000000d2');
      final far = addServerSubLevel(container, 2, 2, '00000000-0000-0000-0000-0000000000d3');

      a.updateBoundingBox();
      b.updateBoundingBox();
      far.updateBoundingBox();
      // Two plots next to each other share a face, so their bounds intersect.
      a.getPlot().setBoundingBox(BoundingBox3i.values(0, 0, 0, 4, 4, 4));
      b.getPlot().setBoundingBox(BoundingBox3i.values(4, 0, 0, 8, 4, 4));
      far.getPlot().setBoundingBox(BoundingBox3i.values(64, 0, 64, 68, 4, 68));
      a.updateBoundingBox();
      b.updateBoundingBox();
      far.updateBoundingBox();

      container.addForceLoadTicket(a, SubLevelLoadingTicketType.commandForced, 'a');

      final chain = container.collectForceLoadedSubLevels();
      expect(chain, contains(a));
      expect(chain, contains(b));
      expect(chain, isNot(contains(far)));
    });

    test('no tickets means no force-loaded sub-levels', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      addServerSubLevel(container, 0, 0, '00000000-0000-0000-0000-0000000000d4');

      expect(container.collectForceLoadedSubLevels(), isEmpty);
    });
  });

  group('sub-level lifecycle', () {
    late FakeLevel level;
    late FakeChunkHost host;
    late ServerSubLevelContainer container;

    setUp(() {
      level = FakeLevel();
      host = FakeChunkHost(level);
      container = makeContainer(level, host);
    });

    test('a plot with no blocks marks the sub-level removed', () {
      final subLevel = addServerSubLevel(container, 0, 0, '00000000-0000-0000-0000-0000000000f1');

      // A plot with no chunks reports `BoundingBox3i.empty`, which is the
      // inverted box Java also recognises (`ServerSubLevel.java:185-190`).
      subLevel.onPlotBoundsChanged();
      expect(subLevel.isRemoved(), isTrue);
    });

    test('non-empty plot bounds keep the sub-level alive', () {
      final subLevel = addServerSubLevel(container, 0, 0, '00000000-0000-0000-0000-0000000000f2');

      subLevel.getPlot().setBoundingBox(BoundingBox3i.values(0, 0, 0, 1, 1, 1));
      subLevel.onPlotBoundsChanged();
      expect(subLevel.isRemoved(), isFalse);
    });

    test('a global bounds range outside the y limits removes the sub-level', () {
      final strict = ServerSubLevelContainer(
        level,
        host,
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
        config: SableConfig(subLevelRemoveMin: 0, subLevelRemoveMax: 100),
      );
      SubLevelContainer.register(strict);
      final subLevel = addServerSubLevel(strict, 0, 0, '00000000-0000-0000-0000-0000000000f3');
      subLevel.getPlot().setBoundingBox(BoundingBox3i.values(0, 200, 0, 1, 201, 1));

      subLevel.tick();

      expect(subLevel.isRemoved(), isTrue);
    });

    test('a sub-level inside the y limits survives the tick', () {
      final strict = ServerSubLevelContainer(
        level,
        host,
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
        config: SableConfig(subLevelRemoveMin: 0, subLevelRemoveMax: 100),
      );
      SubLevelContainer.register(strict);
      final subLevel = addServerSubLevel(strict, 0, 0, '00000000-0000-0000-0000-0000000000f4');
      subLevel.getPlot().setBoundingBox(BoundingBox3i.values(0, 10, 0, 1, 11, 1));

      subLevel.tick();

      expect(subLevel.isRemoved(), isFalse);
    });

    test('splitting creates the heat map on the first tick', () {
      final strict = ServerSubLevelContainer(
        level,
        host,
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
        config: SableConfig(subLevelSplitting: true, subLevelSplittingHeatmapSteps: 1),
      );
      SubLevelContainer.register(strict);
      final subLevel = addServerSubLevel(strict, 0, 0, '00000000-0000-0000-0000-0000000000f5');

      subLevel.tick();

      expect(subLevel.heatMapManager, isNotNull);
    });

    test('splitting off leaves the heat map absent', () {
      final strict = ServerSubLevelContainer(
        level,
        host,
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
        config: SableConfig(subLevelSplitting: false),
      );
      SubLevelContainer.register(strict);
      final subLevel = addServerSubLevel(strict, 0, 0, '00000000-0000-0000-0000-0000000000f6');

      subLevel.tick();

      expect(subLevel.heatMapManager, isNull);
    });

    test('an invalid mass tracker destroys the blocks and removes the sub-level', () {
      final subLevel = addServerSubLevel(container, 0, 0, '00000000-0000-0000-0000-0000000000f7');
      final plot = subLevel.getPlot();
      final global = plot.toGlobal((0, 0));
      plot.newNonLitChunk(global);
      host.setBlock(global.$1 << 4, 0, global.$2 << 4, 'minecraft:stone');
      expect(host.chunks[global]!.blockAt(0, 0, 0), 'minecraft:stone');

      subLevel.massTracker = InvalidMass();
      container.processSubLevelRemovals();

      expect(subLevel.isRemoved(), isTrue);
      expect(container.getLoadedCount(), 0);
      // The block was replaced with air before the plot was dropped.
      expect(host.chunks[global]!.blockAt(0, 0, 0), 'minecraft:air');
    });

    test('the biome of the plot comes from the level at the pose', () {
      level.biome = 'minecraft:plains';
      final biomeHost = FakeChunkHost(level);
      final biomeContainer = makeContainer(level, biomeHost);
      SubLevelContainer.register(biomeContainer);
      final pose = Pose3d()..position().set(5, 6, 7);

      final subLevel = biomeContainer.allocateSubLevel(
        '00000000-0000-0000-0000-0000000000f8',
        0,
        0,
        pose,
      ) as ServerSubLevel;

      expect(subLevel.getPlot().biome, 'minecraft:plains');
    });

    test('forceUpdateGlobalBounds copies the current box into the last one', () {
      final subLevel = addServerSubLevel(container, 0, 0, '00000000-0000-0000-0000-0000000000f9');
      subLevel.getPlot().setBoundingBox(BoundingBox3i.values(0, 0, 0, 2, 2, 2));
      subLevel.updateBoundingBox();

      subLevel.forceUpdateGlobalBounds();

      expect(subLevel.lastGlobalBounds, subLevel.boundingBox);
    });
  });

  group('ServerSubLevelContainer.close', () {
    test('the physics pipeline is disposed', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final pipeline = ClosingPipeline();
      SubLevelPhysicsSystem(
        container: container,
        pipeline: pipeline,
        config: SableConfig(),
        serverConfig: SableServerConfig(),
      );

      container.close();

      expect(pipeline.disposed, isTrue);
    });
  });

  group('SubLevelTrackingSystem snapshot batching', () {
    late FakeLevel level;
    late FakeChunkHost host;
    late ServerSubLevelContainer container;
    late _RecordingSink sink;
    late SubLevelTrackingSystem tracking;

    setUp(() {
      level = FakeLevel();
      host = FakeChunkHost(level);
      host.players['p1'] = FakePlayer('p1', (0, 0, 0));
      container = makeContainer(level, host);
      SubLevelContainer.register(container);
      container.hostOrNull = _Host(host);
      sink = _RecordingSink();
      tracking = SubLevelTrackingSystem(
        container: container,
        config: SableConfig(subLevelTrackingRange: 10000),
        sink: sink,
      );
    });

    test('a player with only stop_moving updates gets no snapshot info', () {
      final subLevel = addServerSubLevel(container, 0, 0, '00000000-0000-0000-0000-0000000000e1');
      subLevel.logicalPose.position().set(1, 2, 3);
      tracking.tick(container);
      subLevel.logicalPose.position().set(10, 2, 3);
      tracking.tick(container);
      sink.clear();

      tracking.tick(container);

      expect(sink.ids, [ClientboundStopMovingSubLevelPacket.payloadId]);
    });

    test('seventeen moving sub-levels are two info payloads and two batches', () {
      for (var i = 0; i < 17; i++) {
        final subLevel = addServerSubLevel(
          container,
          i % 8,
          i ~/ 8,
          '00000000-0000-0000-0000-0000000001${i.toString().padLeft(2, '0')}',
        );
        subLevel.logicalPose.position().set(i.toDouble(), 2, 3);
        subLevel.lastNetworkedPose.set(Pose3d());
      }
      tracking.tick(container);
      sink.clear();

      for (final subLevel in container.serverSubLevels()) {
        subLevel.logicalPose.position().set(subLevel.logicalPose.position().x + 10, 2, 3);
      }
      tracking.tick(container);

      expect(sink.ids.where((id) => id == ClientboundSableSnapshotInfoDualPacket.payloadId), hasLength(2));
      final snapshots = sink.bodies
          .where((entry) => entry.$1 == ClientboundSableSnapshotDualPacket.payloadId)
          .toList();
      expect(snapshots, hasLength(2));
      expect((snapshots[0].$3 as ClientboundSableSnapshotDualPacket).entries, hasLength(16));
      expect((snapshots[1].$3 as ClientboundSableSnapshotDualPacket).entries, hasLength(1));
    });

    test('UDP sends one info datagram and then the batches', () {
      final udp = _RecordingUdp();
      tracking = SubLevelTrackingSystem(
        container: container,
        config: SableConfig(subLevelTrackingRange: 10000),
        sink: sink,
        udp: udp,
      );
      final subLevel = addServerSubLevel(container, 0, 0, '00000000-0000-0000-0000-0000000000e2');
      subLevel.logicalPose.position().set(1, 2, 3);
      tracking.tick(container);
      sink.clear();
      udp.datagrams.clear();

      subLevel.logicalPose.position().set(10, 2, 3);
      tracking.tick(container);

      expect(udp.datagrams, hasLength(2), reason: 'one info datagram and one batch');
      expect(sink.payloads, isEmpty, reason: 'movement went over UDP');
    });
  });
}

/// A contraption that records the partial tick its local pose was asked for.
final class _TickRecordingContraption implements KinematicContraption {
  final Map<(int, int, int), Object> providers;
  double? seenPartialTick;

  _TickRecordingContraption(this.providers);

  @override
  void sable$getLocalBounds(BoundingBox3i bounds) {}

  @override
  Object sable$blockGetter() => Object();

  @override
  MassData sable$getMassTracker() => FixedMass();

  @override
  Vector3d sable$getPosition(double partialTick) => Vector3d();

  @override
  Quaterniond sable$getOrientation(double partialTick) => Quaterniond();

  @override
  Map<(int, int, int), Object> sable$liftProviders() => providers;

  @override
  bool sable$shouldCollide() => false;

  @override
  bool sable$isValid() => true;

  @override
  Pose3d sable$getLocalPose(Pose3d dest, double partialTick) {
    seenPartialTick = partialTick;
    return dest;
  }
}

/// A lift provider that reports a lift group, so the recording path is used.
final class _GroupingLiftProvider implements BlockSubLevelLiftProvider {
  @override
  Direction sable$getNormal(BState state) => Direction.up;

  @override
  double sable$getParallelDragScalar() => 0;

  @override
  double sable$getDirectionlessDragScalar() => 0;

  @override
  double sable$getLiftScalar() => 1;

  @override
  void sable$contributeLiftAndDrag(
    LiftProviderContext ctx,
    ServerSubLevel subLevel,
    Pose3d? localPose,
    double timeStep,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
    Vector3d linearImpulse,
    Vector3d angularImpulse, [
    LiftProviderGroup? group,
  ]) {
    // `BlockSubLevelLiftProvider.contributeLiftAndDrag` records into the group;
    // the recorded total is what `_recordLiftGroups` reads.
    if (group == null) return;
    group.totalLift.add(Vector3d(0, 1, 0));
    group.liftCenter.fma(1.0, Vector3d(0.5, 0.5, 0.5));
    group.totalLiftStrength += 1.0;
  }
}

final class _PartialTick implements PartialPhysicsTickSource {
  @override
  final double partialPhysicsTick;

  _PartialTick(this.partialPhysicsTick);
}

final class _Host implements SubLevelHost {
  @override
  final FakeChunkHost chunks;

  _Host(this.chunks);

  @override
  Iterable<SablePlayer> get players => chunks.players.values;

  @override
  SablePlayer? playerById(String uuid) => chunks.players[uuid];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordingSink implements SablePayloadSink {
  final List<(String, String, SablePacket)> bodies = [];

  /// Forgets the payloads recorded so far.
  void clear() => bodies.clear();

  @override
  void sendPayload(String playerId, String payloadId, Uint8List body) {
    bodies.add((payloadId, playerId, SablePackets.decodeClientbound(payloadId, body)));
  }

  List<(String, SablePacket)> get payloads => [for (final entry in bodies) (entry.$1, entry.$3)];

  List<String> get ids => [for (final entry in bodies) entry.$1];
}

final class _RecordingUdp implements SableUdpSender {
  final List<(String, Uint8List)> datagrams = [];

  @override
  bool isConnected(String playerId) => true;

  @override
  void sendDatagram(String playerId, Uint8List datagram) => datagrams.add((playerId, datagram));
}
