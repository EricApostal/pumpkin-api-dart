// Parity for a block entity's client data: two stacked fluid tanks are one multiblock, and a
// client has to be told the same merge by both servers.
//
// The merge is not a block state a server can be asked about and be done with: the lower tank
// becomes the controller (`Height`, `Size`) and the upper one a part that points at it
// (`Controller`), and that *is* the block entity's client data. So the rig is the smallest thing
// that has the shape — two `create:fluid_tank` blocks, placed in the air above the client — and
// what is compared is what each client was told: the block updates, the first block entity payload
// for each position, and its NBT leaf by leaf.
//
// The rig is static (a tank does not tick), which is what makes it a fair comparison of the
// *content*: nothing in it depends on how long the client stayed connected.
//
// Run it with (see example/create/README.md):
//
// ```sh
// PUMPKIN_E2E=1 PUMPKIN_BIN=<build>/pumpkin PUMPKIN_TESTER_BIN=<build>/pumpkin-tester \
//   puro dart test test/parity/fluid_tank_parity_test.dart
// ```

@Tags(['e2e'])
@Timeout(Duration(minutes: 30))
library;

import 'package:test/test.dart';

import '../support/differential/parity.dart';
import '../support/differential/scenarios.dart';

void main() {
  group('a merged fluid tank', () {
    test('the two servers tell their clients the same merge', () async {
      final report = await runParity(
        fluidTankScenario(),
        log: (message) => print('  $message'),
      );
      expectParity(report, what: 'the fluid tank rig');
    });
  }, skip: paritySkipReason());
}
