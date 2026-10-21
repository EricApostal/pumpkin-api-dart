// Byte-layout and round-trip tests for every Simulated payload.
//
// The wire is read by the real Simulated client, so self-consistency is not
// enough: for every payload this file builds the expected bytes *independently*
// (a small big-endian buffer written by hand, below) in the Java
// `StreamCodec.composite` field order, and requires the codec's output to be
// identical. That pins the field order, the count prefixes and the places where
// Java writes a raw value instead of a `ByteBufCodecs.list`.
//
// The cases that exist because they are easy to get wrong:
//
//  * `diagram_data` / `save_diagram` — `STREAM_VECTOR3DC` and
//    `BOUNDING_BOX_3D_STREAM_CODEC` are list codecs, so they carry a VarInt count
//    (3 and 6) that the `SableBufferUtils` helpers do not;
//  * `rope_data` and `physics_staff_drag` — hand-written, raw doubles and a
//    quaternion as four *floats*;
//  * `linked_typewriter_save` — a map of key code to entry, then the position;
//  * `honey_glue_sync` — six doubles, an int, then an optional uuid;
//  * `end_sea` — `ByteBufCodecs.fromCodec`, i.e. NBT, not fields.
import 'dart:convert';
import 'dart:typed_data';

// create's internals are pure but not exported from the barrel.
// ignore_for_file: implementation_imports
import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/core/nbt.dart' show NetworkNbt;
import 'package:create/src/core/payload.dart' show PayloadRegistry;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/protocol/item_stack.dart' show ItemStackData;
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:sable/sable.dart' show BoundingBox3d, Quaterniond, Vector3d;
import 'package:simulated/simulated.dart';
import 'package:test/test.dart';

/// A big-endian buffer written by hand, so the expectations do not go through
/// `PacketWriter` (the thing under test).
final class _Buf {
  final BytesBuilder _out = BytesBuilder();
  final ByteData _scratch = ByteData(8);

  void u8(int v) => _out.addByte(v & 0xFF);

  void i32(int v) {
    _scratch.setInt32(0, v);
    _out.add(Uint8List.fromList(_scratch.buffer.asUint8List(0, 4)));
  }

  void i64(int v) {
    _scratch.setInt64(0, v);
    _out.add(Uint8List.fromList(_scratch.buffer.asUint8List(0, 8)));
  }

  void f32(double v) {
    _scratch.setFloat32(0, v);
    _out.add(Uint8List.fromList(_scratch.buffer.asUint8List(0, 4)));
  }

  void f64(double v) {
    _scratch.setFloat64(0, v);
    _out.add(Uint8List.fromList(_scratch.buffer.asUint8List(0, 8)));
  }

  void varInt(int v) {
    var rest = v & 0xFFFFFFFF;
    while (rest > 0x7F) {
      _out.addByte((rest & 0x7F) | 0x80);
      rest >>= 7;
    }
    _out.addByte(rest);
  }

  void str(String v) {
    final bytes = utf8.encode(v);
    varInt(bytes.length);
    _out.add(bytes);
  }

  void uuid(String id) {
    final hex = id.replaceAll('-', '');
    i64(_hexToI64(hex.substring(0, 16)));
    i64(_hexToI64(hex.substring(16)));
  }

  /// 16 hex digits as the two's complement 64-bit value `FriendlyByteBuf`
  /// writes (`writeLong`).
  static int _hexToI64(String hex) {
    var value = 0;
    for (var i = 0; i < 16; i++) {
      value = (value << 4) | int.parse(hex[i], radix: 16);
    }
    return value;
  }

  void blockPos(Pos p) {
    final (x, y, z) = p;
    i64(((x & 0x3FFFFFF) << 38) | ((z & 0x3FFFFFF) << 12) | (y & 0xFFF));
  }

  void vec3d(Vector3d v) {
    f64(v.x);
    f64(v.y);
    f64(v.z);
  }

  /// `STREAM_VECTOR3DC`: VarInt 3 then the three doubles.
  void vec3dc(Vector3d v) {
    varInt(3);
    vec3d(v);
  }

  Uint8List get bytes => _out.toBytes();
}

const Pos _pos = (1, 2, 3);
const Pos _pos2 = (-4, 70, 8);
const String _uuid = '00112233-4455-6677-8899-aabbccddeeff';

void _expectBytes(SimPacket packet, Uint8List expected) {
  expect(SimPayloads.encode(packet), expected, reason: packet.id);
}

void main() {
  group('channel table', () {
    test('the 37 channels are the ones SimPacketManager registers', () {
      final ids = simChannels.map((c) => c.id).toList();
      expect(ids, hasLength(37));
      expect(ids.toSet(), hasLength(37));
      expect(SimPayloads.all.map((c) => c.id).toList(), ids);
      expect(simChannels.every((c) => c.version == '0.1'), isTrue);
      expect(simChannels.every((c) => !c.optional), isTrue);
      expect(simChannels.where((c) => c.serverbound), hasLength(23));
      expect(simChannels.where((c) => !c.serverbound), hasLength(14));
      expect(SimulatedAddon().modId, 'simulated');
      expect(SimulatedAddon().channels, hasLength(37));
    });

    test('the channel directions are the Java registrar calls', () {
      const serverbound = {
        'simulated:assemble',
        'simulated:be_observed',
        'simulated:configure_altitude_sensor',
        'simulated:configure_modulating_linked_reciever',
        'simulated:throttle_lever_signal',
        'simulated:nameplate_change_name',
        'simulated:key_interaction',
        'simulated:linked_typewriter_save',
        'simulated:typewriter_disconnect_user',
        'simulated:entry_modify',
        'simulated:linked_typewriter_bind_item',
        'simulated:steering_wheel_update',
        'simulated:place_spring',
        'simulated:place_merging_glue',
        'simulated:update_player_handle',
        'simulated:honey_glue_spawn',
        'simulated:honey_glue_change_bounds',
        'simulated:ride_rope',
        'simulated:break_rope',
        'simulated:physics_staff_action',
        'simulated:physics_staff_drag',
        'simulated:request_diagram_data',
        'simulated:save_diagram',
      };
      for (final channel in simChannels) {
        expect(channel.serverbound, serverbound.contains(channel.id), reason: channel.id);
      }
    });
  });

  group('addon hook', () {
    /// The plugin's registration path, without the host: the handled channels go
    /// through `PayloadRegistry.serverbound`, the rest through the addon's
    /// declared-only list.
    PayloadRegistry<Object?> registered() {
      final payloads = PayloadRegistry<Object?>();
      for (final id in SimHandledPayloads.ids) {
        final codec = SimPayloads.byId[id]!;
        payloads.serverbound<SimPacket>(
          id,
          PayloadCodec<SimPacket>.of(encode: codec.encode, decode: codec.decode),
          (_, _) {},
          version: SimChannel.version,
        );
      }
      SimulatedAddon(handled: SimHandledPayloads.idSet).contribute(payloads);
      return payloads;
    }

    test('the handled channels are serverbound channels of the mod', () {
      expect(SimHandledPayloads.ids, hasLength(6));
      expect(SimHandledPayloads.ids.toSet(), hasLength(6));
      for (final id in SimHandledPayloads.ids) {
        final codec = SimPayloads.byId[id];
        expect(codec, isNotNull, reason: id);
        expect(codec!.direction, SimPacketDirection.serverbound, reason: id);
      }
    });

    test('handling some and declaring the rest covers all 37 once', () {
      final payloads = registered();
      expect(payloads.ids, hasLength(37));
      expect(payloads.ids.toSet(), hasLength(37));
      expect(payloads.ids.toSet(), simChannels.map((c) => c.id).toSet());
      for (final channel in payloads.declared) {
        expect(channel.version, '0.1', reason: channel.id);
        expect(channel.optional, isFalse, reason: channel.id);
      }
    });

    test('the addon declares exactly the channels the plugin does not handle', () {
      final addon = SimulatedAddon(handled: SimHandledPayloads.idSet);
      final declared = addon.channels.map((c) => c.id).toList();
      expect(declared, hasLength(31));
      expect(declared.where(SimHandledPayloads.idSet.contains), isEmpty);
      expect(
        {...declared, ...SimHandledPayloads.ids},
        simChannels.map((c) => c.id).toSet(),
      );
      // The unhandled ones keep the Java order, so the declaration reads like
      // `SimPacketManager.init` minus the handled block.
      expect(
        declared,
        simChannels.map((c) => c.id).where((id) => !SimHandledPayloads.idSet.contains(id)).toList(),
      );
    });

    test('a handled channel dispatches its codec to the handler', () async {
      final payloads = registered();
      final channel = payloads.serverboundFor('simulated:assemble')!;
      expect(channel.version, '0.1');
      final decoded = channel.codec.decode(SimPayloads.encode(AssemblePacket(_pos)));
      expect(decoded, isA<AssemblePacket>());
      expect((decoded as AssemblePacket).pos, _pos);
    });
  });

  group('assembly', () {
    test('assemble is one packed block position', () {
      _expectBytes(AssemblePacket(_pos), (_Buf()..blockPos(_pos)).bytes);
    });

    test('be_observed is the same single long', () {
      _expectBytes(BlockEntityObservedPacket(_pos), (_Buf()..blockPos(_pos)).bytes);
    });

    test('assembler_failed is the position, flick carries the flag after it', () {
      _expectBytes(PhysicsAssemblerFailedPacket(_pos), (_Buf()..blockPos(_pos)).bytes);
      _expectBytes(
        PhysicsAssemblerFlickAndHoldLeverPacket(_pos, true),
        (_Buf()
              ..blockPos(_pos)
              ..u8(1))
            .bytes,
      );
    });
  });

  group('honey glue', () {
    test('spawn is two positions, and its box covers both corners', () {
      _expectBytes(
        HoneyGlueSpawnPacket((5, 64, 5), (2, 70, 1)),
        (_Buf()
              ..blockPos((5, 64, 5))
              ..blockPos((2, 70, 1)))
            .bytes,
      );

      final bounds = HoneyGlueSpawnPacket((5, 64, 5), (2, 70, 1)).bounds;
      expect((bounds.minX, bounds.minY, bounds.minZ), (2.0, 64.0, 1.0));
      expect((bounds.maxX, bounds.maxY, bounds.maxZ), (6.0, 71.0, 6.0));
    });

    test('change_bounds is six doubles then the uuid', () {
      final packet = HoneyGlueChangeBoundsPacket(const Aabb(1, 2, 3, 4, 5, 6), _uuid);
      _expectBytes(
        packet,
        (_Buf()
              ..f64(1)
              ..f64(2)
              ..f64(3)
              ..f64(4)
              ..f64(5)
              ..f64(6)
              ..uuid(_uuid))
            .bytes,
      );
    });

    test('sync is six doubles, the entity id, then the optional uuid', () {
      final withUuid = HoneyGlueSyncBoundsPacket(const Aabb(1, 2, 3, 4, 5, 6), 42, _uuid);
      _expectBytes(
        withUuid,
        (_Buf()
              ..f64(1)
              ..f64(2)
              ..f64(3)
              ..f64(4)
              ..f64(5)
              ..f64(6)
              ..i32(42)
              ..u8(1)
              ..uuid(_uuid))
            .bytes,
      );

      final without = HoneyGlueSyncBoundsPacket(const Aabb(1, 2, 3, 4, 5, 6), 42);
      _expectBytes(
        without,
        (_Buf()
              ..f64(1)
              ..f64(2)
              ..f64(3)
              ..f64(4)
              ..f64(5)
              ..f64(6)
              ..i32(42)
              ..u8(0))
            .bytes,
      );
      expect(SimPayloads.decode(without.id, SimPayloads.encode(without)).toString(), isNotEmpty);
    });
  });

  group('placement', () {
    test('place_spring is hand, parent, child, two direction varints', () {
      _expectBytes(
        PlaceSpringPacket(_pos, _pos2, Direction.north, Direction.up, 0),
        (_Buf()
              ..i32(0)
              ..blockPos(_pos)
              ..blockPos(_pos2)
              ..varInt(2)
              ..varInt(1))
            .bytes,
      );
    });

    test('place_merging_glue has the same shape', () {
      _expectBytes(
        PlaceMergingGluePacket(_pos, _pos2, Direction.east, Direction.down, 1),
        (_Buf()
              ..i32(1)
              ..blockPos(_pos)
              ..blockPos(_pos2)
              ..varInt(5)
              ..varInt(0))
            .bytes,
      );
    });
  });

  group('ropes', () {
    test('break_rope is a uuid, ride_rope appends the flag', () {
      _expectBytes(RopeBreakPacket(_uuid), (_Buf()..uuid(_uuid)).bytes);
      _expectBytes(
        RopeRidingPacket(_uuid, true),
        (_Buf()
              ..uuid(_uuid)
              ..u8(1))
            .bytes,
      );
    });

    test('rope_data writes the tick, owner, uuid, count, points, then the ends', () {
      final packet = ClientboundRopeDataPacket(
        interpolationTick: 7,
        ownerPos: _pos,
        uuid: _uuid,
        points: [Vector3d(1, 2, 3), Vector3d(4.5, 5.5, 6.5)],
        startAttachmentPos: _pos2,
      );
      final expected = _Buf()
        ..i32(7)
        ..blockPos(_pos)
        ..uuid(_uuid)
        ..i32(2)
        ..vec3d(Vector3d(1, 2, 3))
        ..vec3d(Vector3d(4.5, 5.5, 6.5))
        ..u8(1)
        ..blockPos(_pos2)
        ..u8(0);
      _expectBytes(packet, expected.bytes);

      final decoded = ClientboundRopeDataPacket.codec.decode(ClientboundRopeDataPacket.codec.encode(packet));
      expect(decoded.points, hasLength(2));
      expect(decoded.points.first.x, 1);
      expect(decoded.startAttachmentPos, _pos2);
      expect(decoded.endAttachmentPos, isNull);
    });

    test('rope_stopped is the owner position', () {
      _expectBytes(ClientboundRopeStoppedPacket(_pos), (_Buf()..blockPos(_pos)).bytes);
    });
  });

  group('physics staff', () {
    test('action is a VarInt enum ordinal, the uuid and a raw vector', () {
      _expectBytes(
        PhysicsStaffActionPacket(PhysicsStaffAction.lock, _uuid, Vector3d(1, 2, 3)),
        (_Buf()
              ..varInt(1)
              ..uuid(_uuid)
              ..vec3d(Vector3d(1, 2, 3)))
            .bytes,
      );
    });

    test('drag is the uuid, two raw vectors and four floats', () {
      final packet = PhysicsStaffDragPacket(
        _uuid,
        Vector3d(1, 2, 3),
        Vector3d(4, 5, 6),
        Quaterniond(0.5, 0.25, 0.125, 0.0625),
      );
      _expectBytes(
        packet,
        (_Buf()
              ..uuid(_uuid)
              ..vec3d(Vector3d(1, 2, 3))
              ..vec3d(Vector3d(4, 5, 6))
              ..f32(0.5)
              ..f32(0.25)
              ..f32(0.125)
              ..f32(0.0625))
            .bytes,
      );
    });

    test('beam is the uuid and two raw vectors', () {
      _expectBytes(
        PhysicsStaffBeamPacket(_uuid, Vector3d(1, 2, 3), Vector3d(4, 5, 6)),
        (_Buf()
              ..uuid(_uuid)
              ..vec3d(Vector3d(1, 2, 3))
              ..vec3d(Vector3d(4, 5, 6)))
            .bytes,
      );
    });

    test('locks is the dimension string then a list of uuids', () {
      _expectBytes(
        PhysicsStaffLocksPacket('minecraft:overworld', [_uuid]),
        (_Buf()
              ..str('minecraft:overworld')
              ..varInt(1)
              ..uuid(_uuid))
            .bytes,
      );
    });

    test('drag_sessions is the dimension then (uuid, vector) pairs', () {
      _expectBytes(
        PhysicsStaffDragSessionsPacket('minecraft:overworld', [(_uuid, Vector3d(1, 2, 3))]),
        (_Buf()
              ..str('minecraft:overworld')
              ..varInt(1)
              ..uuid(_uuid)
              ..vec3d(Vector3d(1, 2, 3)))
            .bytes,
      );
    });
  });

  group('handles and controls', () {
    test('update_player_handle is float, bool, position', () {
      _expectBytes(
        UpdatePlayerUsingHandlePacket(2.5, false, _pos),
        (_Buf()
              ..f32(2.5)
              ..u8(0)
              ..blockPos(_pos))
            .bytes,
      );
    });

    test('players_holding_handles is a count and the uuids', () {
      _expectBytes(
        ClientboundPlayersHoldingHandlePacket([_uuid]),
        (_Buf()
              ..varInt(1)
              ..uuid(_uuid))
            .bytes,
      );
    });

    test('steering_wheel is bool, float, position — in that order', () {
      _expectBytes(
        SteeringWheelPacket(true, 1.5, _pos),
        (_Buf()
              ..u8(1)
              ..f32(1.5)
              ..blockPos(_pos))
            .bytes,
      );
    });

    test('throttle_lever is position then int', () {
      _expectBytes(
        ThrottleLeverSignalPacket(_pos, 15),
        (_Buf()
              ..blockPos(_pos)
              ..i32(15))
            .bytes,
      );
    });

    test('plunger_launcher_shoot is one boolean (main hand)', () {
      _expectBytes(PlungerLauncherShootPacket(true), (_Buf()..u8(1)).bytes);
    });
  });

  group('sensors', () {
    test('altitude sensor is position then the two floats, clamped to 0..1', () {
      _expectBytes(
        ConfigureAltitudeSensorPacket(_pos, 0.25, 0.75),
        (_Buf()
              ..blockPos(_pos)
              ..f32(0.25)
              ..f32(0.75))
            .bytes,
      );
      final clamped = ConfigureAltitudeSensorPacket(_pos, 3, -2);
      expect(clamped.highSignal, 1.0);
      expect(clamped.lowSignal, 0.0);
    });

    test('modulating receiver is position then two ints', () {
      _expectBytes(
        ConfigureModulatingLinkedRecieverPacket(_pos, 2, 9),
        (_Buf()
              ..blockPos(_pos)
              ..i32(2)
              ..i32(9))
            .bytes,
      );
    });

    test('nameplate name is position then an optional string', () {
      _expectBytes(
        NameplateChangeNamePacket(_pos, 'bow'),
        (_Buf()
              ..blockPos(_pos)
              ..u8(1)
              ..str('bow'))
            .bytes,
      );
      _expectBytes(
        NameplateChangeNamePacket(_pos, null),
        (_Buf()
              ..blockPos(_pos)
              ..u8(0))
            .bytes,
      );
      _expectBytes(
        NameplateChangeNamePacket(_pos, ''),
        (_Buf()
              ..blockPos(_pos)
              ..u8(1)
              ..varInt(0))
            .bytes,
      );
    });

    test('lodestone position is the uuid and three doubles', () {
      _expectBytes(
        UpdateClientLodestonePositionPacket(_uuid, Vector3d(1, 2, 3)),
        (_Buf()
              ..uuid(_uuid)
              ..vec3d(Vector3d(1, 2, 3)))
            .bytes,
      );
    });
  });

  group('typewriter', () {
    test('key_interaction is position, key, scan code, action', () {
      _expectBytes(
        TypewriterKeyInteractionPacket(_pos, 65, 30, 1),
        (_Buf()
              ..blockPos(_pos)
              ..i32(65)
              ..i32(30)
              ..i32(1))
            .bytes,
      );
      expect(const TypewriterKeyInteractionPacket(_pos, 65, 30, 1).isPress, isTrue);
      expect(const TypewriterKeyInteractionPacket(_pos, 65, 30, 0).isPress, isFalse);
    });

    test('save is a map of entries, the position, then the clear flag', () {
      final entry = KeyboardEntry(glfwKeyCode: 65, first: const ItemStackData(10, 1), second: ItemStackData.empty);
      final packet = TypewriterKeySavePacket({65: entry}, _pos, false);
      _expectBytes(
        packet,
        (_Buf()
              ..varInt(1)
              ..i32(65)
              ..varInt(1)
              ..varInt(10)
              ..varInt(0)
              ..varInt(0)
              // the second stack is empty
              ..varInt(0)
              ..i32(65)
              ..blockPos(_pos)
              ..u8(0))
            .bytes,
      );
    });

    test('entry_modify is two optional stacks', () {
      _expectBytes(
        const TypewriterMenuModifySlots(ItemStackData.empty, ItemStackData.empty),
        (_Buf()
              ..varInt(0)
              ..varInt(0))
            .bytes,
      );
    });

    test('bind_item is the hand ordinal then the entry', () {
      final entry = KeyboardEntry(glfwKeyCode: 66);
      _expectBytes(
        TypewriterSaveKeyToItemPacket(1, entry),
        (_Buf()
              ..i32(1)
              ..varInt(0)
              ..varInt(0)
              ..i32(66))
            .bytes,
      );
    });

    test('disconnect is the position', () {
      _expectBytes(TypewriterDisconnectUser(_pos), (_Buf()..blockPos(_pos)).bytes);
    });
  });

  group('diagrams', () {
    test('config: identifier list, two bools, two doubles, then the note', () {
      final config = DiagramConfig(
        ['sable:gravity', 'sable:drag'],
        true,
        false,
        12.5,
        -3.5,
        NoteConfigs(BoundingBox3d.unchecked(1, 2, 3, 4, 5, 6), 0.5, 0.25, true),
      );
      final expected = _Buf()
        ..varInt(2)
        ..str('sable:gravity')
        ..str('sable:drag')
        ..u8(1)
        ..u8(0)
        ..f64(12.5)
        ..f64(-3.5)
        // BOUNDING_BOX_3D_STREAM_CODEC: VarInt 6 then the doubles.
        ..varInt(6)
        ..f64(1)
        ..f64(2)
        ..f64(3)
        ..f64(4)
        ..f64(5)
        ..f64(6)
        ..f64(0.5)
        ..f64(0.25)
        ..u8(1);

      final bytes = PacketBuffer.encode(config.write);
      expect(bytes, expected.bytes);
      final decoded = PacketBuffer.decode(bytes, DiagramConfig.read);
      expect(decoded, config);
    });

    test('save and open are the entity id then the config', () {
      final config = DiagramConfig(['sable:gravity'], false, false, 0, 0, NoteConfigs(BoundingBox3d(), 0, 0, false));
      final expected = (_Buf()..i32(9))..varInt(1)..str('sable:gravity');
      // The rest of the config is checked by the previous test.
      expect(
        SimPayloads.encode(DiagramSaveConfigPacket(9, config)).sublist(0, expected.bytes.length),
        expected.bytes,
      );
      expect(
        SimPayloads.encode(DiagramOpenPacket(9, config)).sublist(0, expected.bytes.length),
        expected.bytes,
      );
    });

    test('diagram_data carries the VarInt counts of the nested list codecs', () {
      final packet = DiagramDataPacket({
        'sable:gravity': [PointForce(Vector3d(1, 2, 3), Vector3d(4, 5, 6))],
      }, 120.0);
      final expected = _Buf()
        ..varInt(1)
        ..str('sable:gravity')
        ..varInt(1)
        // STREAM_POINT_FORCE: VarInt 2, then two STREAM_VECTOR3DC.
        ..varInt(2)
        ..varInt(3)
        ..f64(1)
        ..f64(2)
        ..f64(3)
        ..varInt(3)
        ..f64(4)
        ..f64(5)
        ..f64(6)
        ..f64(120.0);
      _expectBytes(packet, expected.bytes);

      final decoded = DiagramDataPacket.codec.decode(DiagramDataPacket.codec.encode(packet));
      expect(decoded.mass, 120.0);
      expect(decoded.forces['sable:gravity']!.single.force.x, 4);
    });

    test('request_diagram_data is the sub-level uuid', () {
      _expectBytes(RequestDiagramDataPacket(_uuid), (_Buf()..uuid(_uuid)).bytes);
    });
  });

  group('end sea', () {
    test('the entries are NBT compounds, not fields', () {
      final packet = ClientboundEndSeaPacket([
        const EndSeaPhysics(dimension: 'minecraft:the_end', priority: 0, startY: -40),
      ]);
      final bytes = SimPayloads.encode(packet);

      // A 4-byte int count (the Java code writes an int, not a VarInt), then a
      // TAG_Compound per entry.
      final reader = PacketReader(bytes);
      expect(reader.readInt(), 1);
      final tagBytes = reader.readRemainingBytes();
      expect(tagBytes.first, 10); // TAG_Compound
      final tag = NetworkNbt.read(PacketReader(tagBytes))!;
      expect(tag.asCompound['dimension']!.value, 'minecraft:the_end');
      expect(tag.asCompound['start_y']!.value, -40.0);
      expect(tag.asCompound['priority']!.value, 0);
      // The optional fields equal their default, so they are not written.
      expect(tag.asCompound.containsKey('depth_gradient'), isFalse);
      expect(tag.asCompound.containsKey('drag'), isFalse);
      expect(reader.isExhausted, isTrue);
    });

    test('round-trips, including the optional fields when they differ', () {
      final packet = ClientboundEndSeaPacket([
        const EndSeaPhysics(dimension: 'minecraft:the_end', startY: -40),
        const EndSeaPhysics(dimension: 'minecraft:overworld', priority: 3, startY: -64, depthGradient: 2.5, drag: 0.5),
      ]);
      final decoded = ClientboundEndSeaPacket.codec.decode(ClientboundEndSeaPacket.codec.encode(packet));
      expect(decoded.physics, hasLength(2));
      expect(decoded.physics[0].priority, isNull);
      expect(decoded.physics[0].depthGradient, 1.0);
      expect(decoded.physics[1], packet.physics[1]);
    });
  });

  group('every payload round-trips', () {
    final samples = <SimPacket>[
      AssemblePacket(_pos),
      BlockEntityObservedPacket(_pos),
      ConfigureAltitudeSensorPacket(_pos, 0.5, 0.5),
      ConfigureModulatingLinkedRecieverPacket(_pos, 1, 2),
      ThrottleLeverSignalPacket(_pos, 3),
      NameplateChangeNamePacket(_pos, 'x'),
      TypewriterKeyInteractionPacket(_pos, 1, 2, 3),
      TypewriterKeySavePacket({1: KeyboardEntry(glfwKeyCode: 1)}, _pos, true),
      TypewriterDisconnectUser(_pos),
      const TypewriterMenuModifySlots(ItemStackData.empty, ItemStackData.empty),
      TypewriterSaveKeyToItemPacket(0, KeyboardEntry(glfwKeyCode: 9)),
      SteeringWheelPacket(false, 0.25, _pos),
      PlaceSpringPacket(_pos, _pos2, Direction.up, Direction.down, 0),
      PlaceMergingGluePacket(_pos, _pos2, Direction.up, Direction.down, 0),
      UpdatePlayerUsingHandlePacket(1, true, _pos),
      HoneyGlueSpawnPacket(_pos, _pos2),
      HoneyGlueChangeBoundsPacket(const Aabb(0, 0, 0, 2, 2, 2), _uuid),
      HoneyGlueSyncBoundsPacket(const Aabb(0, 0, 0, 2, 2, 2), 1, _uuid),
      RopeRidingPacket(_uuid, false),
      RopeBreakPacket(_uuid),
      PhysicsStaffActionPacket(PhysicsStaffAction.startDrag, _uuid, Vector3d(1, 2, 3)),
      PhysicsStaffDragPacket(_uuid, Vector3d(1, 2, 3), Vector3d(4, 5, 6), Quaterniond()),
      PhysicsStaffBeamPacket(_uuid, Vector3d(1, 2, 3), Vector3d(4, 5, 6)),
      PhysicsStaffLocksPacket('minecraft:overworld', [_uuid]),
      PhysicsStaffDragSessionsPacket('minecraft:overworld', [(_uuid, Vector3d(1, 2, 3))]),
      PlungerLauncherShootPacket(false),
      PhysicsAssemblerFailedPacket(_pos),
      PhysicsAssemblerFlickAndHoldLeverPacket(_pos, true),
      ClientboundPlayersHoldingHandlePacket([_uuid]),
      ClientboundRopeDataPacket(interpolationTick: 1, ownerPos: _pos, uuid: _uuid, points: [Vector3d(1, 2, 3)]),
      ClientboundRopeStoppedPacket(_pos),
      ClientboundEndSeaPacket([const EndSeaPhysics(dimension: 'minecraft:the_end', startY: -40)]),
      RequestDiagramDataPacket(_uuid),
      DiagramDataPacket({'sable:gravity': [PointForce(Vector3d(1, 2, 3), Vector3d(4, 5, 6))]}, 1),
      DiagramSaveConfigPacket(1, DiagramConfig(['sable:gravity'], false, false, 0, 0, NoteConfigs(BoundingBox3d(), 0, 0, false))),
      DiagramOpenPacket(1, DiagramConfig(['sable:gravity'], false, false, 0, 0, NoteConfigs(BoundingBox3d(), 0, 0, false))),
      UpdateClientLodestonePositionPacket(_uuid, Vector3d(1, 2, 3)),
    ];

    test('there is a sample for every channel', () {
      expect(samples.map((p) => p.id).toSet(), SimPayloads.byId.keys.toSet());
    });

    for (final sample in samples) {
      test('${sample.id} encodes and decodes', () {
        final bytes = SimPayloads.encode(sample);
        final decoded = SimPayloads.decode(sample.id, bytes);
        expect(decoded.id, sample.id);
        // Re-encoding the decoded value gives the same bytes.
        expect(SimPayloads.encode(decoded), bytes);
      });
    }
  });
}
