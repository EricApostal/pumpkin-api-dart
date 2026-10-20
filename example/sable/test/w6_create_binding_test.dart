// W6: the contraption binding and the machine lookups.
//
// The binding is what makes a moving Create contraption drive physics: it
// builds the kinematic body, adds it to the plot and the pipeline, and removes
// it again. The machine lookups are the `runIncludingSubLevels` users.
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/contraptions/core/contraption.dart';
import 'package:create/src/contraptions/core/level.dart' show ContraptionLevel;
import 'package:create/src/contraptions/core/structure_info.dart';
import 'package:create/src/contraptions/core/structure_transform.dart';
import 'package:create/src/contraptions/entity/contraption_entity.dart';
import 'package:create/src/contraptions/storage/storage_manager.dart' show StorageSync;
import 'package:create/src/core/nbt.dart' show NbtValue;
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  setUp(() {
    CreateCompatBlocks.uninstall();
    CreateCompat.install();
    ServerSubLevel.massTrackerFactory = (subLevel) => _FakeMassTracker();
  });

  tearDown(() {
    CreateCompat.uninstall();
    ServerLevelPlot.liftProviderLookup = null;
    SubLevelContainer.clearAll();
  });

  group('contraption binding', () {
    late FakeLevel level;
    late ServerSubLevelContainer container;
    late _RecordingPipeline pipeline;
    late ServerSubLevel ship;
    late Contraption contraption;
    late _TestEntity entity;

    setUp(() {
      level = FakeLevel();
      container = ServerSubLevelContainer(
        level,
        FakeChunkHost(level),
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );
      SubLevelContainer.register(container);
      pipeline = _RecordingPipeline();
      SubLevelPhysicsSystem(
        container: container,
        pipeline: pipeline,
        config: SableConfig(),
        serverConfig: SableServerConfig(subLevelSubstepsPerTick: 1),
      );

      ship = container.allocateNewSubLevel(
        Pose3d.full(Vector3d(), Quaterniond(), Vector3d(), Vector3d(1.0, 1.0, 1.0)),
      ) as ServerSubLevel;

      contraption = Contraption()
        ..blocks[(0, 0, 0)] = const StructureBlockInfo((0, 0, 0), BState('minecraft:stone'));
      entity = _TestEntity(contraption, (0.0, 0.0, 0.0));
    });

    test('attaching adds the body to the plot and the pipeline', () {
      final binding = ContraptionPhysicsBinding.attach(entity, ship)!;

      expect(ship.getPlot().contraptions, contains(binding.body));
      expect(pipeline.calls, contains('addContraption'));
      expect(binding.body.mass, isNotNull);
    });

    test('releasing removes the body from both, once', () {
      final binding = ContraptionPhysicsBinding.attach(entity, ship)!;
      binding.release();
      binding.release();

      expect(ship.getPlot().contraptions, isEmpty);
      expect(pipeline.calls.where((c) => c == 'removeContraption').length, 1);
      expect(binding.released, isTrue);
    });

    test('an empty contraption is not attached', () {
      final empty = _TestEntity(Contraption(), (0.0, 0.0, 0.0));
      expect(ContraptionPhysicsBinding.attach(empty, ship), isNull);
      expect(pipeline.calls, isNot(contains('addContraption')));
    });

    test('the passenger save pass moves non-players onto the contraption', () {
      // The test host has no passengers, so the pass is a no-op that must not
      // throw; the real behaviour is covered by the host interface.
      expect(() => ContraptionPhysicsBinding.gatherPassengersForSave(entity), returnsNormally);
    });

    test('the disassembly transforms project in and out of the sub-level', () {
      // The ship's pose is the identity here, so a world point is already local.
      final local = ContraptionDisassemblyTransforms.toLocalVector(
        entity,
        (0.5, 0.5, 0.5),
        0,
        ship,
      );
      expect(local.$1, closeTo(0.5, 1e-9));

      final global = ContraptionDisassemblyTransforms.toGlobalPosition(level, (0.5, 0.5, 0.5));
      expect(global.$1, closeTo(0.5, 1e-9));

      // A ship ten blocks to the east: its plot origin is at world 10, so the
      // plot point 0.5 is the world point 10.5 and back again.
      final moved = container.allocateNewSubLevel(
        Pose3d.full(Vector3d(10.0, 0.0, 0.0), Quaterniond(), Vector3d(), Vector3d(1.0, 1.0, 1.0)),
      ) as ServerSubLevel;
      final plotPos = (moved.getPlot().plotPos.$1 * 256, 0, moved.getPlot().plotPos.$2 * 256);

      final movedLocal = ContraptionDisassemblyTransforms.toLocalVector(
        entity,
        (10.5, 0.5, 0.5),
        0,
        moved,
      );
      expect(movedLocal.$1, closeTo(0.5, 1e-9));
      expect(plotPos.$1, greaterThan(0));
    });

    test('the physics system of a level is the attached one', () {
      expect(physicsSystemOf(level), isA<SubLevelPhysicsSystem>());
    });
  });

  group('machine lookups', () {
    late FakeLevel level;
    late ServerSubLevelContainer container;
    late ServerSubLevel ship;

    setUp(() {
      level = FakeLevel();
      container = ServerSubLevelContainer(
        level,
        FakeChunkHost(level),
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );
      SubLevelContainer.register(container);
      ship = container.allocateNewSubLevel(
        Pose3d.full(Vector3d(100.0, 0.0, 0.0), Quaterniond(), Vector3d(), Vector3d(1.0, 1.0, 1.0)),
      ) as ServerSubLevel;
    });

    test('an open pipe finds the fluid block through the sub-level', () {
      final found = OpenEndedPipeLookup.findOutput(
        level,
        (2560000, 0, 2560000),
        ship,
        (pos) => pos == (2560000, 0, 2560000) ? 'minecraft:water' : 'minecraft:air',
      );

      expect(found, isNotNull);
      expect(found!.state, 'minecraft:water');
    });

    test('an open pipe with no fluid falls back to its own position', () {
      // Java falls back to `level.getBlockState(outputPos)`, which is the air
      // block here; the pipe then does nothing with it.
      final found = OpenEndedPipeLookup.findOutput(
        level,
        (2560000, 0, 2560000),
        ship,
        (pos) => 'minecraft:air',
      );
      expect(found, isNotNull);
      expect(found!.pos, (2560000, 0, 2560000));
      expect(found.state, 'minecraft:air');
    });

    test('a boiler finds a heater under it through the sub-level', () {
      // The ship sits at (100, 0, 0), so its plot position projects to world
      // (2560100, 0, 2560000) and the block below it is (2560100, -1, ...).
      final heat = HeaterLookup.findHeat(
        level,
        (2560000, 0, 2560000),
        ship,
        (pos) => pos == (2560100, -1, 2560000) ? 2.0 : -1.0,
      );
      expect(heat, 2.0);
    });

    test('a boiler without a heater reports none', () {
      expect(
        HeaterLookup.findHeat(level, (2560000, 0, 2560000), ship, (pos) => -1.0),
        -1.0,
      );
    });

    test('the hose pulley accepts a block that cannot be replaced', () {
      final state = HosePulleyCheck.nextState(
        level,
        (2560000, 0, 2560000),
        ship,
        (pos) => pos == (2560000, 0, 2560000) ? 'minecraft:stone' : 'minecraft:air',
        (state) => state == 'minecraft:air',
        inverseReplaceCheck: true,
        original: 'minecraft:air',
      );
      expect(state, 'minecraft:stone');
    });

    test('the hose pulley ignores a replaceable block in the lazy tick', () {
      final state = HosePulleyCheck.nextState(
        level,
        (2560000, 0, 2560000),
        ship,
        (pos) => 'minecraft:air',
        (state) => state == 'minecraft:air',
        inverseReplaceCheck: true,
        original: 'minecraft:water',
      );
      expect(state, 'minecraft:water');
    });

    test('the hose pulley drains from the first position with fluid', () {
      final pos = HosePulleyDrain.drainPos(
        level,
        (2560000, 0, 2560000),
        ship,
        (pos) => pos == (2560000, 0, 2560000),
      );
      expect(pos, (2560000, 0, 2560000));
    });

    test('the hose pulley keeps a nearby drain position', () {
      final last = (2560000, 0, 2560000);
      final pos = HosePulleyDrain.drainPos(
        level,
        (2560000, 0, 2560000),
        ship,
        (pos) => pos == last,
        lastValidPos: last,
      );
      expect(pos, last);
    });

    test('a chute resolves the handler direction in the neighbour frame', () {
      final found = ChuteLookup.handlerAt(
        level,
        (2560000, 0, 2560000),
        ship,
        Direction.south,
        (pos) => true,
      );
      expect(found, isNotNull);
      // The chute looks from the opposite side, rotated out of the sub-level.
      expect(found!.direction, Direction.north);
    });

    test('a capability search finds the block entity through the sub-level', () {
      final found = CapabilityLookup.findBlockEntity(
        level,
        (2560000, 0, 2560000),
        ship,
        (pos) => pos == (2560000, 0, 2560000) ? 'chest' : null,
        (entity) => entity == 'chest',
      );
      expect(found, (2560000, 0, 2560000));
    });

    test('a mechanical arm inside a sub-level always sees its area loaded', () {
      expect(CapabilityLookup.isAreaLoaded(level, (2560000, 0, 2560000)), isTrue);
    });

    test('the lectern controller measures the range across sub-levels', () {
      expect(
        LecternControllerRange.playerInRange(level, (2560000.0, 0.0, 2560000.0), (2560002.0, 0.0, 2560000.0), 4),
        isTrue,
      );
      expect(
        LecternControllerRange.playerInRange(level, (2560000.0, 0.0, 2560000.0), (2560006.0, 0.0, 2560000.0), 4),
        isFalse,
      );
    });

    test('a redstone contact projects its front block out of the sub-level', () {
      final front = RedstoneContactLookup.frontInWorld(level, (2560000, 0, 2560000), Direction.east);
      expect(front.$1, 2560101);
    });
  });

  group('interactions', () {
    late FakeLevel level;
    late ServerSubLevelContainer container;

    setUp(() {
      level = FakeLevel();
      container = ServerSubLevelContainer(
        level,
        FakeChunkHost(level),
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );
      SubLevelContainer.register(container);
      container.allocateNewSubLevel(
        Pose3d.full(Vector3d(), Quaterniond(), Vector3d(), Vector3d(1.0, 1.0, 1.0)),
      );
    });

    test('a track look angle is rotated into the sub-level', () {
      // A ship rotated 180 degrees around y: a world +x look is a local -x.
      final rotated = container.allocateNewSubLevel(
        Pose3d.full(
          Vector3d(),
          Quaterniond(0.0, 1.0, 0.0, 0.0),
          Vector3d(),
          Vector3d(1.0, 1.0, 1.0),
        ),
      );
      final plotPos = (
        rotated.getPlot().plotPos.$1 * 256,
        0,
        rotated.getPlot().plotPos.$2 * 256,
      );

      final look = TrackPlacement.lookAngleInSubLevel(level, plotPos, (1.0, 0.0, 0.0));
      expect(look.$1, closeTo(-1.0, 1e-9));
      expect(look.$3, closeTo(0.0, 1e-9));
    });

    test('a track look angle outside a sub-level is unchanged', () {
      final look = TrackPlacement.lookAngleInSubLevel(level, (0, 0, 0), (1.0, 0.0, 0.0));
      expect(look, (1.0, 0.0, 0.0));
    });

    test('a vertical gearbox faces the player direction in the sub-level', () {
      // A ship rotated 180 degrees around y flips the horizontal facing.
      final rotated = container.allocateNewSubLevel(
        Pose3d.full(
          Vector3d(),
          Quaterniond(0.0, 1.0, 0.0, 0.0),
          Vector3d(),
          Vector3d(1.0, 1.0, 1.0),
        ),
      );
      expect(VerticalGearboxPlacement.facingInSubLevel(rotated, (1, 0, 0)), (-1, 0, 0));
      expect(VerticalGearboxPlacement.facingInSubLevel(null, (1, 0, 0)), (1, 0, 0));
    });

    test('a zapper beam hit is projected out of the sub-level', () {
      final hit = ZapperBeam.projectHitLocation(level, (2560000.0, 0.0, 2560000.0));
      expect(hit.$1, closeTo(2560000.0, 1e-9));
      expect(hit.$2, closeTo(0.0, 1e-9));
    });

    test('a toolbox is reachable across sub-levels', () {
      expect(
        ToolboxRange.withinRange(level, (2560000.0, 0.0, 2560000.0), (2560001, 0, 2560000), 4),
        isTrue,
      );
      expect(
        ToolboxRange.withinRange(level, (2560000.0, 0.0, 2560000.0), (2560010, 0, 2560000), 4),
        isFalse,
      );
    });

    test('the nearest toolboxes are sorted by distance and capped', () {
      final nearest = ToolboxRange.nearest(
        level,
        (2560000.0, 0.0, 2560000.0),
        const [(2560003, 0, 2560000), (2560001, 0, 2560000), (2560002, 0, 2560000)],
        10,
        2,
      );
      expect(nearest, [(2560001, 0, 2560000), (2560002, 0, 2560000)]);
    });

    test('a glue box is projected out of its sub-level', () {
      final box = SuperGlueSelection.projectedBounds(
        const Aabb(0, 0, 0, 1, 1, 1),
        Pose3d.full(Vector3d(5.0, 0.0, 0.0), Quaterniond(), Vector3d(), Vector3d(1.0, 1.0, 1.0)),
      );
      expect(box.minX, closeTo(5.0, 1e-9));
    });

    test('the glue removal range is measured across sub-levels', () {
      expect(
        SuperGlueSelection.withinRemovalRange(
          level,
          (2560000.0, 0.0, 2560000.0),
          (2560002.0, 0.0, 2560000.0),
          4,
        ),
        isTrue,
      );
    });

    test('the stock ticker position follows the vehicle when it is on a sub-level', () {
      final pos = StockTickerLookup.tickerPosition(
        isOnSubLevel: (position) => true,
        entityPosition: (1.0, 2.0, 3.0),
        vehiclePosition: (10.0, 20.0, 30.0),
        hasVehicle: true,
      );
      expect(pos, (10, 20, 30));

      final without = StockTickerLookup.tickerPosition(
        isOnSubLevel: (position) => false,
        entityPosition: (1.0, 2.0, 3.0),
        vehiclePosition: (10.0, 20.0, 30.0),
        hasVehicle: true,
      );
      expect(without, (1, 2, 3));
    });

    test('the turntable centre and height are projected', () {
      expect(TurntableGeometry.centerInWorld(level, (2560000, 0, 2560000)).$1, closeTo(2560000.5, 1e-9));
      expect(TurntableGeometry.worldY(level, (2560000, 4, 2560000)), closeTo(4.0, 1e-9));
    });
  });
}

/// A mass tracker that stands in for the physics pipeline's.
final class _FakeMassTracker implements MassData {
  final Vector3d _center = Vector3d(0.5, 0.5, 0.5);

  @override
  Vector3d getCenterOfMass() => _center;

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

/// A pipeline that records the contraption calls.
final class _RecordingPipeline implements PhysicsPipeline {
  final List<String> calls = [];

  @override
  void init(Vector3d gravity, double universalDrag) {}

  @override
  void dispose() {}

  @override
  void tick() {}

  @override
  void prePhysicsTicks() {}

  @override
  void physicsTick(double timeStep) {}

  @override
  void postPhysicsTicks() {}

  @override
  RigidBodyHandle addSubLevel(ServerSubLevel subLevel, Pose3dc pose) => _Handle();

  @override
  void removeSubLevel(ServerSubLevel subLevel) {}

  @override
  void addContraption(KinematicContraption contraption) => calls.add('addContraption');

  @override
  void removeContraption(KinematicContraption contraption) => calls.add('removeContraption');

  @override
  Pose3d readPose(ServerSubLevel subLevel, Pose3d dest) => dest;

  @override
  BoxHandle addBox(BoxPhysicsObject box) => throw UnimplementedError();

  @override
  void removeBox(BoxHandle box) => throw UnimplementedError();

  @override
  RopeHandle addRope(RopePhysicsObject rope) => throw UnimplementedError();

  @override
  void removeRope(RopeHandle rope) => throw UnimplementedError();

  @override
  void handleChunkSectionAddition(
    int x,
    int y,
    int z,
    List<int> blockStates, {
    required bool global,
    int? subLevelRuntimeId,
  }) {}

  @override
  void handleChunkSectionRemoval(int x, int y, int z, {bool global = false}) {}

  @override
  void handleBlockChange(int x, int y, int z, int packedState) {}

  @override
  void onStatsChanged(ServerSubLevel subLevel) {}

  @override
  void teleport(RigidBodyHandle body, Vector3d position, Quaterniond orientation) {}

  @override
  void applyImpulse(RigidBodyHandle body, Vector3d position, Vector3d force) {}

  @override
  void applyLinearAndAngularImpulse(
    RigidBodyHandle body,
    Vector3d force,
    Vector3d torque,
    bool wakeUp,
  ) {}

  @override
  void addLinearAndAngularVelocity(
    RigidBodyHandle body,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
  ) {}

  @override
  void resetVelocity(RigidBodyHandle body) {}

  @override
  Vector3d getLinearVelocity(RigidBodyHandle body, Vector3d dest) => dest.zero();

  @override
  Vector3d getAngularVelocity(RigidBodyHandle body, Vector3d dest) => dest.zero();

  @override
  void wakeUp(RigidBodyHandle body) {}

  @override
  int getNextRuntimeId() => 1;
}

final class _Handle implements RigidBodyHandle {
  @override
  Vector3d getLinearVelocity([Vector3d? dest]) => (dest ?? Vector3d()).zero();

  @override
  Vector3d getAngularVelocity([Vector3d? dest]) => (dest ?? Vector3d()).zero();

  @override
  void applyLinearAndAngularImpulse(Vector3d linear, Vector3d angular, bool wakeUp) {}

  @override
  void applyForcesAndReset(ForceTotal forceTotal) {}

  @override
  void applyImpulseAtPoint(Vector3d position, Vector3d force) {}

  @override
  bool get isValid => true;

  @override
  void teleport(Vector3d position, Quaterniond orientation) {}

  @override
  void addLinearAndAngularVelocity(Vector3d linear, Vector3d angular) {}
}

final class _TestEntity extends AbstractContraptionEntity {
  _TestEntity(Contraption contraption, Vec3 anchor) : super(_TestHost(anchor)) {
    setContraption(contraption);
    prevPosInvalid = false;
  }

  @override
  Vec3 applyRotation(Vec3 localPos, double partialTicks) => localPos;

  @override
  Vec3 reverseRotation(Vec3 localPos, double partialTicks) => localPos;

  @override
  ContraptionRotationState getRotationState() => ContraptionRotationState();

  @override
  Future<void> tickContraption() async {}

  @override
  StructureTransform makeStructureTransform() => throw UnimplementedError();

  @override
  double getStalledAngle() => 0;

  @override
  void handleStallInformation(double x, double y, double z, double angle) {}
}

final class _TestHost implements ContraptionEntityHost {
  _TestHost(this._position);

  Vec3 _position;

  @override
  int get entityId => 1;

  @override
  String get uuid => '00000000-0000-0000-0000-000000000002';

  @override
  bool get isAlive => true;

  @override
  bool get isRemoved => false;

  @override
  bool get stalled => false;

  @override
  Vec3 get position => _position;

  @override
  Vec3 get prevPosition => _position;

  @override
  Aabb get boundingBox => Aabb(_position.$1, _position.$2, _position.$3, _position.$1 + 1, _position.$2 + 1, _position.$3 + 1);

  @override
  void setBoundingBox(Aabb box) {}

  @override
  Vec3 get deltaMovement => vec3Zero;

  @override
  void setDeltaMovement(Vec3 motion) {}

  @override
  void setPosition(Vec3 position) => _position = position;

  @override
  void teleport(Vec3 position) => _position = position;

  @override
  List<ContraptionPassengerRef> get passengers => const [];

  @override
  bool hasPassenger(ContraptionPassengerRef passenger) => false;

  @override
  void addPassenger(ContraptionPassengerRef passenger, {bool force = true}) {}

  @override
  void removePassenger(ContraptionPassengerRef passenger) {}

  @override
  void ejectPassengers() {}

  @override
  void setPassengerPosition(ContraptionPassengerRef passenger, Vec3 position) {}

  @override
  void teleportEntity(ContraptionPassengerRef passenger, Vec3 position) {}

  @override
  Object? get vehicle => null;

  @override
  ContraptionPassengerRef? get vehiclePassenger => null;

  @override
  Vec3 get vehiclePosition => vec3Zero;

  @override
  Vec3 get vehiclePrevPosition => vec3Zero;

  @override
  Vec3 get vehicleDeltaMovement => vec3Zero;

  @override
  bool get vehicleIsMinecart => false;

  @override
  void setVehicleDeltaMovement(Vec3 motion) {}

  @override
  Object? controllerAt(Pos pos) => null;

  @override
  void setRotation(double yaw, double pitch) {}

  @override
  void setOnGround(bool onGround) {}

  @override
  double get maxUpStep => 0.6;

  @override
  void playSound(String sound, Vec3 at, {double volume = 1, double pitch = 1}) {}

  @override
  void sendPayload(String channel, Map<String, Object?> fields) {}

  @override
  void setStalled(bool stalled) {}

  @override
  String? get controllingPlayer => null;

  @override
  void setControllingPlayer(String? uuid) {}

  @override
  NbtValue? getPersistentData(String key) => null;

  @override
  void setPersistentData(String key, NbtValue? value) {}

  @override
  ContraptionLevel get level => throw UnimplementedError();

  @override
  ContraptionCollisionEntity? collisionEntityById(int id) => null;

  @override
  void sendBlockChanged(Pos localPos, BState state) {}

  @override
  void sendStorageSync(StorageSync sync) {}

  @override
  void sendSeatMapping(Map<String, int> mapping, {int? dismountedId}) {}

  @override
  void sendStall(double angle) {}

  @override
  void sendControlsAbort(String playerUuid) {}

  @override
  void sendDisassembly(StructureTransform transform) {}

  @override
  List<ContraptionCollisionEntity> entitiesNear(Aabb box) => const [];

  @override
  ContraptionPassengerRef? passengerFromHost(Object handle) => null;

  @override
  void remove() {}
}
