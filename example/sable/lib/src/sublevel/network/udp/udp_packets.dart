// The four UDP-only payloads and the UDP datagram framing.
//
// Framing (`SableUDPPacket.configureSerialization`): the channel pipeline is
// `Varint21FrameEncoder/Decoder` + the Sable encoder/decoder, so one datagram is
//
// ```
// VarInt frameLength          (number of bytes that follow)
// u8     packetType.ordinal()
// bytes  body
// ```
//
// The decoder rejects a type byte outside the enum and a frame with bytes left
// over, exactly like `SableUDPPacketDecoder`.
//
// Pure: no host imports.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import 'udp_packet.dart';

/// `SableUDPEchoPacket` (`PING`).
final class SableUdpEchoPacket implements SableUdpPacket {
  final String text;

  const SableUdpEchoPacket(this.text);

  @override
  SableUdpPacketType get type => SableUdpPacketType.ping;

  @override
  void write(PacketWriter buf) => buf.writeString(text);

  @override
  String toString() => 'SableUdpEchoPacket[$text]';
}

/// `SableUDPAuthenticationPacket` (`AUTH`): the player UUID as text.
final class SableUdpAuthenticationPacket implements SableUdpPacket {
  /// `uuid.toString()` of the player that is authenticating.
  final String token;

  const SableUdpAuthenticationPacket(this.token);

  @override
  SableUdpPacketType get type => SableUdpPacketType.auth;

  @override
  void write(PacketWriter buf) => buf.writeString(token);

  @override
  String toString() => 'SableUdpAuthenticationPacket[$token]';
}

/// `SableUDPClientboundKeepAlivePacket` (`KEEP_ALIVE_CLIENTBOUND`): empty body.
final class SableUdpClientboundKeepAlivePacket implements SableUdpPacket {
  const SableUdpClientboundKeepAlivePacket();

  @override
  SableUdpPacketType get type => SableUdpPacketType.keepAliveClientbound;

  @override
  void write(PacketWriter buf) {}

  @override
  String toString() => 'SableUdpClientboundKeepAlivePacket';
}

/// `SableUDPServerboundAlivePacket` (`ALIVE_SERVERBOUND`): empty body.
final class SableUdpServerboundAlivePacket implements SableUdpPacket {
  const SableUdpServerboundAlivePacket();

  @override
  SableUdpPacketType get type => SableUdpPacketType.aliveServerbound;

  @override
  void write(PacketWriter buf) {}

  @override
  String toString() => 'SableUdpServerboundAlivePacket';
}

/// A UDP payload codec: the body only, without the type byte.
abstract class SableUdpCodec<T extends SableUdpPacket> {
  /// `SableUDPPacketType.write`.
  void write(PacketWriter buf, T value);

  /// `SableUDPPacketType.create`.
  T read(PacketReader buf);

  /// Encodes the body.
  Uint8List encodeBody(T value) => PacketBuffer.encode((w) => write(w, value));

  /// Decodes the body.
  T decodeBody(List<int> data) => PacketBuffer.decode(data, read);

  const SableUdpCodec();
}

/// A [SableUdpCodec] whose functions are closures.
final class _UdpCodec<T extends SableUdpPacket> extends SableUdpCodec<T> {
  final void Function(PacketWriter buf, T value) _write;
  final T Function(PacketReader buf) _read;

  const _UdpCodec(this._write, this._read);

  @override
  void write(PacketWriter buf, T value) => _write(buf, value);

  @override
  T read(PacketReader buf) => _read(buf);
}

/// The `SableUDPPacketType` table: every type's codec, and the datagram framing.
abstract final class SableUdpPackets {
  /// `SableUDPEchoPacket.CODEC`.
  static final SableUdpCodec<SableUdpEchoPacket> echoCodec = _UdpCodec<SableUdpEchoPacket>(
    (buf, value) => value.write(buf),
    (buf) => SableUdpEchoPacket(buf.readString()),
  );

  /// `SableUDPAuthenticationPacket.CODEC`.
  static final SableUdpCodec<SableUdpAuthenticationPacket> authenticationCodec =
      _UdpCodec<SableUdpAuthenticationPacket>(
        (buf, value) => value.write(buf),
        (buf) => SableUdpAuthenticationPacket(buf.readString()),
      );

  /// `SableUDPClientboundKeepAlivePacket.CODEC`.
  static final SableUdpCodec<SableUdpClientboundKeepAlivePacket> keepAliveCodec =
      _UdpCodec<SableUdpClientboundKeepAlivePacket>(
        (buf, value) => value.write(buf),
        (buf) => const SableUdpClientboundKeepAlivePacket(),
      );

  /// `SableUDPServerboundAlivePacket.CODEC`.
  static final SableUdpCodec<SableUdpServerboundAlivePacket> aliveCodec =
      _UdpCodec<SableUdpServerboundAlivePacket>(
        (buf, value) => value.write(buf),
        (buf) => const SableUdpServerboundAlivePacket(),
      );

  /// The codec of each type; the dual snapshot payloads are registered by
  /// `SablePackets`, which owns both transports, so they are added here through
  /// [register].
  static final Map<SableUdpPacketType, SableUdpCodec<SableUdpPacket>> codecs = {};

  /// Registers [codec] for [type] (`SableUDPPacketType`'s constructor argument).
  static void register(SableUdpPacketType type, SableUdpCodec<SableUdpPacket> codec) {
    codecs[type] = codec;
  }

  /// Frames [packet] into a datagram.
  static Uint8List encode(SableUdpPacket packet) {
    final codec = codecs[packet.type];
    if (codec == null) {
      throw StateError('No UDP codec registered for ${packet.type.javaName}');
    }
    final body = codec.encodeBody(packet);
    final writer = PacketWriter()
      ..writeVarInt(body.length + 1)
      ..writeByte(packet.type.wireId)
      ..writeBytes(body);
    return writer.toBytes();
  }

  /// Unframes a datagram, or returns `null` when it is not a Sable datagram
  /// (unknown type or trailing bytes), like the Java decoder's drop path.
  static SableUdpPacket? decode(List<int> datagram) {
    final reader = PacketReader(datagram);
    try {
      final frameLength = reader.readVarInt();
      if (frameLength != reader.remaining) return null;

      final type = SableUdpPacketType.fromWire(reader.readUnsignedByte());
      if (type == null) return null;

      final codec = codecs[type];
      if (codec == null) return null;

      final packet = codec.read(reader);
      if (!reader.isExhausted) return null;
      return packet;
    } on PacketException {
      // A malformed datagram is dropped, like `SableUDPPacketDecoder` does.
      return null;
    }
  }
}
