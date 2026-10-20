// Round-trip and byte-layout tests for every Sable payload.
//
// The wire is read by the real Sable client, so the tests do two things:
//
// 1. encode → decode → compare, for every payload;
// 2. for the hand-written codecs, re-encode the value with a `PacketWriter` in
//    the Java `write` order and require the two byte arrays to be identical.
//    That pins the field order, not just self-consistency.
//
// The NBT-backed payloads (`physics_property`, `floating_material`) are checked
// by decoding the tag and looking at the field names and kinds the Java codec
// reads.
import 'dart:typed_data';

// create's barrel re-exports the host bridge (wasm); the NBT model is pure.
// ignore_for_file: implementation_imports
import 'package:create/src/core/nbt.dart' show NbtKind, NetworkNbt;
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

Pose3d pose(double x, double y, double z, double qx, double qy, double qz, double qw) =>
    Pose3d()
      ..position().set(x, y, z)
      ..orientation().set(qx, qy, qz, qw)
      ..rotationPoint().set(x - 1, y - 2, z - 3);

void main() {
  group('tracking payloads', () {
    test('start_tracking_sublevel round-trips', () {
      final packet = ClientboundStartTrackingSubLevelPacket(
        plotCoordinate: 0x0000000200000003,
        subLevelId: '00112233-4455-6677-8899-aabbccddeeff',
        lastPose: pose(1, 2, 3, 0, 0, 0, 1),
        pose: pose(4, 5, 6, 0.5, 0.5, 0.5, 0.5),
        bounds: BoundingBox3i.values(-8, 0, -8, 8, 32, 8),
        name: 'airship',
        gameTick: 1234,
      );

      final decoded = ClientboundStartTrackingSubLevelPacket.codec.decode(
        ClientboundStartTrackingSubLevelPacket.codec.encode(packet),
      );

      expect(decoded.plotCoordinate, packet.plotCoordinate);
      expect(decoded.subLevelId, packet.subLevelId);
      expect(decoded.name, 'airship');
      expect(decoded.gameTick, 1234);
      expect(decoded.bounds, packet.bounds);
      expect(decoded.lastPose.position().x, 1.0);
      expect(decoded.pose.position().y, 5.0);
      expect(decoded.pose.orientation().w, 0.5);
      expect(decoded.pose.rotationPoint().z, 3.0);
    });

    test('start_tracking_sublevel without a name', () {
      final packet = ClientboundStartTrackingSubLevelPacket(
        plotCoordinate: 7,
        subLevelId: '00112233-4455-6677-8899-aabbccddeeff',
        lastPose: pose(0, 0, 0, 0, 0, 0, 1),
        pose: pose(0, 0, 0, 0, 0, 0, 1),
        bounds: BoundingBox3i.values(0, 0, 0, 1, 1, 1),
        gameTick: 0,
      );

      final bytes = ClientboundStartTrackingSubLevelPacket.codec.encode(packet);
      final decoded = ClientboundStartTrackingSubLevelPacket.codec.decode(bytes);
      expect(decoded.name, isNull);
    });

    test('start_tracking_sublevel field order is Java order', () {
      final packet = ClientboundStartTrackingSubLevelPacket(
        plotCoordinate: 9,
        subLevelId: '00112233-4455-6677-8899-aabbccddeeff',
        lastPose: pose(1, 2, 3, 0, 0, 0, 1),
        pose: pose(4, 5, 6, 0, 0, 0, 1),
        bounds: BoundingBox3i.values(-1, -2, -3, 4, 5, 6),
        name: 'n',
        gameTick: 42,
      );

      // writeLong, writeUUID, pose, pose, bounds, bool + utf, int
      final expected = PacketWriter()
        ..writeLong(9)
        ..writeUuid('00112233-4455-6677-8899-aabbccddeeff');
      SableBufferUtils.writePose(expected, packet.lastPose);
      SableBufferUtils.writePose(expected, packet.pose);
      SableBufferUtils.writeBounds(expected, packet.bounds);
      expected
        ..writeBool(true)
        ..writeString('n')
        ..writeInt(42);

      expect(
        ClientboundStartTrackingSubLevelPacket.codec.encode(packet),
        expected.toBytes(),
      );
    });

    test('finalize_sub_level round-trips and is one long', () {
      final codec = ClientboundFinalizeSubLevelPacket.codec;
      final packet = ClientboundFinalizeSubLevelPacket(0x1122334455667788);

      expect(codec.encode(packet), (PacketWriter()..writeLong(0x1122334455667788)).toBytes());
      expect(codec.decode(codec.encode(packet)).plotCoordinate, 0x1122334455667788);
    });

    test('stop_tracking_sublevel round-trips and is one long', () {
      final codec = ClientboundStopTrackingSubLevelPacket.codec;
      final packet = ClientboundStopTrackingSubLevelPacket(-5);

      expect(codec.encode(packet), (PacketWriter()..writeLong(-5)).toBytes());
      expect(codec.decode(codec.encode(packet)).plotCoordinate, -5);
    });

    test('stop_moving_sublevel round-trips and is one long', () {
      final codec = ClientboundStopMovingSubLevelPacket.codec;
      final packet = ClientboundStopMovingSubLevelPacket(77);

      expect(codec.encode(packet), (PacketWriter()..writeLong(77)).toBytes());
      expect(codec.decode(codec.encode(packet)).plotCoordinate, 77);
    });

    test('change_bounds_sublevel round-trips and is long + six ints', () {
      final codec = ClientboundChangeBoundsSubLevelPacket.codec;
      final packet = ClientboundChangeBoundsSubLevelPacket(
        3,
        BoundingBox3i.values(-16, -64, -16, 31, 319, 31),
      );

      final expected = PacketWriter()
        ..writeLong(3)
        ..writeInt(-16)
        ..writeInt(-64)
        ..writeInt(-16)
        ..writeInt(31)
        ..writeInt(319)
        ..writeInt(31);

      expect(codec.encode(packet), expected.toBytes());
      expect(codec.decode(codec.encode(packet)).bounds, packet.bounds);
    });

    test('change_sub_level_name round-trips with and without a name', () {
      final codec = ClientboundChangeSubLevelNamePacket.codec;

      final named = ClientboundChangeSubLevelNamePacket('00112233-4455-6677-8899-aabbccddeeff', 'x');
      final expected = PacketWriter()
        ..writeUuid('00112233-4455-6677-8899-aabbccddeeff')
        ..writeBool(true)
        ..writeString('x');
      expect(codec.encode(named), expected.toBytes());

      final decodedNamed = codec.decode(codec.encode(named));
      expect(decodedNamed.name, 'x');
      expect(decodedNamed.subLevelId, named.subLevelId);

      final cleared = ClientboundChangeSubLevelNamePacket(named.subLevelId, null);
      final expectedCleared = PacketWriter()
        ..writeUuid('00112233-4455-6677-8899-aabbccddeeff')
        ..writeBool(false);
      expect(codec.encode(cleared), expectedCleared.toBytes());
      expect(codec.decode(codec.encode(cleared)).name, isNull);
    });

    test('recently_split_sub_level round-trips and is uuid + uuid + pose', () {
      final codec = ClientboundRecentlySplitSubLevelPacket.codec;
      final packet = ClientboundRecentlySplitSubLevelPacket(
        splitSubLevelId: '00112233-4455-6677-8899-aabbccddeeff',
        splitFromId: 'ffeeddcc-bbaa-9988-7766-554433221100',
        pose: pose(7, 8, 9, 0, 0, 0, 1),
      );

      final expected = PacketWriter()
        ..writeUuid('00112233-4455-6677-8899-aabbccddeeff')
        ..writeUuid('ffeeddcc-bbaa-9988-7766-554433221100');
      SableBufferUtils.writePose(expected, packet.pose);

      expect(codec.encode(packet), expected.toBytes());
      final decoded = codec.decode(codec.encode(packet));
      expect(decoded.splitSubLevelId, packet.splitSubLevelId);
      expect(decoded.splitFromId, packet.splitFromId);
      expect(decoded.pose.position().y, 8.0);
    });
  });

  group('snapshot payloads', () {
    test('snapshot_packet round-trips', () {
      final codec = ClientboundSableSnapshotDualPacket.codec;
      final packet = ClientboundSableSnapshotDualPacket(55, [
        SnapshotEntry(
          plotCoordinate: 1,
          pose: pose(1, 2, 3, 0, 0, 0, 1),
          linearVelocity: Vector3d(0.5, -1.5, 2.5),
          angularVelocity: Vector3d(0.25, 0.0, -0.25),
        ),
        SnapshotEntry(
          plotCoordinate: 2,
          pose: pose(4, 5, 6, 0, 0, 0, 1),
          linearVelocity: Vector3d(0, 0, 0),
          angularVelocity: Vector3d(0, 0, 0),
        ),
      ]);

      final decoded = codec.decode(codec.encode(packet));
      expect(decoded.interpolationTick, 55);
      expect(decoded.entries.length, 2);
      expect(decoded.entries[0].plotCoordinate, 1);
      expect(decoded.entries[0].linearVelocity.y, -1.5);
      expect(decoded.entries[1].pose.position().z, 6.0);
    });

    test('snapshot_packet field order is Java order', () {
      final packet = ClientboundSableSnapshotDualPacket(3, [
        SnapshotEntry(
          plotCoordinate: 10,
          pose: pose(1, 2, 3, 0, 0, 0, 1),
          linearVelocity: Vector3d(1, 2, 3),
          angularVelocity: Vector3d(4, 5, 6),
        ),
      ]);

      final expected = PacketWriter()
        ..writeInt(3)
        ..writeVarInt(1)
        ..writeLong(10);
      SableBufferUtils.writePose(expected, packet.entries[0].pose);
      SableBufferUtils.writeVector3f(expected, Vector3d(1, 2, 3));
      SableBufferUtils.writeVector3f(expected, Vector3d(4, 5, 6));

      expect(ClientboundSableSnapshotDualPacket.codec.encode(packet), expected.toBytes());
    });

    test('snapshot_info_packet round-trips and is int, int, bool', () {
      final codec = ClientboundSableSnapshotInfoDualPacket.codec;
      final packet = ClientboundSableSnapshotInfoDualPacket(
        msSinceLast: 50,
        gameTick: 9,
        stopped: true,
      );

      final expected = PacketWriter()
        ..writeInt(50)
        ..writeInt(9)
        ..writeBool(true);

      expect(codec.encode(packet), expected.toBytes());
      final decoded = codec.decode(codec.encode(packet));
      expect(decoded.msSinceLast, 50);
      expect(decoded.gameTick, 9);
      expect(decoded.stopped, isTrue);
    });

    test('an empty snapshot is legal', () {
      final codec = ClientboundSableSnapshotDualPacket.codec;
      final bytes = codec.encode(ClientboundSableSnapshotDualPacket(1, const []));
      expect(bytes, (PacketWriter()..writeInt(1)..writeVarInt(0)).toBytes());
      expect(codec.decode(bytes).entries, isEmpty);
    });
  });

  group('physics config payloads', () {
    test('physics_property round-trips', () {
      final codec = ClientboundPhysicsPropertyPacket.codec;
      final packet = ClientboundPhysicsPropertyPacket(
        PhysicsBlockPropertiesDefinition(
          selector: const TagOrElementLocation('minecraft:logs', tag: true),
          priority: 500,
          properties: {
            PhysicsBlockPropertyTypes.mass: 2.5,
            PhysicsBlockPropertyTypes.friction: 0.7,
            PhysicsBlockPropertyTypes.fragile: true,
            PhysicsBlockPropertyTypes.inertia: (1.0, 2.0, 3.0),
            PhysicsBlockPropertyTypes.floatingMaterial: 'sable:air',
          },
          overrides: {
            BlockStateConditionSet.parse('waterlogged=true'): {
              PhysicsBlockPropertyTypes.mass: 4.0,
            },
          },
        ),
      );

      final decoded = codec.decode(codec.encode(packet));
      final definition = decoded.definition;

      expect(definition.selector, const TagOrElementLocation('minecraft:logs', tag: true));
      expect(definition.priority, 500);
      expect(definition.properties[PhysicsBlockPropertyTypes.mass], 2.5);
      expect(definition.properties[PhysicsBlockPropertyTypes.fragile], isTrue);
      expect(definition.properties[PhysicsBlockPropertyTypes.inertia], (1.0, 2.0, 3.0));
      expect(definition.overrides!.keys.single.toString(), 'waterlogged=true');
      expect(definition.overrides!.values.single[PhysicsBlockPropertyTypes.mass], 4.0);
    });

    test('physics_property NBT uses the codec field names and omits defaults', () {
      final packet = ClientboundPhysicsPropertyPacket(
        const PhysicsBlockPropertiesDefinition(
          selector: TagOrElementLocation('minecraft:stone'),
          properties: {PhysicsBlockPropertyTypes.mass: 1.0},
        ),
      );

      final bytes = ClientboundPhysicsPropertyPacket.codec.encode(packet);
      final root = NetworkNbt.decode(bytes)!;
      final map = root.asCompound;

      expect(map['selector']!.kind, NbtKind.string);
      expect(map['selector']!.value, 'minecraft:stone');
      // Default priority (1000) and absent overrides are omitted, like
      // optionalFieldOf.
      expect(map.containsKey('priority'), isFalse);
      expect(map.containsKey('overrides'), isFalse);
      expect(map['properties']!.kind, NbtKind.compound);
      expect(map['properties']!.asCompound['sable:mass']!.kind, NbtKind.double);
    });

    test('floating_material round-trips', () {
      final codec = ClientboundFloatingBlockMaterialPacket.codec;
      final packet = ClientboundFloatingBlockMaterialPacket(
        'sable:air',
        const FloatingBlockMaterial(
          liftStrength: 1.25,
          preventSelfLift: true,
          scaleWithPressure: true,
          scaleWithGravity: false,
          transitionSpeed: 0.5,
          slowVerticalFriction: 0.1,
          fastVerticalFriction: 0.2,
          slowHorizontalFriction: 0.3,
          fastHorizontalFriction: 0.4,
        ),
      );

      final decoded = codec.decode(codec.encode(packet));
      expect(decoded.name, 'sable:air');
      expect(decoded.material, packet.material);
    });

    test('floating_material NBT field names match the codec', () {
      final packet = ClientboundFloatingBlockMaterialPacket(
        'sable:air',
        const FloatingBlockMaterial(liftStrength: 2.0),
      );

      final reader = PacketReader(ClientboundFloatingBlockMaterialPacket.codec.encode(packet));
      expect(reader.readString(), 'sable:air');
      final map = NetworkNbt.read(reader)!.asCompound;

      expect(map['lift_strength']!.value, 2.0);
      expect(map.containsKey('prevent_self_lift'), isFalse);
      expect(map.containsKey('scale_with_pressure'), isFalse);
      expect(map.containsKey('scale_friction_with_gravity'), isFalse);
      expect(map.containsKey('transition_speed'), isFalse);
    });

    test('dimension_physics round-trips with every optional present', () {
      final codec = ClientboundDimensionPhysicsPacket.codec;
      final packet = ClientboundDimensionPhysicsPacket([
        DimensionPhysics(
          dimension: 'minecraft:overworld',
          priority: 1000,
          universalDrag: 0.09,
          baseGravity: (0.0, -11.0, 0.0),
          basePressure: 1.0,
          pressureFunction: BezierResourceFunction([
            const BezierPoint(0, 1.5, 0),
            const BezierPoint(64, 1.0, -0.004),
            const BezierPoint(320, 0.0, -0.02),
          ]),
          magneticNorth: (0.0, 0.0, 1.0),
          ignoreChunks: true,
        ),
      ]);

      final decoded = codec.decode(codec.encode(packet));
      final physics = decoded.dimensionPhysics.single;

      expect(physics.dimension, 'minecraft:overworld');
      expect(physics.priority, 1000);
      // `universal_drag` is a float on the wire.
      expect(physics.universalDrag, closeTo(0.09, 1e-6));
      expect(physics.baseGravity, (0.0, -11.0, 0.0));
      expect(physics.basePressure, 1.0);
      expect(physics.magneticNorth, (0.0, 0.0, 1.0));
      expect(physics.ignoreChunks, isTrue);
      expect(physics.pressureFunction!.pointSize, 3);
      expect(physics.pressureFunction!.points[1].value, 1.0);
    });

    test('dimension_physics round-trips with every optional absent', () {
      final codec = ClientboundDimensionPhysicsPacket.codec;
      final packet = ClientboundDimensionPhysicsPacket([
        const DimensionPhysics(dimension: 'minecraft:the_nether'),
      ]);

      final decoded = codec.decode(codec.encode(packet)).dimensionPhysics.single;
      expect(decoded.dimension, 'minecraft:the_nether');
      expect(decoded.universalDrag, isNull);
      expect(decoded.baseGravity, isNull);
      expect(decoded.basePressure, isNull);
      expect(decoded.pressureFunction, isNull);
      expect(decoded.magneticNorth, isNull);
      expect(decoded.ignoreChunks, isFalse);
    });

    test('dimension_physics field order is the Java stream codec order', () {
      final packet = ClientboundDimensionPhysicsPacket([
        const DimensionPhysics(
          dimension: 'a:b',
          priority: 3,
          universalDrag: 0.5,
          baseGravity: (1, 2, 3),
          basePressure: 4.0,
          magneticNorth: (5, 6, 7),
          ignoreChunks: true,
        ),
      ]);

      final expected = PacketWriter()
        ..writeVarInt(1)
        ..writeString('a:b')
        ..writeInt(3)
        ..writeBool(true)
        ..writeFloat(0.5)
        ..writeBool(true)
        ..writeFloat(1)
        ..writeFloat(2)
        ..writeFloat(3)
        ..writeBool(true)
        ..writeDouble(4.0)
        ..writeBool(false)
        ..writeBool(true)
        ..writeFloat(5)
        ..writeFloat(6)
        ..writeFloat(7)
        ..writeBool(true);

      expect(ClientboundDimensionPhysicsPacket.codec.encode(packet), expected.toBytes());
    });

    test('the default pressure curve decays from underground to the build limit', () {
      final level = FakeLevel();
      final physics = DimensionPhysics.createDefault(level);
      final curve = physics.pressureFunction!;

      expect(curve.evaluateFunction(level.maxY.toDouble()), closeTo(0.0, 1e-6));
      expect(curve.evaluateFunction(0), greaterThan(1.0));
      expect(curve.evaluateFunction(64), closeTo(1.0, 0.05));
      // The curve is clamped at 1.5 underground.
      expect(curve.evaluateFunction(-10000), lessThanOrEqualTo(1.5 + 1e-9));
    });
  });

  group('misc payloads', () {
    test('freeze_player round-trips and is uuid + three doubles', () {
      final codec = ClientboundFreezePlayerPacket.codec;
      final packet = ClientboundFreezePlayerPacket(
        '00112233-4455-6677-8899-aabbccddeeff',
        Vector3d(1.5, -2.5, 3.5),
      );

      final expected = PacketWriter()
        ..writeUuid('00112233-4455-6677-8899-aabbccddeeff')
        ..writeDouble(1.5)
        ..writeDouble(-2.5)
        ..writeDouble(3.5);

      expect(codec.encode(packet), expected.toBytes());
      final decoded = codec.decode(codec.encode(packet));
      expect(decoded.subLevelId, packet.subLevelId);
      expect(decoded.localPosition.z, 3.5);
    });

    test('udp_activation round-trips and is one uuid', () {
      final codec = ClientboundSableUdpActivationPacket.codec;
      final packet = ClientboundSableUdpActivationPacket('00112233-4455-6677-8899-aabbccddeeff');

      expect(codec.encode(packet), (PacketWriter()..writeUuid(packet.uuid)).toBytes());
      expect(codec.decode(codec.encode(packet)).uuid, packet.uuid);
    });

    test('enter_gizmo_mode has an empty body', () {
      final codec = ClientboundEnterGizmoPacket.codec;
      expect(codec.encode(const ClientboundEnterGizmoPacket()), isEmpty);
      expect(codec.decode(const []), isA<ClientboundEnterGizmoPacket>());
    });

    test('punch_sub_level round-trips and is blockpos + two vectors', () {
      final codec = ServerboundPunchSubLevelPacket.codec;
      final packet = ServerboundPunchSubLevelPacket(
        (10, 64, -10),
        Vector3d(0.5, 0.5, 0.5),
        Vector3d(0, -1, 0),
      );

      final expected = PacketWriter()
        ..writeBlockPos((10, 64, -10))
        ..writeDouble(0.5)
        ..writeDouble(0.5)
        ..writeDouble(0.5)
        ..writeDouble(0)
        ..writeDouble(-1)
        ..writeDouble(0);

      expect(codec.encode(packet), expected.toBytes());
      final decoded = codec.decode(codec.encode(packet));
      expect(decoded.punchedBlock, (10, 64, -10));
      expect(decoded.direction.y, -1.0);
    });

    test('gizmo_move_sublevel round-trips and is uuid + three doubles', () {
      final codec = ServerboundGizmoMoveSubLevelPacket.codec;
      final packet = ServerboundGizmoMoveSubLevelPacket(
        '00112233-4455-6677-8899-aabbccddeeff',
        Vector3d(1, 2, 3),
      );

      final expected = PacketWriter()
        ..writeUuid(packet.subLevel)
        ..writeDouble(1)
        ..writeDouble(2)
        ..writeDouble(3);

      expect(codec.encode(packet), expected.toBytes());
      expect(codec.decode(codec.encode(packet)).position.y, 2.0);
    });

    test('punchCurve matches the Java tuning curve', () {
      expect(ServerboundPunchSubLevelPacket.punchCurve(1.0), closeTo(1.0, 1e-12));
      expect(ServerboundPunchSubLevelPacket.punchCurve(0.0), closeTo(0.0, 1e-12));
      // Never negative, and the published tuning values of the curve.
      for (var x = 0.0; x <= 1000; x += 0.5) {
        expect(ServerboundPunchSubLevelPacket.punchCurve(x), greaterThanOrEqualTo(0));
      }
      // Above mass 1 the curve follows S·(sqrt(u + g^-2) − g^-1) + 1 with
      // S = 2, g = 0.8: at x = 2 that is 2·(sqrt(2.5625) − 1.25) + 1.
      expect(ServerboundPunchSubLevelPacket.punchCurve(2.0), closeTo(2 * (1.6007810593582122 - 1.25) + 1, 1e-9));
    });
  });

  group('registry', () {
    test('every payload id is sable:<name> and unique', () {
      final ids = <String>{};
      for (final codec in [...SablePackets.allClientbound, ...SablePackets.allServerbound]) {
        expect(codec.id, startsWith('sable:'));
        expect(ids.add(codec.id), isTrue, reason: 'duplicate payload id ${codec.id}');
      }
    });

    test('there are 15 clientbound and 2 serverbound payloads', () {
      expect(SablePackets.allClientbound.length, 15);
      expect(SablePackets.allServerbound.length, 2);
    });

    test('the payload ids are the Java ones', () {
      expect(SablePackets.allClientbound.map((c) => c.id), [
        'sable:snapshot_packet',
        'sable:snapshot_info_packet',
        'sable:stop_moving_sublevel',
        'sable:change_sub_level_name',
        'sable:start_tracking_sublevel',
        'sable:finalize_sub_level',
        'sable:stop_tracking_sublevel',
        'sable:change_bounds_sublevel',
        'sable:freeze_player',
        'sable:physics_property',
        'sable:floating_material',
        'sable:dimension_physics',
        'sable:recently_split_sub_level',
        'sable:udp_activation',
        'sable:enter_gizmo_mode',
      ]);
      expect(SablePackets.allServerbound.map((c) => c.id), [
        'sable:punch_sub_level',
        'sable:gizmo_move_sublevel',
      ]);
    });

    test('the channel is sable:1', () {
      expect(SableChannel.modId, 'sable');
      expect(SableChannel.version, '1');
      expect(SableChannel.name, 'sable:1');
      expect(SableChannel.path('start_tracking_sublevel'), 'sable:start_tracking_sublevel');
    });

    test('encode/decode through the registry', () {
      final packet = ClientboundFinalizeSubLevelPacket(5);
      final bytes = SablePackets.encode(packet);
      final decoded = SablePackets.decodeClientbound(ClientboundFinalizeSubLevelPacket.payloadId, bytes);
      expect((decoded as ClientboundFinalizeSubLevelPacket).plotCoordinate, 5);

      expect(
        () => SablePackets.decodeClientbound('sable:punch_sub_level', bytes),
        throwsArgumentError,
      );
    });
  });

  group('udp', () {
    test('the type ordinals are the Java enum order', () {
      expect(SableUdpPacketType.ping.wireId, 0);
      expect(SableUdpPacketType.snapshot.wireId, 1);
      expect(SableUdpPacketType.snapshotInfo.wireId, 2);
      expect(SableUdpPacketType.auth.wireId, 3);
      expect(SableUdpPacketType.keepAliveClientbound.wireId, 4);
      expect(SableUdpPacketType.aliveServerbound.wireId, 5);
      expect(SableUdpPacketType.values.map((t) => t.javaName), [
        'PING',
        'SNAPSHOT',
        'SNAPSHOT_INFO',
        'AUTH',
        'KEEP_ALIVE_CLIENTBOUND',
        'ALIVE_SERVERBOUND',
      ]);
    });

    test('a datagram is a VarInt frame length, the type byte, then the body', () {
      SablePackets.registerUdpCodecs();

      final datagram = SableUdpPackets.encode(const SableUdpEchoPacket('hi'));
      // frame length = 1 type byte + 1 VarInt length + 2 UTF-8 bytes
      expect(datagram, [4, 0, 2, 0x68, 0x69]);

      final decoded = SableUdpPackets.decode(datagram);
      expect(decoded, isA<SableUdpEchoPacket>());
      expect((decoded as SableUdpEchoPacket).text, 'hi');
    });

    test('auth carries the token as a UTF string', () {
      SablePackets.registerUdpCodecs();
      final datagram = SableUdpPackets.encode(
        const SableUdpAuthenticationPacket('00112233-4455-6677-8899-aabbccddeeff'),
      );
      final decoded = SableUdpPackets.decode(datagram) as SableUdpAuthenticationPacket;
      expect(decoded.token, '00112233-4455-6677-8899-aabbccddeeff');
    });

    test('keep-alives have an empty body', () {
      SablePackets.registerUdpCodecs();
      final keepAlive = SableUdpPackets.encode(const SableUdpClientboundKeepAlivePacket());
      expect(keepAlive, [1, 4]);
      expect(SableUdpPackets.decode(keepAlive), isA<SableUdpClientboundKeepAlivePacket>());

      final alive = SableUdpPackets.encode(const SableUdpServerboundAlivePacket());
      expect(alive, [1, 5]);
      expect(SableUdpPackets.decode(alive), isA<SableUdpServerboundAlivePacket>());
    });

    test('snapshots travel over UDP with the same body as TCP', () {
      SablePackets.registerUdpCodecs();
      final snapshot = ClientboundSableSnapshotDualPacket(4, [
        SnapshotEntry(
          plotCoordinate: 1,
          pose: pose(1, 2, 3, 0, 0, 0, 1),
          linearVelocity: Vector3d(1, 0, 0),
          angularVelocity: Vector3d(0, 0, 0),
        ),
      ]);

      final datagram = SableUdpPackets.encode(snapshot);
      expect(datagram[1], SableUdpPacketType.snapshot.wireId);

      final decoded = SableUdpPackets.decode(datagram) as ClientboundSableSnapshotDualPacket;
      expect(decoded.interpolationTick, 4);
      expect(decoded.entries.single.plotCoordinate, 1);

      // The body after the type byte is exactly the TCP payload body.
      expect(
        Uint8List.fromList(datagram.sublist(2)),
        ClientboundSableSnapshotDualPacket.codec.encode(snapshot),
      );
    });

    test('a truncated or unknown datagram is dropped, not thrown', () {
      SablePackets.registerUdpCodecs();
      expect(SableUdpPackets.decode(const []), isNull);
      expect(SableUdpPackets.decode(const [1, 99]), isNull);
      // Frame length does not match the rest.
      expect(SableUdpPackets.decode(const [5, 0, 1, 0x61]), isNull);
      // Trailing bytes after a complete body.
      expect(SableUdpPackets.decode(const [3, 0, 1, 0x61, 0x62]), isNull);
    });
  });

  group('server config', () {
    test('defaults match SableServerConfig', () {
      final config = SableServerConfig();
      expect(config.subLevelSubstepsPerTick, 2);
      expect(config.subLevelStoragePruning, isFalse);
    });

    test('fromMap clamps the substep range to 1..10', () {
      expect(
        SableServerConfig.fromMap({'sub_level_substeps_per_tick': 0}).subLevelSubstepsPerTick,
        1,
      );
      expect(
        SableServerConfig.fromMap({'sub_level_substeps_per_tick': 99}).subLevelSubstepsPerTick,
        10,
      );
      expect(
        SableServerConfig.fromMap({'sub_level_substeps_per_tick': 4}).subLevelSubstepsPerTick,
        4,
      );
    });

    test('fromMap keeps defaults for missing keys and round-trips toMap', () {
      final config = SableServerConfig.fromMap(const {});
      expect(config.toMap(), {
        'sub_level_substeps_per_tick': 2,
        'sub_level_storage_pruning': false,
      });

      final parsed = SableServerConfig.fromMap({
        'sub_level_substeps_per_tick': 3,
        'sub_level_storage_pruning': true,
      });
      expect(parsed.subLevelSubstepsPerTick, 3);
      expect(parsed.subLevelStoragePruning, isTrue);
    });

    test('PhysicsConfigData takes the substep count from the server config', () {
      final data = PhysicsConfigData();
      expect(data.substepsPerTick, 2);
      expect(data.solverIterations, 18);

      data.updateFromConfig(SableServerConfig(subLevelSubstepsPerTick: 5));
      expect(data.substepsPerTick, 5);
    });
  });
}
