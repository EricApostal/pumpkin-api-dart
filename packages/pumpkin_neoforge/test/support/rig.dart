// A test rig for the handshake: a ConfigurationSessions with a fake transport
// that records everything the server sends, plus a scripted client that
// answers like a NeoForge client (or like a broken one).
import 'dart:async';
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:pumpkin_api/src/configuration_core.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart';

class FakeTransport implements ConfigurationTransport {
  /// (channel, data) of every payload the server sent, in order.
  final List<(String, Uint8List)> sent = [];
  final List<String> events = [];
  String? disconnectReason;
  int releases = 0;
  void Function(String channel, Uint8List data)? onPayload;

  List<String> get channels => [for (final (c, _) in sent) c];

  Uint8List last(String channel) => sent.lastWhere((s) => s.$1 == channel).$2;

  List<Uint8List> all(String channel) => [
    for (final (c, d) in sent)
      if (c == channel) d,
  ];

  @override
  void sendPayload(int connectionId, String channel, Uint8List data) {
    sent.add((channel, data));
    events.add('send $channel');
    onPayload?.call(channel, data);
  }

  /// (packet id, body) of every raw packet the server sent.
  final List<(int, Uint8List)> packets = [];
  final List<ConnectionFlavour> flavours = [];
  ConfigurationException? failFlavour;
  void Function(int packetId, Uint8List body)? onPacket;

  @override
  void sendPacket(int connectionId, int packetId, Uint8List payload) {
    packets.add((packetId, payload));
    events.add('packet $packetId');
    onPacket?.call(packetId, payload);
  }

  @override
  void setFlavour(int connectionId, ConnectionFlavour flavour) {
    if (failFlavour != null) throw failFlavour!;
    flavours.add(flavour);
    events.add('flavour ${flavour.name}');
  }

  @override
  void release(int connectionId) {
    releases++;
    events.add('release');
  }

  @override
  void disconnect(int connectionId, String reason) {
    disconnectReason = reason;
    events.add('disconnect');
  }
}

class Rig {
  final FakeTransport transport = FakeTransport();
  late final ConfigurationSessions sessions = ConfigurationSessions(transport);
  final List<NeoForgeClient> results = [];
  final List<String> log = [];
  late final NeoForgeHandshake handshake;
  late ConfigurationConnection conn;

  Rig(
    NeoForgeServerSpec spec, {
    NeoForgeServerOptions options = const NeoForgeServerOptions(),
  }) {
    handshake = NeoForgeHandshake(
      spec,
      options: options,
      log: log.add,
      onResult: results.add,
    );
  }

  /// A client entered the configuration phase (start hold requested). With
  /// [preBrand] it is at the pre-brand event instead (the full mode); call
  /// [toStart] after the pre-brand handler released it.
  void begin({
    String uuid = '00000000-0000-0000-0000-000000000001',
    bool preBrand = false,
  }) {
    if (preBrand) {
      conn = sessions.preBrand(
        id: 1,
        uuid: uuid,
        username: 'Steve',
        protocolVersion: 777,
        holdTimeout: const Duration(seconds: 30),
      )!;
      return;
    }
    conn = sessions.start(
      id: 1,
      uuid: uuid,
      username: 'Steve',
      protocolVersion: 777,
      holdTimeout: const Duration(seconds: 30),
    )!;
  }

  void clientSends(
    String channel,
    List<int> data, {
    String? brand = 'neoforge',
  }) {
    sessions.payload(id: 1, channel: channel, data: data, brand: brand);
  }

  /// The server sent its brand and fired the start event.
  void toStart() {
    conn = sessions.start(
      id: 1,
      uuid: conn.uuid,
      username: 'Steve',
      protocolVersion: 777,
      holdTimeout: const Duration(seconds: 30),
    )!;
  }

  /// Runs the pre-brand handler like `Context.onConfiguration` does.
  Future<void> runPreBrand() => runConnectionHandler<ConfigurationConnection>(
    conn,
    handshake.preBrand,
    onError: (m) => throw StateError(m),
  );

  /// The client sent a raw packet (captured for `nextPacket`).
  void clientSendsPacket(int packetId, List<int> payload) =>
      sessions.packet(id: 1, packetId: packetId, payload: payload, capture: true);

  /// Runs the start handler like `Context.onConfiguration` does.
  Future<void> runStart() => runConnectionHandler<ConfigurationConnection>(
    conn,
    handshake.start,
    onError: (m) => throw StateError(m),
  );

  /// The server reached the finish hold.
  Future<void> runFinish() {
    final c = sessions.finish(id: 1, holdTimeout: const Duration(seconds: 30))!;
    return runConnectionHandler<ConfigurationConnection>(
      c,
      handshake.finish,
      onError: (m) => throw StateError(m),
    );
  }

  /// The client left.
  void clientLeaves() => sessions.end(id: 1, completed: false);
}

/// Answers like a NeoForge client does. Fields switch behaviours off.
class ScriptedClient {
  final Rig rig;

  /// What the client announces (`minecraft:register`) as soon as the server
  /// speaks (it is sent after the brand in real life).
  List<String>? announce = NeoForgeChannels.clientConfigurationListening;

  bool ackSync = true;
  bool answerQuery = true;
  bool answerPing = true;
  bool answerCommon = true;
  bool answerTasks = true;
  List<int> commonVersions = [1];
  Map<NetworkPhase, List<QueryComponent>> registrations =
      neoForgeOwnRegistrations;
  Map<String, List<String>> dataMaps = {};
  String? brand = 'neoforge';

  bool _announced = false;

  ScriptedClient(this.rig) {
    rig.transport.onPayload = _onServerPayload;
    rig.transport.onPacket = _onServerPacket;
  }

  void _onServerPacket(int packetId, Uint8List body) {
    if (packetId == configurationPingPacketId && answerPing) {
      scheduleMicrotask(
        () => rig.clientSendsPacket(configurationPongPacketId, body),
      );
    }
  }

  /// Sends the announcement now.
  void announceNow() {
    final list = announce;
    if (list == null || _announced) return;
    _announced = true;
    rig.clientSends(
      NeoForgeChannels.minecraftRegister,
      encodeRegisterChannels(list),
      brand: brand,
    );
  }

  void _reply(String channel, List<int> data) =>
      scheduleMicrotask(() => rig.clientSends(channel, data, brand: brand));

  void _onServerPayload(String channel, Uint8List data) {
    switch (channel) {
      case NeoForgeChannels.minecraftRegister:
        announceNow();
      case NeoForgeChannels.moddedNetworkQuery:
        if (answerQuery) {
          _reply(
            NeoForgeChannels.moddedNetworkQuery,
            ModdedNetworkQuery(registrations).encode(),
          );
        }
      case NeoForgeChannels.frozenRegistrySyncCompleted:
        if (ackSync) {
          _reply(NeoForgeChannels.frozenRegistrySyncCompleted, const []);
        }
      case NeoForgeChannels.commonVersion:
        if (answerCommon) {
          _reply(
            NeoForgeChannels.commonVersion,
            CommonVersion(commonVersions).encode(),
          );
        }
      case NeoForgeChannels.commonRegister:
        if (answerCommon) {
          _reply(
            NeoForgeChannels.commonRegister,
            CommonRegister(
              phase: NetworkPhase.play,
              channels: ['neoforge:recipe_content'],
            ).encode(),
          );
        }
      case NeoForgeChannels.knownRegistryDataMaps:
        if (answerTasks) {
          _reply(
            NeoForgeChannels.knownRegistryDataMapsReply,
            KnownRegistryDataMapsReply(dataMaps).encode(),
          );
        }
      case NeoForgeChannels.extensibleEnumData:
        if (answerTasks) _reply(NeoForgeChannels.extensibleEnumAck, const []);
      case NeoForgeChannels.featureFlags:
        if (answerTasks) _reply(NeoForgeChannels.featureFlagsAck, const []);
    }
  }
}
