// Binding-free, so the codecs run in VM tests.
// ignore: implementation_imports
import 'package:pumpkin_api/src/packet_buffer.dart';

/// The ModBridge wire protocol, a small stand-in for the protocol of a real
/// mod. `testclient/` speaks it for testing; a real mod would define its own.
/// All payloads are Minecraft `FriendlyByteBuf`s.
///
/// ```text
/// configuration  server -> client  modbridge:hello      varint protocol, string serverName
///                client -> server  modbridge:hello_ack  varint protocol, string modVersion
/// play           client -> server  modbridge:ping       long nonce
///                server -> client  modbridge:pong       long nonce, long serverTick
///                server -> client  modbridge:toast      string title, string message
/// ```
///
/// This file has no server bindings, so the codecs are unit tested.
abstract final class Protocol {
  static const version = 1;

  static const helloChannel = 'modbridge:hello';
  static const ackChannel = 'modbridge:hello_ack';
  static const pingChannel = 'modbridge:ping';
  static const pongChannel = 'modbridge:pong';
  static const toastChannel = 'modbridge:toast';

  static const maxName = 64;
  static const maxText = 256;

  static final hello = PayloadCodec<Hello>.buffer(
    write: (w, v) => w
      ..writeVarInt(v.protocol)
      ..writeString(v.serverName, maxLength: maxName),
    read: (r) => Hello(r.readVarInt(), r.readString(maxLength: maxName)),
  );

  static final ack = PayloadCodec<Ack>.buffer(
    write: (w, v) => w
      ..writeVarInt(v.protocol)
      ..writeString(v.modVersion, maxLength: maxName),
    read: (r) => Ack(r.readVarInt(), r.readString(maxLength: maxName)),
  );

  static final ping = PayloadCodec<Ping>.buffer(
    write: (w, v) => w.writeLong(v.nonce),
    read: (r) => Ping(r.readLong()),
  );

  static final pong = PayloadCodec<Pong>.buffer(
    write: (w, v) => w
      ..writeLong(v.nonce)
      ..writeLong(v.serverTick),
    read: (r) => Pong(r.readLong(), r.readLong()),
  );

  static final toast = PayloadCodec<Toast>.buffer(
    write: (w, v) => w
      ..writeString(v.title, maxLength: maxText)
      ..writeString(v.message, maxLength: maxText),
    read: (r) =>
        Toast(r.readString(maxLength: maxText), r.readString(maxLength: maxText)),
  );
}

final class Hello {
  final int protocol;
  final String serverName;
  const Hello(this.protocol, this.serverName);
}

final class Ack {
  final int protocol;
  final String modVersion;
  const Ack(this.protocol, this.modVersion);
}

final class Ping {
  final int nonce;
  const Ping(this.nonce);
}

final class Pong {
  final int nonce;
  final int serverTick;
  const Pong(this.nonce, this.serverTick);
}

final class Toast {
  final String title;
  final String message;
  const Toast(this.title, this.message);
}

/// Why a client did or did not pass the handshake.
enum HandshakeOutcome { accepted, noMod, wrongProtocol }

/// Decides what to do with the client's answer (`null` = no answer in time).
HandshakeOutcome judge(Ack? ack) {
  if (ack == null) return HandshakeOutcome.noMod;
  return ack.protocol == Protocol.version
      ? HandshakeOutcome.accepted
      : HandshakeOutcome.wrongProtocol;
}

/// Players that completed the handshake, by UUID.
final class ModUsers {
  final Map<String, String> _versions = {};

  void accept(String uuid, String modVersion) => _versions[uuid] = modVersion;
  void remove(String uuid) => _versions.remove(uuid);

  bool has(String uuid) => _versions.containsKey(uuid);
  String? versionOf(String uuid) => _versions[uuid];
  int get count => _versions.length;
}
