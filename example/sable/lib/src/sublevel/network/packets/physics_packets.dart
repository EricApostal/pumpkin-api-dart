// The physics-config payloads: `physics_property`, `floating_material` and
// `dimension_physics`.
//
// These are the three payloads whose body is not a fixed layout in Java: two use
// `ByteBufCodecs.fromCodec(Codec)`, which is a nameless network-NBT root tag,
// and one uses a hand-written `StreamCodec`. See `network_nbt.dart` and
// `physics/dimension_physics.dart` for the field layouts.
//
// Registry ids: none of them carries a numeric registry id. They refer to
// blocks, tags, materials and dimensions by resource identifier, which the
// client resolves in its own registries (see `docs/sable-w4-packets.md`).
//
// Pure: no host imports.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../physics/dimension_physics.dart';
import '../../physics/floating_block_material.dart';
import '../../physics/physics_block_properties.dart';
import '../network_nbt.dart';
import '../packet.dart';

/// `ClientboundPhysicsPropertyPacket`.
///
/// Wire: the NBT form of `PhysicsBlockPropertiesDefinition.CODEC`.
final class ClientboundPhysicsPropertyPacket implements SablePacket {
  /// `Sable.sablePath("physics_property")`.
  static const String payloadId = 'sable:physics_property';

  final PhysicsBlockPropertiesDefinition definition;

  const ClientboundPhysicsPropertyPacket(this.definition);

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) => NetworkNbtMap.write(buf, definition.toNbt());

  /// `ClientboundPhysicsPropertyPacket.CODEC`.
  static ClientboundPhysicsPropertyPacket read(PacketReader buf) =>
      ClientboundPhysicsPropertyPacket(
        PhysicsBlockPropertiesDefinition.fromNbt(NetworkNbtMap.read(buf)),
      );

  /// `ClientboundPhysicsPropertyPacket.CODEC`.
  static final SablePacketCodec<ClientboundPhysicsPropertyPacket> codec =
      SableCodec<ClientboundPhysicsPropertyPacket>(
        payloadId,
        SablePacketDirection.clientbound,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() => 'ClientboundPhysicsPropertyPacket[$definition]';
}

/// `ClientboundFloatingBlockMaterialPacket`.
///
/// Wire: `Identifier name` (UTF-8 string), then the NBT form of
/// `FloatingBlockMaterial.CODEC`.
final class ClientboundFloatingBlockMaterialPacket implements SablePacket {
  /// `Sable.sablePath("floating_material")`.
  static const String payloadId = 'sable:floating_material';

  /// The material id (`sable:air`).
  final String name;

  final FloatingBlockMaterial material;

  const ClientboundFloatingBlockMaterialPacket(this.name, this.material);

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) {
    buf.writeString(name);
    material.write(buf);
  }

  /// `ClientboundFloatingBlockMaterialPacket.CODEC`.
  static ClientboundFloatingBlockMaterialPacket read(PacketReader buf) =>
      ClientboundFloatingBlockMaterialPacket(buf.readString(), FloatingBlockMaterial.read(buf));

  /// `ClientboundFloatingBlockMaterialPacket.CODEC`.
  static final SablePacketCodec<ClientboundFloatingBlockMaterialPacket> codec =
      SableCodec<ClientboundFloatingBlockMaterialPacket>(
        payloadId,
        SablePacketDirection.clientbound,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() => 'ClientboundFloatingBlockMaterialPacket[$name, $material]';
}

/// `ClientboundDimensionPhysicsPacket`.
///
/// Wire: `ByteBufCodecs.collection(DimensionPhysics.STREAM_CODEC)`, i.e. a
/// VarInt count followed by that many `DimensionPhysics` bodies.
final class ClientboundDimensionPhysicsPacket implements SablePacket {
  /// `Sable.sablePath("dimension_physics")`.
  static const String payloadId = 'sable:dimension_physics';

  final List<DimensionPhysics> dimensionPhysics;

  const ClientboundDimensionPhysicsPacket(this.dimensionPhysics);

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) {
    buf.writeVarInt(dimensionPhysics.length);
    for (final physics in dimensionPhysics) {
      physics.write(buf);
    }
  }

  /// `ClientboundDimensionPhysicsPacket.CODEC`.
  static ClientboundDimensionPhysicsPacket read(PacketReader buf) {
    final count = buf.readVarInt();
    if (count < 0) throw PacketException('Negative dimension physics count $count');
    return ClientboundDimensionPhysicsPacket([
      for (var i = 0; i < count; i++) DimensionPhysics.read(buf),
    ]);
  }

  /// `ClientboundDimensionPhysicsPacket.CODEC`.
  static final SablePacketCodec<ClientboundDimensionPhysicsPacket> codec =
      SableCodec<ClientboundDimensionPhysicsPacket>(
        payloadId,
        SablePacketDirection.clientbound,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() => 'ClientboundDimensionPhysicsPacket[${dimensionPhysics.length} entries]';
}
