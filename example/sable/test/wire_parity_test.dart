// Wire parity: every Sable payload, byte for byte, against the Java codec.
//
// The real Sable client is on the other end of this wire, so "it round-trips
// through our own codec" is not enough: a field in the wrong order, a value
// written as a float instead of a double, or a payload registered under a
// slightly different id all round-trip perfectly and still break the client.
//
// This file therefore builds the expected bytes with its own writer, written
// from the Java `FriendlyByteBuf` / `SableBufferUtils` behaviour, instead of
// reusing `PacketWriter`. The two implementations can only agree if both match
// the Java format.
//
// Each test names the Java method it mirrors, e.g.
// `ClientboundStartTrackingSubLevelPacket.write(FriendlyByteBuf)`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:sable/sable.dart';
import 'package:test/test.dart';

/// A `FriendlyByteBuf` written from the Java spec, independent of
/// `PacketWriter`: big endian, `long` = 8 bytes, `float` = 4, `double` = 8,
/// strings and collections length-prefixed with a VarInt.
final class JavaBuf {
  final List<int> _bytes = [];

  List<int> get bytes => List.unmodifiable(_bytes);

  void u8(int value) => _bytes.add(value & 0xFF);

  void i16(int value) {
    _bytes
      ..add((value >> 8) & 0xFF)
      ..add(value & 0xFF);
  }

  void i32(int value) {
    final data = ByteData(4)..setInt32(0, value);
    _bytes.addAll(data.buffer.asUint8List());
  }

  void i64(int value) {
    final data = ByteData(8)..setInt64(0, value);
    _bytes.addAll(data.buffer.asUint8List());
  }

  void f32(double value) {
    final data = ByteData(4)..setFloat32(0, value);
    _bytes.addAll(data.buffer.asUint8List());
  }

  void f64(double value) {
    final data = ByteData(8)..setFloat64(0, value);
    _bytes.addAll(data.buffer.asUint8List());
  }

  void varInt(int value) {
    var current = value;
    while ((current & ~0x7F) != 0) {
      u8((current & 0x7F) | 0x80);
      current = current >>> 7;
    }
    u8(current);
  }

  void utf(String value) {
    final encoded = utf8.encode(value);
    varInt(encoded.length);
    _bytes.addAll(encoded);
  }

  /// `FriendlyByteBuf.writeUUID`: two longs, most significant first.
  void uuid(String value) {
    final hex = value.replaceAll('-', '');
    i64(_parseHex(hex.substring(0, 16)));
    i64(_parseHex(hex.substring(16)));
  }

  /// `FriendlyByteBuf.writeBlockPos`: x:26, z:26, y:12.
  void blockPos(int x, int y, int z) =>
      i64(((x & 0x3FFFFFF) << 38) | ((z & 0x3FFFFFF) << 12) | (y & 0xFFF));

  void vector3d(double x, double y, double z) {
    f64(x);
    f64(y);
    f64(z);
  }

  void vector3f(double x, double y, double z) {
    f32(x);
    f32(y);
    f32(z);
  }

  void quaternion(double x, double y, double z, double w) {
    f32(x);
    f32(y);
    f32(z);
    f32(w);
  }

  /// `SableBufferUtils.write(buf, Pose3dc)`: position, orientation, rotation
  /// point. The scale is not on the wire.
  void pose(
    double px,
    double py,
    double pz,
    double qx,
    double qy,
    double qz,
    double qw,
    double rx,
    double ry,
    double rz,
  ) {
    vector3d(px, py, pz);
    quaternion(qx, qy, qz, qw);
    vector3d(rx, ry, rz);
  }

  /// `SableBufferUtils.write(buf, BoundingBox3ic)`: six ints.
  void bounds(int minX, int minY, int minZ, int maxX, int maxY, int maxZ) {
    i32(minX);
    i32(minY);
    i32(minZ);
    i32(maxX);
    i32(maxY);
    i32(maxZ);
  }

  static int _parseHex(String hex) {
    var value = 0;
    for (var i = 0; i < hex.length; i++) {
      final digit = int.parse(hex[i], radix: 16);
      value = (value << 4) | digit;
    }
    return value.toSigned(64);
  }
}

/// `ChunkPos.pack(x, z)`: x in the low 32 bits, z in the high 32.
int packChunk(int x, int z) => (x & 0xFFFFFFFF) | (z & 0xFFFFFFFF) << 32;

const String testUuid = '00112233-4455-6677-8899-aabbccddeeff';
const String otherUuid = 'f0e1d2c3-b4a5-9687-7869-5a4b3c2d1e0f';

Pose3d poseOf(
  double px,
  double py,
  double pz,
  double qx,
  double qy,
  double qz,
  double qw,
  double rx,
  double ry,
  double rz,
) =>
    Pose3d()
      ..position().set(px, py, pz)
      ..orientation().set(qx, qy, qz, qw)
      ..rotationPoint().set(rx, ry, rz);

/// The canonical pose used by the golden vectors: a half turn about y.
Pose3d canonicalPose() => poseOf(1.5, 2.5, 3.5, 0, 0.5, 0, 0.8660254, 0.5, 0.5, 0.5);

/// `Sable.sablePath(...)` argument of every payload, copied from the Java
/// `TYPE` declarations. These are literal strings on purpose: a test that
/// compared against `payloadId` would have passed while the id was wrong.
const Map<String, String> javaPayloadIds = {
  'snapshot_packet': 'ClientboundSableSnapshotDualPacket',
  'snapshot_info_packet': 'ClientboundSableSnapshotInfoDualPacket',
  'stop_moving_sub_level': 'ClientboundStopMovingSubLevelPacket',
  'change_sub_level_name': 'ClientboundChangeSubLevelNamePacket',
  'start_tracking_sub_level': 'ClientboundStartTrackingSubLevelPacket',
  'finalize_sub_level': 'ClientboundFinalizeSubLevelPacket',
  'stop_tracking_sub_level': 'ClientboundStopTrackingSubLevelPacket',
  'change_bounds_sublevel': 'ClientboundChangeBoundsSubLevelPacket',
  'freeze_player': 'ClientboundFreezePlayerPacket',
  'physics_property': 'ClientboundPhysicsPropertyPacket',
  'floating_material': 'ClientboundFloatingBlockMaterialPacket',
  'dimension_physics': 'ClientboundDimensionPhysicsPacket',
  'recently_split_sub_level': 'ClientboundRecentlySplitSubLevelPacket',
  'udp_activation': 'ClientboundSableUDPActivationPacket',
  'enter_gizmo_mode': 'ClientboundEnterGizmoPacket',
  'punch_sub_level': 'ServerboundPunchSubLevelPacket',
  'gizmo_move_sub_level': 'ServerboundGizmoMoveSubLevelPacket',
};

void main() {
  group('payload ids are the Java ids', () {
    test('every registered payload id is a Java sablePath argument', () {
      final registered = [
        for (final codec in SablePackets.allClientbound) codec.id,
        for (final codec in SablePackets.allServerbound) codec.id,
      ];
      final expected = [for (final name in javaPayloadIds.keys) 'sable:$name'];

      expect(registered.toSet(), expected.toSet());
      expect(registered.toSet().length, registered.length, reason: 'duplicate id');
    });

    test('no payload id spells sub_level as sublevel', () {
      for (final id in [
        for (final codec in SablePackets.allClientbound) codec.id,
        for (final codec in SablePackets.allServerbound) codec.id,
      ]) {
        expect(id, isNot(contains('sublevel')), reason: 'Java spells the payload id "$id" with sub_level');
      }
    });

    test('registration order is SableTCPPackets.init order', () {
      expect(SablePackets.allClientbound.map((codec) => codec.id), [
        'sable:snapshot_packet',
        'sable:snapshot_info_packet',
        'sable:stop_moving_sub_level',
        'sable:change_sub_level_name',
        'sable:start_tracking_sub_level',
        'sable:finalize_sub_level',
        'sable:stop_tracking_sub_level',
        'sable:change_bounds_sublevel',
        'sable:freeze_player',
        'sable:physics_property',
        'sable:floating_material',
        'sable:dimension_physics',
        'sable:recently_split_sub_level',
        'sable:udp_activation',
        'sable:enter_gizmo_mode',
      ]);
      expect(SablePackets.allServerbound.map((codec) => codec.id), [
        'sable:punch_sub_level',
        'sable:gizmo_move_sub_level',
      ]);
    });

    test('the channel is VeilPacketManager.create(MOD_ID, "1")', () {
      expect(SableChannel.name, 'sable:1');
    });
  });

  group('tracking payloads, exact bytes', () {
    test('start_tracking_sub_level', () {
      final packet = ClientboundStartTrackingSubLevelPacket(
        plotCoordinate: packChunk(3, 7),
        subLevelId: testUuid,
        lastPose: canonicalPose(),
        pose: poseOf(2.5, 3.5, 4.5, 0, 0, 0, 1, 0.5, 0.5, 0.5),
        bounds: BoundingBox3i(0, 0, 0, 16, 16, 16),
        name: 'Airship',
        gameTick: 42,
      );

      final expected = JavaBuf()
        ..i64(packChunk(3, 7))
        ..uuid(testUuid)
        ..pose(1.5, 2.5, 3.5, 0, 0.5, 0, 0.8660254, 0.5, 0.5, 0.5)
        ..pose(2.5, 3.5, 4.5, 0, 0, 0, 1, 0.5, 0.5, 0.5)
        ..bounds(0, 0, 0, 16, 16, 16)
        ..u8(1)
        ..utf('Airship')
        ..i32(42);

      expect(ClientboundStartTrackingSubLevelPacket.codec.encode(packet), expected.bytes);
    });

    test('start_tracking_sub_level without a name writes a false flag only', () {
      final packet = ClientboundStartTrackingSubLevelPacket(
        plotCoordinate: packChunk(0, 0),
        subLevelId: testUuid,
        lastPose: canonicalPose(),
        pose: canonicalPose(),
        bounds: BoundingBox3i(0, 0, 0, 1, 1, 1),
        gameTick: 0,
      );

      final expected = JavaBuf()
        ..i64(packChunk(0, 0))
        ..uuid(testUuid)
        ..pose(1.5, 2.5, 3.5, 0, 0.5, 0, 0.8660254, 0.5, 0.5, 0.5)
        ..pose(1.5, 2.5, 3.5, 0, 0.5, 0, 0.8660254, 0.5, 0.5, 0.5)
        ..bounds(0, 0, 0, 1, 1, 1)
        ..u8(0)
        ..i32(0);

      expect(ClientboundStartTrackingSubLevelPacket.codec.encode(packet), expected.bytes);
    });

    test('finalize_sub_level is one long', () {
      final bytes = ClientboundFinalizeSubLevelPacket.codec.encode(
        ClientboundFinalizeSubLevelPacket(packChunk(-4, 9)),
      );
      expect(bytes, (JavaBuf()..i64(packChunk(-4, 9))).bytes);
      expect(bytes, hasLength(8));
    });

    test('stop_tracking_sub_level is one long', () {
      final bytes = ClientboundStopTrackingSubLevelPacket.codec.encode(
        ClientboundStopTrackingSubLevelPacket(packChunk(1, 2)),
      );
      expect(bytes, (JavaBuf()..i64(packChunk(1, 2))).bytes);
    });

    test('stop_moving_sub_level is one long', () {
      final bytes = ClientboundStopMovingSubLevelPacket.codec.encode(
        ClientboundStopMovingSubLevelPacket(packChunk(5, 6)),
      );
      expect(bytes, (JavaBuf()..i64(packChunk(5, 6))).bytes);
    });

    test('change_bounds_sublevel is a long then six ints', () {
      final packet = ClientboundChangeBoundsSubLevelPacket(
        packChunk(2, 3),
        BoundingBox3i(-1, 0, -2, 15, 20, 16),
      );
      final expected = JavaBuf()
        ..i64(packChunk(2, 3))
        ..bounds(-1, 0, -2, 15, 20, 16);

      expect(ClientboundChangeBoundsSubLevelPacket.codec.encode(packet), expected.bytes);
      expect(expected.bytes, hasLength(8 + 24));
    });

    test('change_sub_level_name is a uuid then optional UTF', () {
      final named = JavaBuf()
        ..uuid(testUuid)
        ..u8(1)
        ..utf('Boat');
      expect(
        ClientboundChangeSubLevelNamePacket.codec.encode(
          const ClientboundChangeSubLevelNamePacket(testUuid, 'Boat'),
        ),
        named.bytes,
      );

      final cleared = JavaBuf()
        ..uuid(testUuid)
        ..u8(0);
      expect(
        ClientboundChangeSubLevelNamePacket.codec.encode(
          const ClientboundChangeSubLevelNamePacket(testUuid, null),
        ),
        cleared.bytes,
      );
    });

    test('recently_split_sub_level is uuid, uuid, pose', () {
      final packet = ClientboundRecentlySplitSubLevelPacket(
        splitSubLevelId: testUuid,
        splitFromId: otherUuid,
        pose: canonicalPose(),
      );
      final expected = JavaBuf()
        ..uuid(testUuid)
        ..uuid(otherUuid)
        ..pose(1.5, 2.5, 3.5, 0, 0.5, 0, 0.8660254, 0.5, 0.5, 0.5);

      expect(ClientboundRecentlySplitSubLevelPacket.codec.encode(packet), expected.bytes);
    });
  });

  group('snapshot payloads, exact bytes', () {
    test('snapshot_packet is int, VarInt count, then per entry', () {
      final packet = ClientboundSableSnapshotDualPacket(7, [
        SnapshotEntry(
          plotCoordinate: packChunk(1, 2),
          pose: canonicalPose(),
          linearVelocity: Vector3d(0.5, -0.25, 0),
          angularVelocity: Vector3d(0, 0.125, -0.5),
        ),
        SnapshotEntry(
          plotCoordinate: packChunk(3, 4),
          pose: canonicalPose(),
          linearVelocity: Vector3d(1, 2, 3),
          angularVelocity: Vector3d(4, 5, 6),
        ),
      ]);

      final expected = JavaBuf()
        ..i32(7)
        ..varInt(2)
        ..i64(packChunk(1, 2))
        ..pose(1.5, 2.5, 3.5, 0, 0.5, 0, 0.8660254, 0.5, 0.5, 0.5)
        ..vector3f(0.5, -0.25, 0)
        ..vector3f(0, 0.125, -0.5)
        ..i64(packChunk(3, 4))
        ..pose(1.5, 2.5, 3.5, 0, 0.5, 0, 0.8660254, 0.5, 0.5, 0.5)
        ..vector3f(1, 2, 3)
        ..vector3f(4, 5, 6);

      expect(ClientboundSableSnapshotDualPacket.codec.encode(packet), expected.bytes);
    });

    test('an empty snapshot is an int and a zero count', () {
      final bytes = ClientboundSableSnapshotDualPacket.codec.encode(
        const ClientboundSableSnapshotDualPacket(0, []),
      );
      expect(bytes, (JavaBuf()
            ..i32(0)
            ..varInt(0))
          .bytes);
    });

    test('snapshot_info_packet is int, int, bool', () {
      final bytes = ClientboundSableSnapshotInfoDualPacket.codec.encode(
        const ClientboundSableSnapshotInfoDualPacket(msSinceLast: 50, gameTick: 12, stopped: true),
      );
      expect(bytes, (JavaBuf()
            ..i32(50)
            ..i32(12)
            ..u8(1))
          .bytes);
    });
  });

  group('misc payloads, exact bytes', () {
    test('freeze_player is a uuid and three doubles', () {
      final packet = ClientboundFreezePlayerPacket(testUuid, Vector3d(1, 2, 3));
      final expected = JavaBuf()
        ..uuid(testUuid)
        ..vector3d(1, 2, 3);
      expect(ClientboundFreezePlayerPacket.codec.encode(packet), expected.bytes);
    });

    test('udp_activation is one uuid', () {
      final bytes = ClientboundSableUdpActivationPacket.codec.encode(
        const ClientboundSableUdpActivationPacket(testUuid),
      );
      expect(bytes, (JavaBuf()..uuid(testUuid)).bytes);
      expect(bytes, hasLength(16));
    });

    test('enter_gizmo_mode has an empty body', () {
      expect(ClientboundEnterGizmoPacket.codec.encode(const ClientboundEnterGizmoPacket()), isEmpty);
    });

    test('punch_sub_level is a BlockPos then two vectors', () {
      final packet = ServerboundPunchSubLevelPacket(
        (10, 64, -10),
        Vector3d(0.5, 0.25, 0.75),
        Vector3d(0, -1, 0),
      );
      final expected = JavaBuf()
        ..blockPos(10, 64, -10)
        ..vector3d(0.5, 0.25, 0.75)
        ..vector3d(0, -1, 0);
      expect(ServerboundPunchSubLevelPacket.codec.encode(packet), expected.bytes);
    });

    test('gizmo_move_sub_level is a uuid and three doubles', () {
      final packet = ServerboundGizmoMoveSubLevelPacket(testUuid, Vector3d(4, 5, 6));
      final expected = JavaBuf()
        ..uuid(testUuid)
        ..vector3d(4, 5, 6);
      expect(ServerboundGizmoMoveSubLevelPacket.codec.encode(packet), expected.bytes);
    });
  });

  group('dimension_physics, exact bytes', () {
    test('every optional present, in the Java stream codec order', () {
      final packet = ClientboundDimensionPhysicsPacket([
        DimensionPhysics(
          dimension: 'minecraft:overworld',
          priority: 10,
          universalDrag: 0.09,
          baseGravity: (0.0, -11.0, 0.0),
          basePressure: 1.0,
          pressureFunction: BezierResourceFunction([
            const BezierPoint(0, 1, -0.004),
            const BezierPoint(100, 0.5, -0.002),
          ]),
          magneticNorth: (0.0, 0.0, 1.0),
          ignoreChunks: true,
        ),
      ]);

      final expected = JavaBuf()
        ..varInt(1)
        // Identifier.STREAM_CODEC
        ..utf('minecraft:overworld')
        // ByteBufCodecs.INT
        ..i32(10)
        // optional FLOAT
        ..u8(1)
        ..f32(0.09)
        // optional VECTOR3F
        ..u8(1)
        ..vector3f(0, -11, 0)
        // optional DOUBLE
        ..u8(1)
        ..f64(1.0)
        // optional BezierResourceFunction: VarInt count, three doubles per point
        ..u8(1)
        ..varInt(2)
        ..f64(0)
        ..f64(1)
        ..f64(-0.004)
        ..f64(100)
        ..f64(0.5)
        ..f64(-0.002)
        // optional VECTOR3F
        ..u8(1)
        ..vector3f(0, 0, 1)
        // BOOL
        ..u8(1);

      expect(ClientboundDimensionPhysicsPacket.codec.encode(packet), expected.bytes);
    });

    test('every optional absent writes seven false flags', () {
      final packet = ClientboundDimensionPhysicsPacket([
        const DimensionPhysics(dimension: 'minecraft:the_nether', priority: 1000),
      ]);

      final expected = JavaBuf()
        ..varInt(1)
        ..utf('minecraft:the_nether')
        ..i32(1000)
        ..u8(0) // universal_drag
        ..u8(0) // base_gravity
        ..u8(0) // base_pressure
        ..u8(0) // pressure_function
        ..u8(0) // magnetic_north
        ..u8(0); // ignore_chunks

      expect(ClientboundDimensionPhysicsPacket.codec.encode(packet), expected.bytes);
    });

    test('an empty dimension list is a zero count', () {
      expect(
        ClientboundDimensionPhysicsPacket.codec.encode(const ClientboundDimensionPhysicsPacket([])),
        [0],
      );
    });
  });

  group('NBT payloads', () {
    test('physics_property is one nameless compound tag', () {
      final packet = ClientboundPhysicsPropertyPacket(
        PhysicsBlockPropertiesDefinition(
          selector: const TagOrElementLocation('minecraft:stone'),
          properties: const {'sable:mass': 2.5},
        ),
      );

      final bytes = ClientboundPhysicsPropertyPacket.codec.encode(packet);
      // TAG_Compound, then the unnamed root's children.
      expect(bytes.first, 10);
      expect(bytes.last, 0, reason: 'the compound must end with TAG_End');

      // `selector` is a TAG_String, so the first child is 8, then its name.
      expect(bytes[1], 8);
      final nameLength = (bytes[2] << 8) | bytes[3];
      expect(nameLength, 'selector'.length);
      expect(utf8.decode(bytes.sublist(4, 4 + nameLength)), 'selector');
    });

    test('physics_property field names are the codec field names', () {
      final definition = PhysicsBlockPropertiesDefinition(
        selector: const TagOrElementLocation('logs', tag: true),
        priority: 5,
        properties: const {'sable:mass': 3.0, 'sable:fragile': true},
      );
      final decoded = ClientboundPhysicsPropertyPacket.codec.decode(
        ClientboundPhysicsPropertyPacket.codec.encode(ClientboundPhysicsPropertyPacket(definition)),
      ).definition;

      expect(decoded.selector.decoratedId, '#logs');
      expect(decoded.priority, 5);
      expect(decoded.properties['sable:mass'], 3.0);
      expect(decoded.properties['sable:fragile'], true);
    });

    test('floating_material is a UTF identifier then an NBT compound', () {
      final packet = ClientboundFloatingBlockMaterialPacket(
        'sable:air',
        const FloatingBlockMaterial(liftStrength: 1.5, scaleWithPressure: true),
      );

      final bytes = ClientboundFloatingBlockMaterialPacket.codec.encode(packet);
      expect(bytes.sublist(0, 10), [9, ...utf8.encode('sable:air')]);
      expect(bytes[10], 10, reason: 'the material body is a TAG_Compound');

      final decoded = ClientboundFloatingBlockMaterialPacket.codec.decode(bytes);
      expect(decoded.name, 'sable:air');
      expect(decoded.material.liftStrength, 1.5);
      expect(decoded.material.scaleWithPressure, isTrue);
    });
  });

  group('udp datagrams', () {
    setUpAll(SablePackets.registerUdpCodecs);

    test('a datagram is VarInt length, the type byte, then the body', () {
      final datagram = SableUdpPackets.encode(const SableUdpEchoPacket('hi'));
      final expected = JavaBuf()
        ..varInt(1 + 1 + 2) // type byte + UTF length + 2 characters
        ..u8(0)
        ..utf('hi');
      expect(datagram, expected.bytes);
    });

    test('the type byte is the Java ordinal for every type', () {
      final cases = <SableUdpPacket, int>{
        const SableUdpEchoPacket('x'): 0,
        ClientboundSableSnapshotDualPacket(0, const []): 1,
        const ClientboundSableSnapshotInfoDualPacket(msSinceLast: 0, gameTick: 0, stopped: false): 2,
        const SableUdpAuthenticationPacket(testUuid): 3,
        const SableUdpClientboundKeepAlivePacket(): 4,
        const SableUdpServerboundAlivePacket(): 5,
      };
      for (final entry in cases.entries) {
        expect(SableUdpPackets.encode(entry.key)[1], entry.value,
            reason: entry.key.runtimeType.toString());
      }
    });

    test('an empty-body type is a two byte datagram', () {
      final datagram = SableUdpPackets.encode(const SableUdpClientboundKeepAlivePacket());
      expect(datagram, [1, 4]);
    });

    test('the dual snapshot payload has the same body over UDP and TCP', () {
      final packet = ClientboundSableSnapshotDualPacket(9, [
        SnapshotEntry(
          plotCoordinate: packChunk(1, 1),
          pose: canonicalPose(),
          linearVelocity: Vector3d(1, 2, 3),
          angularVelocity: Vector3d(4, 5, 6),
        ),
      ]);

      final tcp = ClientboundSableSnapshotDualPacket.codec.encode(packet);
      final udp = SableUdpPackets.encode(packet);
      expect(udp.sublist(2), tcp);
    });

    test('a datagram decodes back to the payload', () {
      final packet = const SableUdpAuthenticationPacket(testUuid);
      final decoded = SableUdpPackets.decode(SableUdpPackets.encode(packet));
      expect(decoded, isA<SableUdpAuthenticationPacket>());
      expect((decoded! as SableUdpAuthenticationPacket).token, testUuid);
    });
  });

  group('chunk coordinate packing', () {
    test('pack matches ChunkPos.pack and unpack sign-extends', () {
      for (final (x, z) in [(0, 0), (1, 2), (-1, -2), (10000, -10000), (0x7FFFFFFF, -0x80000000)]) {
        final packed = SableBufferUtils.packChunk(x, z);
        expect(packed, packChunk(x, z), reason: 'pack($x, $z)');
        expect(SableBufferUtils.unpackChunkX(packed), x, reason: 'getX of pack($x, $z)');
        expect(SableBufferUtils.unpackChunkZ(packed), z, reason: 'getZ of pack($x, $z)');
      }
    });

    test('the low half of a negative x is not returned as an unsigned value', () {
      final packed = SableBufferUtils.packChunk(-1, 0);
      expect(SableBufferUtils.unpackChunkX(packed), -1);
      expect(SableBufferUtils.unpackChunkX(packed), isNot(0xFFFFFFFF));
    });
  });
}
