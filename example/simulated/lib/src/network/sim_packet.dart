// The packet plumbing shared by every Simulated payload: the
// `CustomPacketPayload` surface, the direction of a payload, and the identity of
// `VeilPacketManager.create(Simulated.MOD_ID, "0.1")`.
//
// Veil registers a payload by its `CustomPacketPayload.Type`, a
// `ResourceLocation` built by `Simulated.path(path)`; the registrar version
// ("0.1") is part of the channel the client expects, so it lives here and not
// in the plugin.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.SimPacketManager
//       dev.simulated_team.simulated.Simulated#path
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

/// Which side may send a payload.
enum SimPacketDirection { clientbound, serverbound }

/// `net.minecraft.network.protocol.common.custom.CustomPacketPayload`.
abstract interface class SimPacket {
  /// The `CustomPacketPayload.Type`, e.g. `simulated:assemble`.
  String get id;
}

/// `StreamCodec<RegistryFriendlyByteBuf, T>` for one payload.
abstract class SimPacketCodec<T extends SimPacket> {
  const SimPacketCodec();

  /// The `CustomPacketPayload.Type` this codec is registered under.
  String get id;

  /// The direction the payload travels.
  SimPacketDirection get direction;

  /// `StreamCodec.encode`.
  void write(PacketWriter buf, T value);

  /// `StreamCodec.decode`.
  T read(PacketReader buf);

  /// Encodes [value] to a fresh byte array (the payload body only).
  Uint8List encode(T value) => PacketBuffer.encode((w) => write(w, value));

  /// Decodes a payload body; trailing bytes are an error, as Veil's reader
  /// rejects them.
  T decode(List<int> data) => PacketBuffer.decode(data, read);
}

/// A codec whose read/write functions are given as closures.
final class SimCodec<T extends SimPacket> extends SimPacketCodec<T> {
  @override
  final String id;

  @override
  final SimPacketDirection direction;

  final void Function(PacketWriter buf, T value) _write;
  final T Function(PacketReader buf) _read;

  const SimCodec(this.id, this.direction, this._write, this._read);

  @override
  void write(PacketWriter buf, T value) => _write(buf, value);

  @override
  T read(PacketReader buf) => _read(buf);
}

/// The identity of the Veil channel Simulated uses.
///
/// `VeilPacketManager.create(Simulated.MOD_ID, "0.1")` builds the channel named
/// `simulated:0.1`; every payload of the mod is registered on it, so this string
/// is wire compatibility, not a local choice.
abstract final class SimChannel {
  /// `Simulated.MOD_ID`.
  static const String modId = 'simulated';

  /// The registrar version: `event.registrar("0.1")`.
  static const String version = '0.1';

  /// The full channel name.
  static const String name = '$modId:$version';

  /// `Simulated.path(path)`.
  static String path(String path) => '$modId:$path';
}
