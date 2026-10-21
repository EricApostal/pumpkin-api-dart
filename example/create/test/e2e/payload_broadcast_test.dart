// A payload broadcast reaches a client that is already connected.
//
// `PayloadBus.sendClientboundAll` sends one payload to a list of players - the players the
// `PlayerRoster` holds - and every fleet-wide send goes through it: chain conveyors, contraption
// packets, decoration, armour and the rail graph (`create:sync_rail_graph`). A roster that holds a
// handle the host has already taken back delivers *nothing*, and the only trace of that was a
// `debug` line, so the client silently never learned about the content while the server had it.
//
// This test asks the client, through its own packet trace, whether a broadcast arrived. The vehicle
// is `create:server_speed`, which the infrastructure module broadcasts to `bus.roster.players`
// every second (`lib/src/infrastructure/infrastructure_module.dart`, `ServerSpeedProvider.serverTick`,
// default `infrastructure.tickrateSyncTimer` of 20 ticks): a connected client that is in the roster
// receives it while it stands still, with no scenario to place.
//
// Run it with (see example/create/README.md):
//
// ```sh
// PUMPKIN_E2E=1 PUMPKIN_BIN=<build>/pumpkin PUMPKIN_TESTER_BIN=<build>/pumpkin-tester \
//   puro dart test test/e2e/payload_broadcast_test.dart
// ```

@Tags(['e2e'])
@Timeout(Duration(minutes: 20))
library;

import 'package:test/test.dart';

import '../support/pumpkin_lab.dart';
import '../support/pumpkin_trace.dart';

/// The channel the infrastructure module broadcasts every `tickrateSyncTimer` ticks.
const String serverSpeed = 'create:server_speed';

void main() {
  group(
    'a connected client is sent a broadcast payload',
    skip: PumpkinLab.skipReason(),
    () {
      test('the payload of a `sendClientboundAll` reaches it', () async {
        final lab = await PumpkinLab.boot();
        addTearDown(lab.shutdown);
        final watcher = await lab.connect('Watcher');

        // The broadcast is periodic, so the client does not have to do anything: wait until it
        // arrives, or fail with the trace of what it did receive.
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        var received = <TracedPacket>[];
        while (DateTime.now().isBefore(deadline)) {
          received = [
            for (final packet in watcher.readTrace().customPayloads)
              if (packet.channel == serverSpeed) packet,
          ];
          if (received.isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }

        final trace = watcher.readTrace();
        final serverTrace = lab.server.readTrace();
        final serverView = serverTrace.forClient(serverTrace.clients.single);

        // What the *client* received is the assertion; the server's own trace says whether the
        // payload was enqueued at all, so "the plugin sent nothing" and "it was sent but the
        // client never got it" stay distinguishable in the failure message.
        expect(
          received,
          isNotEmpty,
          reason:
              'the client received no $serverSpeed payload it was broadcast, while the server '
              'enqueued ${serverView.customPayloads.where((p) => p.channel == serverSpeed).length} '
              'of them:\n${trace.describe()}\n\nchannels the client did receive: '
              '${[for (final p in trace.customPayloads) p.channel].join(', ')}\n\n'
              'server tail:\n${_tail(lab.server.logLines)}',
        );
        expect(
          serverView.customPayloads.where((p) => p.channel == serverSpeed),
          isNotEmpty,
          reason: 'the server never enqueued a $serverSpeed payload for the client',
        );

        print('$serverSpeed payloads the client received: ${received.length}');
        print('first: ${received.first.describe()}');
      });
    },
  );
}

String _tail(List<String> lines, [int count = 30]) =>
    (lines.length > count ? lines.sublist(lines.length - count) : lines).join('\n');