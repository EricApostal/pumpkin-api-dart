// The UDP transport's packet type table.
//
// `SableUDPPacketType` is an enum whose **ordinal is on the wire**: the encoder
// writes `packetType.ordinal()` as one unsigned byte after the VarInt21 frame
// length. The declaration order below is therefore wire compatibility, not
// style: PING=0, SNAPSHOT=1, SNAPSHOT_INFO=2, AUTH=3, KEEP_ALIVE_CLIENTBOUND=4,
// ALIVE_SERVERBOUND=5.
//
// UDP is optional. `SubLevelTrackingSystem` falls back to TCP when a player has
// not authenticated, and the server never requires a UDP socket.
//
// Pure: no host imports.
import 'package:pumpkin_api/pumpkin_api_core.dart';

/// `dev.ryanhcode.sable.network.udp.SableUDPPacketType`.
enum SableUdpPacketType {
  /// `PING`: an echo with a text payload.
  ping,

  /// `SNAPSHOT`: the dual snapshot payload.
  snapshot,

  /// `SNAPSHOT_INFO`: the dual snapshot-info payload.
  snapshotInfo,

  /// `AUTH`: the client's authentication token (the player UUID).
  auth,

  /// `KEEP_ALIVE_CLIENTBOUND`: asks the client to answer `ALIVE_SERVERBOUND`.
  keepAliveClientbound,

  /// `ALIVE_SERVERBOUND`: the client's answer to a keep-alive.
  aliveServerbound;

  /// The Java enum constant name.
  String get javaName => switch (this) {
    SableUdpPacketType.ping => 'PING',
    SableUdpPacketType.snapshot => 'SNAPSHOT',
    SableUdpPacketType.snapshotInfo => 'SNAPSHOT_INFO',
    SableUdpPacketType.auth => 'AUTH',
    SableUdpPacketType.keepAliveClientbound => 'KEEP_ALIVE_CLIENTBOUND',
    SableUdpPacketType.aliveServerbound => 'ALIVE_SERVERBOUND',
  };

  /// The type byte on the wire (`ordinal()`).
  int get wireId => index;

  /// The type for a wire byte, or `null` when it is not a Sable type.
  static SableUdpPacketType? fromWire(int wireId) =>
      wireId >= 0 && wireId < values.length ? values[wireId] : null;
}

/// A payload that can travel over the UDP channel.
abstract interface class SableUdpPacket {
  /// The type byte the packet is framed with.
  SableUdpPacketType get type;

  /// The payload body.
  void write(PacketWriter buf);
}
