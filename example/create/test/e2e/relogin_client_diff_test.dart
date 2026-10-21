// The highest-value shape in this suite: **it only shows up after a relogin**.
//
// A player sees something in game; if it is right after reconnecting and wrong before, then the
// server never pushed it when it changed, and the relogin's chunk (which carries the world, and the
// plugin block entities of each chunk, inline) is the first time that client hears about it. From
// the server's side this is invisible: the world is correct, the command succeeded, nothing errored.
// The only way to see it is to compare what two clients were *told*.
//
// So: one simulated client is present while the state changes, then disconnects; a second one joins
// the same world — a relogin — and spawns where the first one did, so it loads the same chunks.
// Their traces are diffed over the scenario's positions, which is what `focus` is for: a live world
// produces unrelated traffic between the two sessions (an ambient mob that spawned in between is an
// `add_entity` the relogin saw and the first client never did, and that is nobody's defect).
//
// The ordering half of the same defect is asserted too: a block-entity payload that reaches a client
// before the block update that creates the block entity is dropped by the client itself
// (`ClientPacketListener.handleBlockEntityData`), which leaves the block entity empty until a
// relogin. `payloadFollowsState` reads exactly that out of the trace.
//
// Run it with (see example/create/README.md):
//
// ```sh
// PUMPKIN_E2E=1 PUMPKIN_BIN=<build>/pumpkin PUMPKIN_TESTER_BIN=<build>/pumpkin-tester \
//   puro dart test test/e2e/relogin_client_diff_test.dart
// ```

@Tags(['e2e'])
@Timeout(Duration(minutes: 20))
library;

import 'package:test/test.dart';

import '../support/pumpkin_lab.dart';
import '../support/pumpkin_trace.dart';

void main() {
  group(
    'a relogin is not told state the client that was there never was',
    skip: PumpkinLab.skipReason(),
    () {
      test('two tanks merge while a client watches', () async {
        final lab = await PumpkinLab.boot();
        addTearDown(lab.shutdown);

        // The client that is there when the state changes.
        final present = await lab.connect('Present');
        final stand = await lab.playerPosition('Present');
        final lower = TracePos(stand.x, stand.y - 3, stand.z);
        final upper = TracePos(stand.x, stand.y - 2, stand.z);

        // The scenario's chunk has to be loaded before it can be written to; a client standing in
        // it is not enough, because a chunk is generated asynchronously behind the join.
        await lab.server.command('forceload add -16 -16 16 16');
        await lab.server.settle(const Duration(seconds: 2));
        await lab.server.placeBlock(lower, 'create:fluid_tank');
        await lab.server.placeBlock(upper, 'create:fluid_tank');
        await lab.server.sync();
        final presentTrace = present.readTrace();

        // A run where the present client was told nothing at all would prove nothing, whatever the
        // relogin's trace says.
        expect(
          presentTrace.blockEntityAt(lower),
          isNotNull,
          reason:
              'the client that was present was never sent a tank payload, so this run cannot '
              'distinguish "the push is missing" from "nothing happened":\n'
              '${presentTrace.describe()}\n\nserver tail:\n${_tail(lab.server.logLines)}',
        );

        // The relogin: the first client goes away, a second one joins the same world.
        await present.stop();
        final relogin = await lab.connect('Relogin');
        await lab.server.settle(const Duration(seconds: 3));
        final reloginTrace = relogin.readTrace();

        // Both clients stand at the world spawn, so the relogin loads the column the tanks are in —
        // that is what makes its chunk the source of the state the present client had to be pushed.
        final reloginStand = await lab.playerPosition('Relogin');
        expect(
          TracePos(reloginStand.x >> 4, 0, reloginStand.z >> 4),
          TracePos(stand.x >> 4, 0, stand.z >> 4),
          reason:
              'the relogin spawned in a different chunk column than the client that was there, so '
              'this run cannot compare what the two were told',
        );

        final diff = VisibilityDiff.between(
          ClientVisibility.of(presentTrace),
          ClientVisibility.of(reloginTrace),
          focus: {lower, upper},
        );

        // Anything the relogin learned that the client who was *there* never did is state the
        // server failed to send when it changed.
        expect(
          diff.lateIsNoWiser,
          isTrue,
          reason:
              'the relogin was told state the present client never was, which is what "it only '
              'shows up after a relogin" looks like from the wire:\n${diff.describe()}\n\n'
              'present client:\n${presentTrace.describe()}\n\n'
              'relogin:\n${reloginTrace.describe()}',
        );

        // And the client that was there must have been able to *use* what it was sent: the block
        // entity payload cannot precede the block update that creates it.
        for (final (name, pos) in [('lower', lower), ('upper', upper)]) {
          expect(
            presentTrace.payloadFollowsState(pos),
            isTrue,
            reason:
                'the client was sent the $name tank payload at $pos before it was told the block '
                'itself, so its own `handleBlockEntityData` drops it and the tank stays empty '
                'until a relogin:\n${presentTrace.describe()}',
          );
          expect(
            reloginTrace.payloadFollowsState(pos),
            isTrue,
            reason:
                'the relogin was sent the $name tank payload at $pos before it was told the '
                'block:\n${reloginTrace.describe()}',
          );
        }
      });
    },
  );
}

String _tail(List<String> lines, [int count = 30]) =>
    (lines.length > count ? lines.sublist(lines.length - count) : lines).join('\n');