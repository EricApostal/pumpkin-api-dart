// How the railway packets leave the server (pure interface). The host implementation sends the
// bytes as custom payloads (`manager_host.dart`); tests install a recorder.
import 'dart:typed_data';

/// The channels of the railway packets.
abstract final class RailwayChannels {
  static const String syncRailGraph = 'create:sync_rail_graph';
  static const String trackGraphRollCall = 'create:track_graph_roll_call';
  static const String trackGraphRequest = 'create:track_graph_request';
  static const String syncEdgeGroup = 'create:sync_edge_group';
}

abstract interface class RailwayNetwork {
  /// `NetworkHelper.INSTANCE.sendToAllClients(packet)`.
  void sendToAll(String channel, Uint8List data);

  /// `NetworkHelper.INSTANCE.sendToClient(player, packet)`; [player] is the host's `Player` (or an
  /// id the implementation understands).
  void sendTo(Object player, String channel, Uint8List data);
}

/// Drops everything (before the host is wired).
final class NullRailwayNetwork implements RailwayNetwork {
  const NullRailwayNetwork();

  @override
  void sendToAll(String channel, Uint8List data) {}

  @override
  void sendTo(Object player, String channel, Uint8List data) {}
}

/// A packet that went out (for tests).
final class SentPacket {
  final String channel;
  final Uint8List data;
  final Object? player;

  const SentPacket(this.channel, this.data, this.player);
}

/// Records what is sent.
final class RecordingRailwayNetwork implements RailwayNetwork {
  final List<SentPacket> sent = [];

  @override
  void sendToAll(String channel, Uint8List data) => sent.add(SentPacket(channel, data, null));

  @override
  void sendTo(Object player, String channel, Uint8List data) => sent.add(SentPacket(channel, data, player));
}

/// The installed network.
abstract final class RailwayNet {
  static RailwayNetwork current = const NullRailwayNetwork();
}
