// `TrackGraphRequestPacket` (`create:track_graph_request`, serverbound, pure): a client asks for the
// full state of the graph with this net id. [handle] is the server handler.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../manager/create.dart';

class TrackGraphRequestPacket {
  final int netId;

  const TrackGraphRequestPacket(this.netId);

  void write(PacketWriter buffer) => buffer.writeInt(netId);

  static TrackGraphRequestPacket read(PacketReader buffer) => TrackGraphRequestPacket(buffer.readInt());

  Uint8List toBytes() => PacketBuffer.encode(write);

  /// `handle(ServerPlayer)`: sends the full graph to [player] (the host's player handle).
  void handle(Object player) {
    for (final trackGraph in Create.RAILWAYS.trackNetworks.values) {
      if (trackGraph.netId == netId) {
        Create.RAILWAYS.sync.sendFullGraphTo(trackGraph, player);
        break;
      }
    }
  }
}
