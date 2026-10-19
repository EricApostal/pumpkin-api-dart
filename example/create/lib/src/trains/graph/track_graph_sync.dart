// `TrackGraphSync` (pure): collects the changes of the graphs and sends them to the clients as
// `create:sync_rail_graph` packets at the end of the tick, with a roll call afterwards. The bytes go
// out through [RailwayNet].
import '../../common/data.dart';
import '../signal/edge_group_color.dart';
import '../signal/signal_edge_group_packet.dart';
import '../signal/track_edge_point.dart';
import '../manager/create.dart';
import '../manager/railway_network.dart';
import 'edge_point_type.dart';
import 'track_edge.dart';
import 'track_graph.dart';
import 'track_graph_roll_call_packet.dart';
import 'track_graph_sync_packet.dart';
import 'track_node.dart';

class TrackGraphSync {
  List<TrackGraphSyncPacket> queuedPackets = [];
  int rollCallIn = 0;

  TrackGraphSyncPacket? currentGraphSyncPacket;
  int currentPayload = 0;

  void serverTick() {
    _flushGraphPacket();

    if (queuedPackets.isNotEmpty) {
      for (final packet in queuedPackets) {
        if (!packet.packetDeletesGraph && !Create.RAILWAYS.trackNetworks.containsKey(packet.graphId)) continue;
        RailwayNet.current.sendToAll(RailwayChannels.syncRailGraph, packet.toBytes());
        rollCallIn = 3;
      }

      queuedPackets.clear();
    }

    if (rollCallIn <= 0) return;
    rollCallIn--;
    if (rollCallIn > 0) return;

    _sendRollCall();
  }

  //

  void nodeAdded(TrackGraph graph, TrackNode node) {
    _flushGraphPacket1(graph);
    currentGraphSyncPacket!.addedNodes[node.getNetId()] = Pair.of(node.getLocation(), node.getNormal());
    currentPayload++;
  }

  void edgeAdded(TrackGraph graph, TrackNode node1, TrackNode node2, TrackEdge edge) {
    _flushGraphPacket1(graph);
    currentGraphSyncPacket!.addedEdges.add(
      Pair.of(Pair.of(Couple.create(node1.getNetId(), node2.getNetId()), edge.getTrackMaterial()), edge.getTurn()),
    );
    currentPayload++;
  }

  void pointAdded(TrackGraph graph, TrackEdgePoint point) {
    _flushGraphPacket1(graph);
    currentGraphSyncPacket!.addedEdgePoints.add(point);
    currentPayload++;
  }

  void pointRemoved(TrackGraph graph, TrackEdgePoint point) {
    _flushGraphPacket1(graph);
    currentGraphSyncPacket!.removedEdgePoints.add(point.getId());
    currentPayload++;
  }

  void nodeRemoved(TrackGraph graph, TrackNode node) {
    _flushGraphPacket1(graph);
    final nodeId = node.getNetId();
    final packet = currentGraphSyncPacket!;
    if (packet.addedNodes.remove(nodeId) == null) packet.removedNodes.add(nodeId);
    packet.addedEdges.removeWhere((pair) {
      final ids = pair.getFirst().getFirst();
      return ids.getFirst() == nodeId || ids.getSecond() == nodeId;
    });
  }

  void graphSplit(TrackGraph graph, Set<TrackGraph> additional) {
    _flushGraphPacket1(graph);
    for (final rg in additional) {
      currentGraphSyncPacket!.splitSubGraphs[rg.nodesById.keys.first] = Pair.of(rg.netId, rg.id);
    }
  }

  void graphRemoved(TrackGraph graph) {
    _flushGraphPacket1(graph);
    currentGraphSyncPacket!.packetDeletesGraph = true;
  }

  //

  /// `sendEdgeGroups(ids, colors, player)`.
  void sendEdgeGroups(List<String> ids, List<EdgeGroupColor> colors, Object player) {
    RailwayNet.current.sendTo(player, RailwayChannels.syncEdgeGroup, SignalEdgeGroupPacket(ids, colors, true).toBytes());
  }

  void edgeGroupCreated(String id, EdgeGroupColor color) {
    RailwayNet.current.sendToAll(RailwayChannels.syncEdgeGroup, SignalEdgeGroupPacket.added(id, color).toBytes());
  }

  void edgeGroupRemoved(String id) {
    RailwayNet.current.sendToAll(RailwayChannels.syncEdgeGroup, SignalEdgeGroupPacket([id], const [], false).toBytes());
  }

  //

  /// `edgeDataChanged(graph, node1, node2, edge)` and the variant with the opposite edge.
  void edgeDataChanged(TrackGraph graph, TrackNode node1, TrackNode node2, TrackEdge edge, [TrackEdge? edge2]) {
    _flushGraphPacket1(graph);
    currentGraphSyncPacket!.syncEdgeData(node1, node2, edge);
    if (edge2 != null) currentGraphSyncPacket!.syncEdgeData(node2, node1, edge2);
    currentPayload++;
  }

  /// `sendFullGraphTo(graph, player)`; [player] is the host's player handle.
  void sendFullGraphTo(TrackGraph graph, Object player) {
    var packet = TrackGraphSyncPacket(graph.id, graph.netId);
    packet.fullWipe = true;
    var sent = 0;

    final sentPoints = Set<TrackEdgePoint>.identity();

    for (final node in graph.nodes.values) {
      final currentPacket = packet;
      currentPacket.addedNodes[node.getNetId()] = Pair.of(node.getLocation(), node.getNormal());
      if (sent++ < 1000) continue;

      sent = 0;
      packet = _flushAndCreateNew(graph, player, packet);
    }

    for (final node in graph.nodes.values) {
      final currentPacket = packet;
      if (!graph.connectionsByNode.containsKey(node)) continue;

      for (final entry in graph.connectionsByNode[node]!.entries) {
        final node2 = entry.key;
        final edge = entry.value;

        final key = Couple.create(node.getNetId(), node2.getNetId());
        currentPacket.addedEdges.add(Pair.of(Pair.of(key, edge.getTrackMaterial()), edge.getTurn()));
        currentPacket.syncEdgeData(node, node2, edge);

        for (final point in edge.edgeData.getPoints()) {
          if (sentPoints.contains(point)) continue;

          sentPoints.add(point);
          currentPacket.addedEdgePoints.add(point);
          sent++;
        }
      }

      if (sent++ < 1000) continue;

      sent = 0;
      packet = _flushAndCreateNew(graph, player, packet);
    }

    for (final type in EdgePointType.TYPES.values) {
      for (final point in graph.getPoints(type)) {
        if (sentPoints.contains(point)) continue;

        sentPoints.add(point);
        packet.addedEdgePoints.add(point);

        if (sent++ < 1000) continue;

        sent = 0;
        packet = _flushAndCreateNew(graph, player, packet);
      }
    }

    if (sent > 0) _flushAndCreateNew(graph, player, packet);
  }

  void _sendRollCall() {
    RailwayNet.current.sendToAll(RailwayChannels.trackGraphRollCall, TrackGraphRollCallPacket.ofServer().toBytes());
  }

  TrackGraphSyncPacket _flushAndCreateNew(TrackGraph graph, Object player, TrackGraphSyncPacket packet) {
    RailwayNet.current.sendTo(player, RailwayChannels.syncRailGraph, packet.toBytes());
    return TrackGraphSyncPacket(graph.id, graph.netId);
  }

  //

  void _flushGraphPacket() => _flushGraphPacketIds(null, 0);

  void _flushGraphPacket1(TrackGraph graph) => _flushGraphPacketIds(graph.id, graph.netId);

  void _flushGraphPacketIds(String? graphId, int netId) {
    final current = currentGraphSyncPacket;
    if (current != null) {
      if (current.graphId == graphId && currentPayload < 1000) return;
      queuedPackets.add(current);
      currentGraphSyncPacket = null;
      currentPayload = 0;
    }

    if (graphId != null) {
      currentGraphSyncPacket = TrackGraphSyncPacket(graphId, netId);
      currentPayload = 0;
    }
  }
}
