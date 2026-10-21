import 'package:create/src/common/common.dart';
import 'package:create/src/manifest/manifest.dart';
import 'package:create/src/protocol/codec_compiler.dart' show PayloadSchemas;
import 'package:create/src/protocol/payload_hub.dart';
import 'package:create/src/trains/graph/dimension_palette.dart';
import 'package:create/src/trains/graph/edge_point_type.dart';
import 'package:create/src/trains/graph/track_edge.dart';
import 'package:create/src/trains/graph/track_graph.dart';
import 'package:create/src/trains/graph/track_node.dart';
import 'package:create/src/trains/graph/track_node_location.dart';
import 'package:create/src/trains/graph/track_graph_sync_packet.dart';
import 'package:create/src/trains/graph/track_graph_roll_call_packet.dart';
import 'package:create/src/trains/manager/create.dart';
import 'package:create/src/trains/signal/edge_group_color.dart';
import 'package:create/src/trains/signal/signal_boundary.dart';
import 'package:create/src/trains/signal/signal_edge_group.dart';
import 'package:create/src/trains/signal/signal_edge_group_packet.dart';
import 'package:create/src/trains/track/bezier_connection.dart';
import 'package:create/src/trains/track/track_material.dart';
import 'package:create/src/trains/track/track_shape.dart';
import 'package:create/src/trains/track/track_voxel_shapes.dart';
import 'package:create/src/trains/util/ctag.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

/// A straight edge between two nodes of the overworld.
TrackEdge straightEdge(TrackNode a, TrackNode b) =>
    TrackEdge(a, b, null, TrackMaterial.ANDESITE);

TrackNode node(double x, double y, double z, int netId) => TrackNode(
  TrackNodeLocation(x, y, z).inDimension(overworldId),
  netId,
  (0.0, 1.0, 0.0),
);

void main() {
  group('dimension palette', () {
    test('encodes each dimension once, in first-seen order', () {
      final palette = DimensionPalette();
      expect(palette.encode('minecraft:overworld'), 0);
      expect(palette.encode('minecraft:the_nether'), 1);
      expect(palette.encode('minecraft:overworld'), 0);
      expect(palette.gatheredDims, [
        'minecraft:overworld',
        'minecraft:the_nether',
      ]);
      expect(palette.decode(1), 'minecraft:the_nether');
      expect(palette.decode(99), overworldId);
    });

    test('round-trips through NBT and the wire', () {
      final palette = DimensionPalette()
        ..encode('minecraft:the_nether')
        ..encode('minecraft:the_end');

      final tag = CTag();
      palette.write(tag);
      expect(DimensionPalette.read(tag).gatheredDims, palette.gatheredDims);

      final bytes = PacketBuffer.encode(palette.send);
      final back = DimensionPalette.receive(PacketReader(bytes));
      expect(back.gatheredDims, palette.gatheredDims);
    });
  });

  group('track node location', () {
    test('maps a world position onto the doubled grid', () {
      final location = TrackNodeLocation(1.0, 2.0, 3.0);
      expect((location.x, location.y, location.z), (2, 4, 6));
      expect(location.getLocation(), (1.0, 2.0, 3.0));

      final packed = TrackNodeLocation.packed(3, 5, 7);
      expect(packed.getLocation(), (1.5, 2.5, 3.5));
    });

    test('round-trips through NBT and the wire', () {
      final location = TrackNodeLocation.fromVec((1.5, 2.0, -3.5))
        ..inDimension('minecraft:the_nether')
        ..yOffsetPixels = 3;

      final palette = DimensionPalette();
      final tag = location.write(palette);
      final fromTag = TrackNodeLocation.read(tag, palette);
      expect(fromTag, location);
      expect(fromTag.dimension, 'minecraft:the_nether');
      expect(fromTag.yOffsetPixels, 3);

      final bytes = PacketBuffer.encode((w) => location.send(w, palette));
      final fromWire = TrackNodeLocation.receive(PacketReader(bytes), palette);
      expect(fromWire, location);
    });

    test('allAdjacent covers the eight neighbouring pixels', () {
      final adjacent = TrackNodeLocation.fromVec((0.0, 0.0, 0.0)).allAdjacent();
      expect(adjacent, hasLength(8));
      expect(adjacent, contains((-1, -1, -1)));
      expect(adjacent, contains((0, 0, 0)));
    });
  });

  group('track graph', () {
    test('adds nodes and edges and computes the checksum', () {
      final graph = TrackGraph('00000000-0000-4000-8000-000000000001');
      final a = node(0, 0, 0, 10);
      final b = node(0, 0, 4, 20);
      graph
        ..addNode(a)
        ..addNode(b);

      expect(graph.locateNode(a.location), same(a));
      expect(graph.getNode(20), same(b));
      expect(graph.getNodes(), hasLength(2));

      final edge = straightEdge(a, b);
      expect(graph.putConnection(a, b, edge), isTrue);
      expect(graph.getConnectionsFrom(a)[b], same(edge));
      expect(edge.getLength(), closeTo(4.0, 1e-9));
      expect(graph.getChecksum(), 30);
    });

    test('round-trips nodes and connections through NBT', () {
      final graph = TrackGraph('00000000-0000-4000-8000-000000000002');
      final a = node(0, 0, 0, 1);
      final b = node(0, 0, 4, 2);
      final c = node(4, 0, 4, 3);
      graph
        ..addNode(a)
        ..addNode(b)
        ..addNode(c);
      graph.putConnection(a, b, straightEdge(a, b));
      graph.putConnection(b, c, straightEdge(b, c));

      final palette = DimensionPalette();
      final tag = graph.write(palette);
      final back = TrackGraph.read(tag, palette);

      expect(back.nodes, hasLength(3));
      final backA = back.locateNode(a.location)!;
      final backB = back.locateNode(b.location)!;
      final backC = back.locateNode(c.location)!;
      expect(back.getConnectionsFrom(backA)[backB], isNotNull);
      expect(back.getConnectionsFrom(backB)[backC], isNotNull);
      expect(
        back.getConnectionsFrom(backA)[backB]!.getLength(),
        closeTo(4.0, 1e-9),
      );
    });

    test('removing a node drops its connections', () {
      final graph = TrackGraph('00000000-0000-4000-8000-000000000003');
      final a = node(0, 0, 0, 1);
      final b = node(0, 0, 4, 2);
      graph
        ..addNode(a)
        ..addNode(b);
      graph.putConnection(a, b, straightEdge(a, b));
      graph.putConnection(b, a, straightEdge(b, a));

      expect(graph.removeNode(null, a.location), isTrue);
      expect(graph.locateNode(a.location), isNull);
      expect(graph.getConnectionsFrom(b), isEmpty);
    });
  });

  group('bezier connection', () {
    BezierConnection curve() => BezierConnection(
      Couple.create((0, 0, 0), (0, 0, 4)),
      Couple.create((0.5, 0.0, 0.0), (0.5, 0.0, 4.0)),
      Couple.create((0.0, 0.0, 1.0), (0.0, 0.0, -1.0)),
      Couple.create((0.0, 1.0, 0.0), (0.0, 1.0, 0.0)),
      true,
      false,
      TrackMaterial.ANDESITE,
    );

    test('has a positive length and a secondary view', () {
      final bezier = curve();
      expect(bezier.getLength(), greaterThan(3.5));
      expect(bezier.getSegmentCount(), greaterThan(0));
      expect(bezier.getKey(), (0, 0, 4));
      expect(bezier.isPrimary(), isTrue);

      final secondary = bezier.secondary();
      expect(secondary.isPrimary(), isFalse);
      expect(secondary.bePositions.first, (0, 0, 4));
      expect(secondary.getLength(), closeTo(bezier.getLength(), 1e-6));
    });

    test('round-trips through NBT and the wire', () {
      final bezier = curve();
      final tag = bezier.write((0, 0, 0));
      final fromTag = BezierConnection.fromTag(tag, (0, 0, 0));
      expect(fromTag.getMaterial().id, 'create:andesite');
      expect(fromTag.getLength(), closeTo(bezier.getLength(), 1e-6));
      expect(fromTag.bePositions.first, bezier.bePositions.first);
      expect(fromTag.axes.first, bezier.axes.first);

      final bytes = PacketBuffer.encode(bezier.writeTo);
      final fromWire = BezierConnection.read(PacketReader(bytes));
      expect(fromWire.getLength(), closeTo(bezier.getLength(), 1e-6));
      expect(fromWire.getMaterial().id, 'create:andesite');
      expect(fromWire.bePositions.first, bezier.bePositions.first);
    });

    test('equalsSansMaterial ignores the material', () {
      final a = curve();
      final b = curve();
      expect(a.equalsSansMaterial(b), isTrue);
      expect(a.clone().equalsSansMaterial(b), isTrue);
    });
  });

  group('track shapes', () {
    test('every shape stays within the host box limit', () {
      for (final shape in TrackShape.values) {
        expect(
          TrackShapes.fullShape(shape).boxes.length,
          lessThanOrEqualTo(64),
          reason: 'selection ${shape.name}',
        );
        expect(
          TrackShapes.collisionShape(shape).boxes.length,
          lessThanOrEqualTo(64),
          reason: 'collision ${shape.name}',
        );
      }
    });

    test('ascending tracks have no collision, other tracks a thin slab', () {
      for (final shape in TrackShape.values) {
        final ascending = switch (shape) {
          TrackShape.ae ||
          TrackShape.aw ||
          TrackShape.an ||
          TrackShape.as_ => true,
          _ => false,
        };
        expect(
          TrackShapes.collisionShape(shape).boxes.isEmpty,
          ascending,
          reason: shape.name,
        );
      }
    });

    test('the shape state values of the manifest name every shape', () {
      const manifestValues = {
        'none',
        'zo',
        'xo',
        'pd',
        'nd',
        'an',
        'as',
        'ae',
        'aw',
        'tn',
        'ts',
        'te',
        'tw',
        'cr_o',
        'cr_d',
        'cr_pdx',
        'cr_pdz',
        'cr_ndx',
        'cr_ndz',
      };
      expect({
        for (final shape in TrackShape.values) shape.serializedName,
      }, manifestValues);
    });

    test('the shape rules are valid for the manifest shape property', () {
      final track = kBlocks.firstWhere((b) => b.key == 'track');
      final shape = track.properties.firstWhere((p) => p.name == 'shape');
      final definition = BlockDefinition(
        key: 'create:track',
        properties: [
          BlockProperty.enumeration('shape', shape.values),
          BlockProperty.boolean('turn'),
          BlockProperty.boolean('waterlogged'),
        ],
        defaultState: {'shape': 'zo', 'turn': 'false', 'waterlogged': 'false'},
        hardness: 0.8,
        blastResistance: 0.8,
        shapeRules: trackShapeRules(),
      );
      expect(definition.validate(), isEmpty);
      expect(definition.stateCount, 76);
    });
  });

  group('railway packets', () {
    test('sync rail graph bytes round-trip through the manifest schema', () {
      final packet = TrackGraphSyncPacket(
        '00000000-0000-4000-8000-000000000010',
        7,
      );
      packet.addedNodes[1] = Pair.of(
        TrackNodeLocation(0, 0, 0).inDimension(overworldId),
        (0.0, 1.0, 0.0),
      );
      packet.addedEdges.add(
        Pair.of(Pair.of(Couple.create(1, 2), TrackMaterial.ANDESITE), null),
      );
      packet.removedNodes.add(3);
      packet.removedEdgePoints.add('00000000-0000-4000-8000-000000000011');
      packet.updatedEdgeData[Couple.create(1, 2)] = Pair.of(1, [
        '00000000-0000-4000-8000-000000000011',
      ]);
      packet.splitSubGraphs[4] = Pair.of(
        8,
        '00000000-0000-4000-8000-000000000012',
      );

      final boundary = EdgePointType.SIGNAL.create();
      boundary.setId('00000000-0000-4000-8000-000000000020');
      boundary.setLocation(
        Couple.create(
          TrackNodeLocation(0, 0, 0).inDimension(overworldId),
          TrackNodeLocation(0, 0, 4).inDimension(overworldId),
        ),
        0.5,
      );
      boundary.groups.set(true, '00000000-0000-4000-8000-000000000021');
      boundary.groups.set(false, '00000000-0000-4000-8000-000000000022');
      packet.addedEdgePoints.add(boundary);

      // A `create:station` point appends its name, assembling flag and block entity position
      // (`GlobalStation.write(FriendlyByteBuf)`); a `create:observer` point appends nothing.
      final station = EdgePointType.STATION.create();
      station.setId('00000000-0000-4000-8000-000000000030');
      station.setLocation(
        Couple.create(
          TrackNodeLocation(0, 0, 0).inDimension(overworldId),
          TrackNodeLocation(0, 0, 8).inDimension(overworldId),
        ),
        0.25,
      );
      station.name = 'Track Station';
      station.assembling = true;
      packet.addedEdgePoints.add(station);

      final observer = EdgePointType.OBSERVER.create();
      observer.setId('00000000-0000-4000-8000-000000000031');
      observer.setLocation(
        Couple.create(
          TrackNodeLocation(0, 0, 0).inDimension(overworldId),
          TrackNodeLocation(0, 0, 4).inDimension(overworldId),
        ),
        0.75,
      );
      packet.addedEdgePoints.add(observer);

      final schema = PayloadSchemas.manifest['create:sync_rail_graph'];
      final bytes = packet.toBytes();
      final fields = schema.decode(bytes);
      expect(schema.encode(fields), bytes);
    });

    // The send path (`HostRailwayNetwork.sendToAll`/`sendTo`) decodes the pure packet's bytes with
    // the manifest schema and re-encodes them for the client. A graph containing a station edge
    // point used to be undecodable there (the schema only accounted for `create:signal` subclass
    // data), so every `create:sync_rail_graph` of a network with a station was dropped -- the
    // client then had no rail graph, which breaks the station screen and the track previews.
    test('a graph with a station edge point survives the send path', () {
      final hub = PayloadHub<Object>(
        schemas: PayloadSchemas.manifest,
        sink: (level, message) => fail('$level: $message'),
        describePlayer: (player) => '$player',
      );

      final packet = TrackGraphSyncPacket('00000000-0000-4000-8000-000000000040', 3);
      final station = EdgePointType.STATION.create();
      station.setId('00000000-0000-4000-8000-000000000041');
      station.setLocation(
        Couple.create(
          TrackNodeLocation(0, 0, 0).inDimension(overworldId),
          TrackNodeLocation(0, 0, 4).inDimension(overworldId),
        ),
        0.5,
      );
      station.name = 'Track Station';
      packet.addedEdgePoints.add(station);
      for (var i = 0; i < 13; i++) {
        packet.removedEdgePoints.add('00000000-0000-4000-8000-0000000005${i.toString().padLeft(2, '0')}');
      }

      final bytes = packet.toBytes();
      final fields = hub.decode('create:sync_rail_graph', bytes);
      expect(hub.encode('create:sync_rail_graph', fields), bytes);
    });

    test('edge group and roll call bytes round-trip', () {
      final groups = SignalEdgeGroupPacket(
        ['00000000-0000-4000-8000-000000000001'],
        [EdgeGroupColor.GREEN],
        true,
      );
      final groupSchema = PayloadSchemas.manifest['create:sync_edge_group'];
      expect(
        groupSchema.encode(groupSchema.decode(groups.toBytes())),
        groups.toBytes(),
      );

      final rollCall = TrackGraphRollCallPacket([
        TrackGraphRollCallEntry(7, 42),
      ]);
      final rollSchema =
          PayloadSchemas.manifest['create:track_graph_roll_call'];
      expect(
        rollSchema.encode(rollSchema.decode(rollCall.toBytes())),
        rollCall.toBytes(),
      );
    });
  });

  group('signal edge groups', () {
    setUp(() => Create.RAILWAYS.cleanUp());

    test('intersections are resolved through the global group map', () {
      final a = SignalEdgeGroup('00000000-0000-4000-8000-00000000000a');
      final b = SignalEdgeGroup('00000000-0000-4000-8000-00000000000b');
      Create.RAILWAYS.signalEdgeGroups = {a.id: a, b.id: b};

      a.putAdjacent(b.id);
      b.putAdjacent(a.id);
      a.putIntersection('i', b.id);

      expect(a.intersecting, {'i': b.id});
      expect(a.intersectingResolved, contains(b));
      expect(a.color, b.color);

      a.removeIntersection('i');
      expect(a.intersecting, isEmpty);
    });

    test(
      'resolveColor avoids the colours of adjacent groups outside the set',
      () {
        final a = SignalEdgeGroup('00000000-0000-4000-8000-00000000000a');
        final b = SignalEdgeGroup('00000000-0000-4000-8000-00000000000b');
        final c = SignalEdgeGroup('00000000-0000-4000-8000-00000000000c');
        Create.RAILWAYS.signalEdgeGroups = {a.id: a, b.id: b, c.id: c};

        a.putAdjacent(b.id);
        b.putAdjacent(a.id);
        a.putIntersection('i', b.id);
        expect(a.color, EdgeGroupColor.YELLOW);

        a.putAdjacent(c.id);
        a.resolveColor();
        expect(a.color, EdgeGroupColor.GREEN);
        expect(b.color, EdgeGroupColor.GREEN);
        expect(c.color, EdgeGroupColor.YELLOW);
      },
    );

    test(
      'a boundary reserves a group; another boundary still finds it occupied',
      () {
        final group = SignalEdgeGroup('00000000-0000-4000-8000-000000000010');
        Create.RAILWAYS.signalEdgeGroups = {group.id: group};

        final own = SignalBoundary();
        final other = SignalBoundary();
        expect(group.isOccupiedUnless(other), isFalse);

        group.reserved = own;
        expect(group.isOccupiedUnless(own), isFalse);
        expect(group.isOccupiedUnless(other), isTrue);

        group.reserved = null;
        expect(group.isOccupiedUnless(other), isFalse);
      },
    );

    test('edge group colours pick the next free slot', () {
      expect(EdgeGroupColor.YELLOW.mask, 1);
      expect(EdgeGroupColor.GREEN.strikeFrom(1), 3);
      expect(EdgeGroupColor.WHITE.strikeFrom(1), 1);
      expect(EdgeGroupColor.findNextAvailable(0), EdgeGroupColor.YELLOW);
      expect(EdgeGroupColor.findNextAvailable(1), EdgeGroupColor.GREEN);
      expect(EdgeGroupColor.findNextAvailable(0x1FF), EdgeGroupColor.WHITE);
      expect(EdgeGroupColor.getDefault(), EdgeGroupColor.YELLOW);
    });
  });
}
