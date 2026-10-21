// A station on a real rail graph, as the client hears about it.
//
// The station screen, the station markers and the track previews a Create client draws all read
// the rail graph it was told about (`create:sync_rail_graph`), and the graph carries the station's
// edge point (`EdgePointType.STATION` / `GlobalStation`) with its name, its assembling flag and
// its block entity position. If that packet never reaches the client - because the plugin's own
// bytes failed to decode into the manifest schema in `HostRailwayNetwork` before they went out -
// the station is invisible to the client even though the server has it.
//
// This test drives the client's side: it boots the real server with the plugin, joins a simulated
// client, builds a straight run of `create:track`, aims a `create:track_station` at the middle of
// that run through its `TrackTargeting` behaviour, and then decodes what the client actually
// received.
//
// Run it with (see example/create/README.md):
//
// ```sh
// PUMPKIN_E2E=1 PUMPKIN_BIN=<build>/pumpkin PUMPKIN_TESTER_BIN=<build>/pumpkin-tester \
//   PUMPKIN_PLUGIN_WASM=<build>/create.wasm puro dart test test/e2e/station_rail_graph_test.dart
// ```

@Tags(['e2e'])
@Timeout(Duration(minutes: 20))
library;

import 'package:create/src/trains/graph/track_graph_sync_packet.dart';
import 'package:create/src/trains/station/global_station.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

import '../support/pumpkin_lab.dart';
import '../support/pumpkin_trace.dart';

/// The channel of the graph packet.
const String syncRailGraph = 'create:sync_rail_graph';

/// Every `create:sync_rail_graph` payload the client received, decoded with the port that decodes
/// the packet (`TrackGraphSyncPacket.read`); a payload the client could not decode fails here.
List<TrackGraphSyncPacket> graphsIn(PumpkinTrace trace) => [
  for (final packet in trace.customPayloads)
    if (packet.channel == syncRailGraph)
      PacketBuffer.decode(packet.data!, (r) => TrackGraphSyncPacket.read(r)),
];

void main() {
  group(
    'a station on a rail graph reaches the client',
    skip: PumpkinLab.skipReason(),
    () {
      test('the graph the client is told carries the station', () async {
        final lab = await PumpkinLab.boot();
        addTearDown(lab.shutdown);
        final watcher = await lab.connect('Watcher');

        final stand = await lab.playerPosition('Watcher');
        await lab.server.command('forceload add -16 -16 16 16');
        await lab.server.settle(const Duration(seconds: 2));

        // The run: a straight 9-block track laid two blocks below the client's feet. The run is
        // placed through the item flow (`create tplace`: a fake player clicks a track item twice,
        // `TrackPlacement.tryConnect` lays the whole run), which is what a player placing a track
        // does - `/setblock create:track` writes the blocks but leaves no block entity behind.
        final trackY = stand.y - 2;
        final trackZ = stand.z - 4;
        // `create tplace` refuses a position in a chunk the server has not loaded yet (chunk
        // generation is asynchronous behind the join), so retry on its own reply like `placeBlock`.
        await lab.server.commandUntil(
          'create tplace ${stand.x} $trackY $trackZ ${stand.x} $trackY ${trackZ + 8} bulk',
          'TPROBE mode',
          retryWhile: RegExp('not loaded'),
        );
        print('trains before the station: ${(await lab.server.outputOf('create trains')).join(' | ')}');

        // The station block, aimed at the middle track of the run: a `TrackTargetingBehaviour`
        // stores the target as an offset from the block entity (`targetOffset`), so the target
        // track at (x, y, z+4) is `(-2, 0, 0)` from the station at (x+2, y, z+4). This is what the
        // station / signal / observer item writes on placement.
        final station = TracePos(stand.x + 2, trackY, trackZ + 4);
        await lab.server.placeBlock(station, 'create:track_station');
        print('merge: ${(await lab.server.outputOf(
          'data merge block ${station.x} ${station.y} ${station.z} '
          '{PluginData:{TargetTrack:[I;-2,0,0]}}',
        )).join(' | ')}');
        print('station data: ${(await lab.server.outputOf(
          'data get block ${station.x} ${station.y} ${station.z}',
        )).join(' | ')}');
        await lab.server.settle(const Duration(seconds: 2));

        final after = await lab.server.outputOf('create trains');
        final serverView = lab.server.readTrace();
        final early = watcher.readTrace();

        expect(
          serverView.drops,
          isEmpty,
          reason: 'the server dropped packets:\n${serverView.describe()}',
        );

        // The station the server itself has: `create trains` lists the graph's node count and its
        // station because the port now fills the nearest-graph list (`manager_registration.dart`
        // `summarize`). Retried on the command's own reply, because a single console window can be
        // attributed the previous command's lines.
        await lab.server.commandUntil(
          'create trains',
          RegExp('Stations'),
          timeout: const Duration(seconds: 30),
        );

        // A client that joins *after* the station exists: `playerLogin` sends it every graph
        // directly (`sendFullGraphTo` -> `RailwayNet.sendTo`).
        final later = await lab.connect('Later');
        await lab.server.settle(const Duration(seconds: 2));
        final late = later.readTrace();
        final lateGraphs = graphsIn(late);

        print('early channels: ${_channels(early).join(', ')}');
        print('late channels: ${_channels(late).join(', ')}');
        print('late graph payloads: ${lateGraphs.length}, stations: '
            '${lateGraphs.expand((g) => g.addedEdgePoints).whereType<GlobalStation>().length}');

        // 1. The client received the rail graph at all.
        expect(
          lateGraphs,
          isNotEmpty,
          reason:
              'the joining client was never sent a `$syncRailGraph` payload it could decode:\n'
              '${late.describe()}\n\n`create trains` after the station: ${after.join(' | ')}\n\n'
              'server tail:\n${lab.server.logLines}',
        );

        // 2. The graph the client decoded carries the station edge point, with the station
        //    resolved: its edge point type, and the block entity position it points at.
        final stations = [
          for (final graph in lateGraphs)
            ...graph.addedEdgePoints.whereType<GlobalStation>(),
        ];
        expect(
          stations,
          isNotEmpty,
          reason:
              'no station edge point made it into the graph the client decoded. '
              '`create trains` after the station: ${after.join(' | ')}',
        );
        expect(
          stations.first.blockEntityPos,
          isNotNull,
          reason: 'the station the client resolved has no block entity position',
        );
        expect(
          stations.first.getType().getId(),
          'create:station',
          reason: 'the station the client resolved has the wrong edge point type',
        );

        // 3. The client that was already connected when the station appeared. The server queues the
        //    tick sync and `RailwayNet.sendToAll` broadcasts it to `bus.roster.players`
        //    (`HostRailwayNetwork.sendToAll` -> `PayloadBus.sendClientboundAll`), so this client is
        //    told the station too, without rejoining. (It used to reach nobody: the roster held the
        //    `Player` the join event carried, which the host consumes when the event goes back to
        //    it, so `_send` failed on a dead handle and said so only at debug level.)
        final earlyGraphs = graphsIn(early);
        expect(
          earlyGraphs,
          isNotEmpty,
          reason:
              'the client that was already in the world was never told about the rail graph that '
              'grew under it (the tick sync broadcast to the roster):\n${early.describe()}\n\n'
              'server trace:\n${serverView.describe()}',
        );
        expect(
          [
            for (final graph in earlyGraphs)
              ...graph.addedEdgePoints.whereType<GlobalStation>(),
          ],
          isNotEmpty,
          reason: 'the broadcast graph carried no station edge point',
        );
      });
    },
  );
}

/// The payload channels of a trace, in order.
List<String> _channels(PumpkinTrace trace) => [
  for (final packet in trace.customPayloads) packet.channel ?? '?',
];