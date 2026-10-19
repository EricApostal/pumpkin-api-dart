// ignore_for_file: constant_identifier_names
// `TrackGraphSyncPacket` (`create:sync_rail_graph`, pure): the changes of one graph for the clients.
// `write` is the Java `write(FriendlyByteBuf)` byte for byte, `read` the decoding constructor
// (used by tests and tools; the server never receives this packet). The client-side `handle` is not
// ported.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../common/data.dart';
import '../../common/vec_helper.dart';
import '../../core/byte_buf.dart';
import '../signal/track_edge_point.dart';
import '../track/bezier_connection.dart';
import '../track/track_material.dart';
import 'dimension_palette.dart';
import 'edge_data.dart';
import 'edge_point_type.dart';
import 'track_edge.dart';
import 'track_node.dart';
import 'track_node_location.dart';

/// `TrackGraphPacket`: the fields every graph packet has.
abstract class TrackGraphPacket {
  late String graphId;
  late int netId;
  bool packetDeletesGraph = false;
}

class TrackGraphSyncPacket extends TrackGraphPacket {
  Map<int, Pair<TrackNodeLocation, Vec3>> addedNodes = {};
  List<Pair<Pair<Couple<int>, TrackMaterial>, BezierConnection?>> addedEdges = [];
  List<int> removedNodes = [];
  List<TrackEdgePoint> addedEdgePoints = [];
  List<String> removedEdgePoints = [];
  Map<int, Pair<int, String>> splitSubGraphs = {};
  Map<Couple<int>, Pair<int, List<String>>> updatedEdgeData = {};

  bool fullWipe = false;

  static const int NULL_GROUP = 0, PASSIVE_GROUP = 1, GROUP = 2;

  TrackGraphSyncPacket(String graphId, int netId) {
    this.graphId = graphId;
    this.netId = netId;
  }

  /// `new TrackGraphSyncPacket(FriendlyByteBuf)`.
  TrackGraphSyncPacket.read(PacketReader buffer) {
    graphId = buffer.readUuid();
    netId = buffer.readInt();
    packetDeletesGraph = buffer.readBool();
    fullWipe = buffer.readBool();

    if (packetDeletesGraph) return;

    final dimensions = DimensionPalette.receive(buffer);

    var size = buffer.readVarInt();
    for (var i = 0; i < size; i++) {
      removedNodes.add(buffer.readVarInt());
    }

    size = buffer.readVarInt();
    for (var i = 0; i < size; i++) {
      final id = buffer.readVarInt();
      final location = TrackNodeLocation.receive(buffer, dimensions);
      addedNodes[id] = Pair.of(location, buffer.readVec3());
    }

    size = buffer.readVarInt();
    for (var i = 0; i < size; i++) {
      final a = buffer.readVarInt();
      final b = buffer.readVarInt();
      final material = TrackMaterial.deserialize(buffer.readString());
      final turn = buffer.readBool() ? BezierConnection.read(buffer) : null;
      addedEdges.add(Pair.of(Pair.of(Couple.create(a, b), material), turn));
    }

    size = buffer.readVarInt();
    for (var i = 0; i < size; i++) {
      addedEdgePoints.add(EdgePointType.read(buffer, dimensions));
    }

    size = buffer.readVarInt();
    for (var i = 0; i < size; i++) {
      removedEdgePoints.add(buffer.readUuid());
    }

    size = buffer.readVarInt();
    for (var i = 0; i < size; i++) {
      final list = <String>[];
      final a = buffer.readInt();
      final b = buffer.readInt();
      final key = Couple.create(a, b);
      final entry = Pair.of(buffer.readVarInt(), list);
      final size2 = buffer.readVarInt();
      for (var j = 0; j < size2; j++) {
        list.add(buffer.readUuid());
      }
      updatedEdgeData[key] = entry;
    }

    size = buffer.readVarInt();
    for (var i = 0; i < size; i++) {
      final node = buffer.readVarInt();
      final splitNetId = buffer.readInt();
      splitSubGraphs[node] = Pair.of(splitNetId, buffer.readUuid());
    }
  }

  void write(PacketWriter buffer) {
    buffer.writeUuid(graphId);
    buffer.writeInt(netId);
    buffer.writeBool(packetDeletesGraph);
    buffer.writeBool(fullWipe);

    if (packetDeletesGraph) return;

    // Populate and send palette ahead of time
    final dimensions = DimensionPalette();
    addedNodes.forEach((node, loc) => dimensions.encode(loc.getFirst().dimension));
    for (final ep in addedEdgePoints) {
      ep.edgeLocation.forEach((loc) => dimensions.encode(loc.dimension));
    }
    dimensions.send(buffer);

    buffer.writeVarInt(removedNodes.length);
    for (final n in removedNodes) {
      buffer.writeVarInt(n);
    }

    buffer.writeVarInt(addedNodes.length);
    addedNodes.forEach((node, loc) {
      buffer.writeVarInt(node);
      loc.getFirst().send(buffer, dimensions);
      buffer.writeVec3(loc.getSecond());
    });

    buffer.writeVarInt(addedEdges.length);
    for (final pair in addedEdges) {
      pair.getFirst().getFirst().forEach(buffer.writeVarInt);
      buffer.writeString(pair.getFirst().getSecond().id);
      final turn = pair.getSecond();
      buffer.writeBool(turn != null);
      if (turn != null) turn.writeTo(buffer);
    }

    buffer.writeVarInt(addedEdgePoints.length);
    for (final ep in addedEdgePoints) {
      ep.writeBuffer(buffer, dimensions);
    }

    buffer.writeVarInt(removedEdgePoints.length);
    for (final id in removedEdgePoints) {
      buffer.writeUuid(id);
    }

    buffer.writeVarInt(updatedEdgeData.length);
    for (final entry in updatedEdgeData.entries) {
      entry.key.forEach(buffer.writeInt);
      final pair = entry.value;
      buffer.writeVarInt(pair.getFirst());
      final list = pair.getSecond();
      buffer.writeVarInt(list.length);
      for (final id in list) {
        buffer.writeUuid(id);
      }
    }

    buffer.writeVarInt(splitSubGraphs.length);
    splitSubGraphs.forEach((node, p) {
      buffer.writeVarInt(node);
      buffer.writeInt(p.getFirst());
      buffer.writeUuid(p.getSecond());
    });
  }

  /// The bytes of the packet.
  Uint8List toBytes() => PacketBuffer.encode(write);

  void syncEdgeData(TrackNode node1, TrackNode node2, TrackEdge edge) {
    final key = Couple.create(node1.getNetId(), node2.getNetId());
    final list = <String>[];
    final edgeData = edge.getEdgeData();
    final groupType = edgeData.hasSignalBoundaries()
        ? NULL_GROUP
        : (edgeData.getSingleSignalGroup() == EdgeData.passiveGroup ? PASSIVE_GROUP : GROUP);
    if (groupType == GROUP) list.add(edgeData.getSingleSignalGroup()!);
    for (final point in edgeData.getPoints()) {
      list.add(point.getId());
    }
    updatedEdgeData[key] = Pair.of(groupType, list);
  }
}
