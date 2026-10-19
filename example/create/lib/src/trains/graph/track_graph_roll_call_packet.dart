// `TrackGraphRollCallPacket` (`create:track_graph_roll_call`, clientbound, pure): the net id and
// checksum of every graph, so that clients can detect graphs that went out of sync.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../manager/create.dart';

class TrackGraphRollCallEntry {
  final int netId;
  final int checksum;

  const TrackGraphRollCallEntry(this.netId, this.checksum);

  void write(PacketWriter buffer) {
    buffer.writeVarInt(netId);
    buffer.writeInt(checksum);
  }

  static TrackGraphRollCallEntry read(PacketReader buffer) {
    final netId = buffer.readVarInt();
    return TrackGraphRollCallEntry(netId, buffer.readInt());
  }
}

class TrackGraphRollCallPacket {
  final List<TrackGraphRollCallEntry> entries;

  const TrackGraphRollCallPacket(this.entries);

  /// `ofServer()`.
  static TrackGraphRollCallPacket ofServer() => TrackGraphRollCallPacket([
    for (final graph in Create.RAILWAYS.trackNetworks.values) TrackGraphRollCallEntry(graph.netId, graph.getChecksum()),
  ]);

  void write(PacketWriter buffer) => buffer.writeList<TrackGraphRollCallEntry>(entries, (w, e) => e.write(w));

  static TrackGraphRollCallPacket read(PacketReader buffer) =>
      TrackGraphRollCallPacket(buffer.readList(TrackGraphRollCallEntry.read));

  Uint8List toBytes() => PacketBuffer.encode(write);
}
