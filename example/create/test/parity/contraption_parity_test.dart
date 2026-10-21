// Parity for the contraption rig the user's own replay uses: a bearing driven by a creative motor
// assembling one stone.
//
// This is the rig the differential was built for, and it is the one that tells the whole story at
// once — a block update, a block entity's payload, the contraption entity and the spawn data that
// has to travel in the same bundle. A client that is told a different block-state history, a
// different block entity payload or a differently shaped spawn payload draws a different machine.
//
// The rig is tick-driven (a bearing assembles on a later tick than the one that changed its speed),
// so the runner settles both arms for the same time before it stops the clients; the comparison is
// over the first push of each block entity, because a running machine re-pushes its payload every
// tick with an angle in it.
//
// Run it with (see example/create/README.md):
//
// ```sh
// PUMPKIN_E2E=1 PUMPKIN_BIN=<build>/pumpkin PUMPKIN_TESTER_BIN=<build>/pumpkin-tester \
//   puro dart test test/parity/contraption_parity_test.dart
// ```

@Tags(['e2e'])
@Timeout(Duration(minutes: 30))
library;

import 'package:test/test.dart';

import '../support/differential/parity.dart';
import '../support/differential/scenarios.dart';

void main() {
  group('a contraption', () {
    test('a bearing and its payload reach the client the same way on both servers', () async {
      final report = await runParity(
        contraptionScenario(),
        log: (message) => print('  $message'),
      );
      expectParity(report, what: 'the contraption rig');
    });
  }, skip: paritySkipReason());
}
