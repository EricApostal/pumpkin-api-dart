// `SignalEdgeGroupPacket` (`create:sync_edge_group`, clientbound, pure): adds or removes signal edge
// groups (with their colours) on the clients.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../core/byte_buf.dart';
import 'edge_group_color.dart';

class SignalEdgeGroupPacket {
  final List<String> ids;
  final List<EdgeGroupColor> colors;
  final bool add;

  const SignalEdgeGroupPacket(this.ids, this.colors, this.add);

  /// `new SignalEdgeGroupPacket(id, color)`.
  SignalEdgeGroupPacket.added(String id, EdgeGroupColor color) : this([id], [color], true);

  void write(PacketWriter buffer) {
    buffer.writeList<String>(ids, (w, id) => w.writeUuid(id));
    buffer.writeList<EdgeGroupColor>(colors, (w, c) => w.writeEnum(c));
    buffer.writeBool(add);
  }

  static SignalEdgeGroupPacket read(PacketReader buffer) {
    final ids = buffer.readList((r) => r.readUuid());
    final colors = buffer.readList((r) => r.readEnum(EdgeGroupColor.values));
    return SignalEdgeGroupPacket(ids, colors, buffer.readBool());
  }

  Uint8List toBytes() => PacketBuffer.encode(write);
}
