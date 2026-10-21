// What a client is told about a fluid tank that merged with its neighbour.
//
// Two vertically stacked `create:fluid_tank` blocks are one multiblock: the lower one becomes the
// controller (with a `Size`/`Height`) and the upper one a part pointing at it (with a `Controller`);
// their `bottom`/`top` states are rewritten so the client draws one tank
// (`lib/src/fluids/fluid_tank.dart:126`, `lib/src/manifest/blocks.g.dart`: default state
// `bottom=true, top=true`).
//
// Server-side that can be perfect and the game still show two lone tanks, because what the client
// renders is what the server pushed. This test asks the *client*, through its own packet trace:
// it must have been told a block-entity payload for both positions, that payload must decode to the
// merged shape, and it must have been told the rewritten state.
//
// The scenario runs where the client is (see `PumpkinLab.playerPosition`): the server only sends
// block updates to players tracking the chunk, so blocks placed out of the client's view produce no
// packets at all — and a console `tp` does not change that, it never sends the destination's chunk.
//
// Run it with (see example/create/README.md):
//
// ```sh
// PUMPKIN_E2E=1 PUMPKIN_BIN=<build>/pumpkin PUMPKIN_TESTER_BIN=<build>/pumpkin-tester \
//   puro dart test test/e2e/tank_client_payload_test.dart
// ```

@Tags(['e2e'])
@Timeout(Duration(minutes: 20))
library;

import 'package:test/test.dart';

import '../support/pumpkin_lab.dart';
import '../support/pumpkin_trace.dart';

void main() {
  group(
    'a client is told the tank that merged',
    skip: PumpkinLab.skipReason(),
    () {
      test('two stacked tanks', () async {
        final lab = await PumpkinLab.boot();
        addTearDown(lab.shutdown);
        final watcher = await lab.connect('Watcher');

        // Under the client's feet: same chunk column, so every block update and block entity of the
        // scenario is something this client is sent.
        final stand = await lab.playerPosition('Watcher');
        final lower = TracePos(stand.x, stand.y - 3, stand.z);
        final upper = TracePos(stand.x, stand.y - 2, stand.z);

        // The scenario's chunk has to be loaded before it can be written to; a client standing in
        // it is not enough, because a chunk is generated asynchronously behind the join.
        await lab.server.command('forceload add -16 -16 16 16');
        await lab.server.settle(const Duration(seconds: 2));
        await lab.server.placeBlock(lower, 'create:fluid_tank');
        await lab.server.placeBlock(upper, 'create:fluid_tank');
        await lab.server.sync();

        final trace = watcher.readTrace();
        final serverTrace = lab.server.readTrace();
        final serverView = serverTrace.forClient(serverTrace.clients.single);

        // A packet the connection never took would look exactly like "the plugin sent nothing", so
        // rule that out first.
        expect(
          serverTrace.drops,
          isEmpty,
          reason: 'the server dropped packets:\n${serverTrace.describe()}',
        );

        // 1. The payload that carries the merge reached the client, for both parts.
        for (final (name, pos) in [('lower', lower), ('upper', upper)]) {
          final payload = trace.blockEntityAt(pos);
          expect(
            payload,
            isNotNull,
            reason:
                'the client was never sent the block-entity payload of the $name tank at $pos:\n'
                '${trace.describe()}\n\nserver tail:\n${_tail(lab.server.logLines)}',
          );
          expect(
            payload!.nbt,
            isNotNull,
            reason:
                'the $name payload did not decode as the network NBT a client reads:\n'
                '${payload.describe()}',
          );
        }

        // 2. ... and it says what the plugin meant: the lower tank is the controller of a 2-tall
        // tank, the upper one points at it.
        final lowerNbt = trace.blockEntityAt(lower)!.nbt!;
        expect(
          lowerNbt['Height']?.value,
          2,
          reason: 'the controller the client was told is not 2 tall: $lowerNbt',
        );
        expect(
          lowerNbt['Size']?.value,
          1,
          reason: 'the controller the client was told is not 1 wide: $lowerNbt',
        );
        expect(
          lowerNbt.containsKey('Controller'),
          isFalse,
          reason: 'the controller was sent a `Controller` pointing at itself: $lowerNbt',
        );

        final upperNbt = trace.blockEntityAt(upper)!.nbt!;
        expect(
          upperNbt['Controller']?.value,
          [lower.x, lower.y, lower.z],
          reason: 'the upper tank was not told that the lower one controls it: $upperNbt',
        );

        // 3. The client was told the block itself, and what it renders last is what the server sent
        // last. A block whose state never reached the client stays whatever it was; the merge's own
        // rewrite of the parts' `bottom`/`top` flags (`lib/src/fluids/fluid_tank.dart:147`,
        // `notifyMultiUpdated`) would show up here as a second, different state.
        for (final (name, pos) in [('lower', lower), ('upper', upper)]) {
          final states = trace.statesFor(pos);
          expect(
            states,
            isNotEmpty,
            reason: 'the client was never told a state for the $name tank at $pos',
          );
          expect(
            serverView.stateAt(pos),
            states.last,
            reason:
                'the client\'s last state for the $name tank at $pos is not the last one the '
                'server sent it ($states against ${serverView.stateAt(pos)})',
          );
        }
      });
    },
  );
}

String _tail(List<String> lines, [int count = 30]) =>
    (lines.length > count ? lines.sublist(lines.length - count) : lines).join('\n');