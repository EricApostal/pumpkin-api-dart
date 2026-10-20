// The packet plumbing shared by every Sable payload: the `CustomPacketPayload`
// surface, the direction of a payload, and the registry of
// `VeilPacketManager.create(Sable.MOD_ID, "1")`.
//
// Veil registers a payload by its `CustomPacketPayload.Type`, which is a
// `ResourceLocation`; `Sable.sablePath(path)` builds `sable:<path>`. The
// registrar version string ("1") is part of the channel name the client
// expects, so it is part of this file rather than of the plugin.
//
// Pure: no host imports.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

/// Which side may send a payload.
enum SablePacketDirection {
  /// Server to client.
  clientbound,

  /// Client to server.
  serverbound,

  /// Both (the dual snapshot payloads travel over TCP and UDP).
  both,
}

/// `net.minecraft.network.protocol.common.custom.CustomPacketPayload`.
abstract interface class SablePacket {
  /// The `CustomPacketPayload.Type`, e.g. `sable:start_tracking_sublevel`.
  String get id;

  /// The payload body, without the type id (Veil writes that).
  void write(PacketWriter buf);
}

/// `StreamCodec<RegistryFriendlyByteBuf, T>` for one payload.
abstract class SablePacketCodec<T extends SablePacket> {
  /// The `CustomPacketPayload.Type` this codec is registered under.
  String get id;

  /// The direction the payload travels.
  SablePacketDirection get direction;

  /// `StreamCodec.encode`.
  void write(PacketWriter buf, T value);

  /// `StreamCodec.decode`.
  T read(PacketReader buf);

  /// Encodes [value] to a fresh byte array (the payload body only).
  Uint8List encode(T value) => PacketBuffer.encode((w) => write(w, value));

  /// Decodes a payload body; trailing bytes are an error, as Veil's reader
  /// rejects them.
  T decode(List<int> data) => PacketBuffer.decode(data, read);

  const SablePacketCodec();
}

/// A codec whose read/write functions are given as closures.
final class SableCodec<T extends SablePacket> extends SablePacketCodec<T> {
  @override
  final String id;

  @override
  final SablePacketDirection direction;

  final void Function(PacketWriter buf, T value) _write;
  final T Function(PacketReader buf) _read;

  const SableCodec(this.id, this.direction, this._write, this._read);

  @override
  void write(PacketWriter buf, T value) => _write(buf, value);

  @override
  T read(PacketReader buf) => _read(buf);
}

/// The identity of the Veil channel Sable uses.
///
/// `VeilPacketManager.create(Sable.MOD_ID, "1")` builds a channel named
/// `sable:1`; `SableTCPPackets.init` registers every payload on it. The client
/// mod is installed with the same channel name, so this string is wire
/// compatibility, not a local choice.
abstract final class SableChannel {
  /// `Sable.MOD_ID`.
  static const String modId = 'sable';

  /// The registrar version: `event.registrar("1")`.
  static const String version = '1';

  /// The full channel name.
  static const String name = '$modId:$version';

  /// `Sable.sablePath(path)`.
  static String path(String path) => '$modId:$path';
}
