// The suite's proof that it can fail.
//
// A parity test that has only ever run against two working servers has not been shown to catch
// anything. This file takes one *real* run of a real rig, asserts the two arms agree, and then
// deletes one event from one arm's trace: "the server never pushed this block entity's payload" is
// the regression class the suite exists for, and the comparison has to report it, by name.
//
// It runs two Pumpkin arms on purpose: what is under test here is the comparison, not a server, and
// two identical arms are the cheapest honest way to get a real trace pair (the same check the CLI
// documents for `--reference pumpkin --candidate pumpkin`). The live Java-against-Pumpkin parity is
// in the subsystem tests next to it.
//
// Run it with (see example/create/README.md):
//
// ```sh
// PUMPKIN_E2E=1 PUMPKIN_BIN=<build>/pumpkin PUMPKIN_TESTER_BIN=<build>/pumpkin-tester \
//   puro dart test test/parity/negative_control_test.dart
// ```

@Tags(['e2e'])
@Timeout(Duration(minutes: 30))
library;

import 'package:test/test.dart';

import '../support/differential/differential_run.dart';
import '../support/differential/parity.dart';
import '../support/differential/scenarios.dart';
import '../support/differential/trace_diff.dart';

void main() {
  group('the parity comparison', () {
    test('reports a candidate that never pushed a block entity payload', () async {
      final scenario = fluidTankScenario();
      final report = await runParity(
        scenario,
        reference: ArmKind.pumpkin,
        candidate: ArmKind.pumpkin,
        log: (message) => print('  $message'),
      );
      // The run itself is a clean agreement, so what follows is about the mutation and not about
      // a difference that was already there.
      expectParity(report, what: 'the negative control run');

      final reference = report.reference.normalised(scenario)!;
      final candidate = report.candidate.normalised(scenario)!;
      expect(
        candidate.events.where((event) => event.kind == 'block_entity_data'),
        isNotEmpty,
        reason:
            'the rig has to produce a block entity payload for the control to remove one:\n'
            '${candidate.summary}',
      );

      // The regression: the same run, minus every block entity payload.
      final regressed = candidate.without(
        (event) => event.kind == 'block_entity_data',
      );
      final comparison = Differential.compare(reference, regressed);
      expect(
        comparison.agrees,
        isFalse,
        reason:
            'removing a block entity payload from one arm must be a difference, or the suite '
            'would pass a server that never tells a client what it placed:\n'
            '${comparison.report(all: true)}',
      );
      expect(
        comparison.first!.subject,
        contains('block_entity_data'),
        reason:
            'the difference has to name the event that went missing:\n'
            '${comparison.report(all: true)}',
      );
      expect(
        comparison.first!.describe(),
        contains('nothing'),
        reason:
            'the difference has to say one side sent nothing there:\n'
            '${comparison.report(all: true)}',
      );

      // …and the assertion every parity test ends in has to fail on it. A comparison object that
      // notices a difference is only worth anything if `expectParity` turns it into a failed test,
      // so the proof is carried all the way to the helper the suite is written against.
      final mutated = DifferentialReport(
        scenario: scenario,
        reference: report.reference,
        candidate: report.candidate,
        differential: comparison,
        proxyCheck: null,
        notes: const [],
        failure: null,
        environment: report.environment,
        traceCompared: true,
      );
      expect(
        () => expectParity(mutated, what: 'the mutated control'),
        throwsA(isA<TestFailure>()),
        reason:
            'a parity test built on this comparison must fail, or the suite would pass a server '
            'that never tells a client what it placed:\n'
            '${comparison.report(all: true)}',
      );
    });
  }, skip: paritySkipReason(requireJava: false));
}