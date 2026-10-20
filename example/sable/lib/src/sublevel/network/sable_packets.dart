// `dev.ryanhcode.sable.network.tcp.SableTCPPackets`: every payload Sable
// registers, by id and direction, on the Veil channel `sable:1`.
//
// The registration order below is the Java `SableTCPPackets.init` order. Veil
// itself identifies a payload by its `CustomPacketPayload.Type` (the id), not by
// position, so the order matters only for documentation and for
// `SablePackets.allClientbound` stability in tests.
//
// Pure: no host imports.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import 'packet.dart';
import 'packets/misc_packets.dart';
import 'packets/physics_packets.dart';
import 'packets/snapshot_packets.dart';
import 'packets/tracking_packets.dart';
import 'udp/udp_packet.dart';
import 'udp/udp_packets.dart';

/// The payload table.
abstract final class SablePackets {
  /// Every clientbound payload, in `SableTCPPackets.init` order.
  static final List<SablePacketCodec<SablePacket>> allClientbound = [
    _cast(ClientboundSableSnapshotDualPacket.codec),
    _cast(ClientboundSableSnapshotInfoDualPacket.codec),
    _cast(ClientboundStopMovingSubLevelPacket.codec),
    _cast(ClientboundChangeSubLevelNamePacket.codec),
    _cast(ClientboundStartTrackingSubLevelPacket.codec),
    _cast(ClientboundFinalizeSubLevelPacket.codec),
    _cast(ClientboundStopTrackingSubLevelPacket.codec),
    _cast(ClientboundChangeBoundsSubLevelPacket.codec),
    _cast(ClientboundFreezePlayerPacket.codec),
    _cast(ClientboundPhysicsPropertyPacket.codec),
    _cast(ClientboundFloatingBlockMaterialPacket.codec),
    _cast(ClientboundDimensionPhysicsPacket.codec),
    _cast(ClientboundRecentlySplitSubLevelPacket.codec),
    _cast(ClientboundSableUdpActivationPacket.codec),
    _cast(ClientboundEnterGizmoPacket.codec),
  ];

  /// Every serverbound payload, in `SableTCPPackets.init` order.
  static final List<SablePacketCodec<SablePacket>> allServerbound = [
    _cast(ServerboundPunchSubLevelPacket.codec),
    _cast(ServerboundGizmoMoveSubLevelPacket.codec),
  ];

  /// The clientbound codecs by payload id.
  static final Map<String, SablePacketCodec<SablePacket>> clientbound = {
    for (final codec in allClientbound) codec.id: codec,
  };

  /// The serverbound codecs by payload id.
  static final Map<String, SablePacketCodec<SablePacket>> serverbound = {
    for (final codec in allServerbound) codec.id: codec,
  };

  /// The codec of [id] in [direction], or `null`.
  static SablePacketCodec<SablePacket>? codec(String id, SablePacketDirection direction) =>
      switch (direction) {
        SablePacketDirection.clientbound => clientbound[id],
        SablePacketDirection.serverbound => serverbound[id],
        SablePacketDirection.both => clientbound[id] ?? serverbound[id],
      };

  /// Encodes a payload body (no type id; Veil writes that).
  static Uint8List encode(SablePacket packet) {
    final found = codec(packet.id, SablePacketDirection.both);
    if (found == null) throw ArgumentError.value(packet.id, 'packet', 'is not a Sable payload');
    return found.encode(packet);
  }

  /// Decodes a clientbound payload body; throws for an unknown id.
  static SablePacket decodeClientbound(String id, List<int> data) {
    final codec = clientbound[id];
    if (codec == null) throw ArgumentError.value(id, 'id', 'is not a clientbound Sable payload');
    return codec.decode(data);
  }

  /// Decodes a serverbound payload body; throws for an unknown id.
  static SablePacket decodeServerbound(String id, List<int> data) {
    final codec = serverbound[id];
    if (codec == null) throw ArgumentError.value(id, 'id', 'is not a serverbound Sable payload');
    return codec.decode(data);
  }

  /// Registers the dual snapshot payloads as UDP types, so
  /// `SableUdpPacketType.SNAPSHOT` / `SNAPSHOT_INFO` have codecs. Safe to call
  /// more than once.
  static void registerUdpCodecs() {
    SableUdpPackets.register(SableUdpPacketType.ping, _udp(SableUdpPackets.echoCodec));
    SableUdpPackets.register(SableUdpPacketType.snapshot, _snapshotCodec);
    SableUdpPackets.register(SableUdpPacketType.snapshotInfo, _snapshotInfoCodec);
    SableUdpPackets.register(SableUdpPacketType.auth, _udp(SableUdpPackets.authenticationCodec));
    SableUdpPackets.register(
      SableUdpPacketType.keepAliveClientbound,
      _udp(SableUdpPackets.keepAliveCodec),
    );
    SableUdpPackets.register(SableUdpPacketType.aliveServerbound, _udp(SableUdpPackets.aliveCodec));
  }

  static final SableUdpCodec<SableUdpPacket> _snapshotCodec = _UdpBridge(
    _cast(ClientboundSableSnapshotDualPacket.codec),
  );

  static final SableUdpCodec<SableUdpPacket> _snapshotInfoCodec = _UdpBridge(
    _cast(ClientboundSableSnapshotInfoDualPacket.codec),
  );

  /// Widens a typed codec to `SablePacket`.
  static SablePacketCodec<SablePacket> _cast<T extends SablePacket>(SablePacketCodec<T> codec) =>
      _WidenedCodec<T>(codec);

  /// Widens a UDP codec to `SableUdpPacket`.
  static SableUdpCodec<SableUdpPacket> _udp<T extends SableUdpPacket>(SableUdpCodec<T> codec) =>
      _WidenedUdpCodec<T>(codec);
}

/// A codec viewed as its supertype.
final class _WidenedCodec<T extends SablePacket> implements SablePacketCodec<SablePacket> {
  final SablePacketCodec<T> _inner;

  _WidenedCodec(this._inner);

  @override
  String get id => _inner.id;

  @override
  SablePacketDirection get direction => _inner.direction;

  @override
  void write(PacketWriter buf, SablePacket value) => _inner.write(buf, value as T);

  @override
  SablePacket read(PacketReader buf) => _inner.read(buf);

  @override
  Uint8List encode(SablePacket value) => _inner.encode(value as T);

  @override
  SablePacket decode(List<int> data) => _inner.decode(data);
}

/// A UDP codec viewed as its supertype.
final class _WidenedUdpCodec<T extends SableUdpPacket> implements SableUdpCodec<SableUdpPacket> {
  final SableUdpCodec<T> _inner;

  _WidenedUdpCodec(this._inner);

  @override
  void write(PacketWriter buf, SableUdpPacket value) => _inner.write(buf, value as T);

  @override
  SableUdpPacket read(PacketReader buf) => _inner.read(buf);

  @override
  Uint8List encodeBody(SableUdpPacket value) => _inner.encodeBody(value as T);

  @override
  SableUdpPacket decodeBody(List<int> data) => _inner.decodeBody(data);
}

/// Adapts a dual payload's TCP codec to the UDP codec interface.
final class _UdpBridge implements SableUdpCodec<SableUdpPacket> {
  final SablePacketCodec<SablePacket> _inner;

  _UdpBridge(this._inner);

  @override
  void write(PacketWriter buf, SableUdpPacket value) => _inner.write(buf, value as SablePacket);

  @override
  SableUdpPacket read(PacketReader buf) => _inner.read(buf) as SableUdpPacket;

  @override
  Uint8List encodeBody(SableUdpPacket value) => _inner.encode(value as SablePacket);

  @override
  SableUdpPacket decodeBody(List<int> data) => _inner.decode(data) as SableUdpPacket;
}
