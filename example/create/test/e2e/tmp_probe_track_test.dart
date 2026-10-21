@Tags(['e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'package:create/src/trains/graph/track_graph_sync_packet.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

import '../support/pumpkin_lab.dart';
import '../support/pumpkin_trace.dart';

void main() {
  test('probe', () async {
    final lab = await PumpkinLab.boot();
    addTearDown(lab.shutdown);
    final watcher = await lab.connect('Watcher');
    final stand = await lab.playerPosition('Watcher');
    print('stand=$stand');
    await lab.server.command('forceload add -16 -16 16 16');
    await lab.server.settle(const Duration(seconds: 2));

    final y = stand.y - 2;
    final z = stand.z - 4;
    for (var i = 0; i < 9; i++) {
      await lab.server.placeBlock(TracePos(stand.x, y, z + i), 'create:track');
    }
    await lab.server.settle(const Duration(seconds: 2));

    print('trains: ${(await lab.server.outputOf('create trains')).join(' | ')}');
    print('blockentity: ${(await lab.server.outputOf('data get block ${stand.x} $y ${z + 4}')).join(' | ')}');

    final trace = watcher.readTrace();
    print('channels: ${[for (final p in trace.customPayloads) p.channel].join(', ')}');
    final graphs = [
      for (final p in trace.customPayloads)
        if (p.channel == 'create:sync_rail_graph')
          PacketBuffer.decode(p.data!, (r) => TrackGraphSyncPacket.read(r)),
    ];
    for (final g in graphs) {
      print('graph ${g.graphId} nodes=${g.addedNodes.length} edges=${g.addedEdges.length} '
          'points=${g.addedEdgePoints.length} wipe=${g.fullWipe}');
      for (final e in g.addedNodes.entries) {
        print('  node ${e.key} ${e.value.getFirst()}');
      }
      for (final e in g.addedEdges) {
        print('  edge ${e.getFirst().getFirst()}');
      }
    }
  });
}
