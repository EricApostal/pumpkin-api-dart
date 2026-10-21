// The contract a parity test is written against: run one rig on both servers, then assert the two
// clients were told the same thing.
//
// A parity test is not a unit test with a second server bolted on: what it compares is a *semantic*
// record of two independent runs (see `trace_diff.dart`), so the only things a test file has to say
// are (a) which rig, and (b) that it must agree. Everything else — the two arms, the ports, the
// client, the wire capture, the normalisation — is [runParity]'s job.
//
// Three outcomes are kept apart on purpose, because collapsing them is how a suite stops meaning
// anything:
//
//  * **agreement** (exit 0) — the test passes;
//  * **a difference** (exit 1) — the test fails and the message names the first differing event,
//    with both servers' own packets around it;
//  * **the run never got to compare** (exit 2) — a broken environment (no binary, an arm that never
//    started, a scenario that produced nothing on the reference arm). This is a *failure*, never a
//    skip and never a pass: "both traces were empty" must not read as agreement.
//
// The suite is off unless `PUMPKIN_E2E=1`, like the rest of the server-booting tests, and it needs
// a Java install for the reference arm (`MCTRACE_JAVA_DIR`). `PARITY_REFERENCE`/`PARITY_CANDIDATE`
// override the two arms, which is how the comparison itself is checked (`pumpkin` against
// `pumpkin` must agree).

import 'dart:io';

import 'package:test/test.dart';

import '../pumpkin_lab.dart';
import 'channel_manifest.dart';
import 'differential_run.dart';
import 'scenario.dart';

/// The arms a parity run compares, read from the environment.
///
/// The default is the reference against the thing under test: the Java mod (presumed right) against
/// the plugin. Setting both to the same server is a legitimate run — it proves the comparison has no
/// false positives — so it is allowed and only noted in the report.
({ArmKind reference, ArmKind candidate}) parityArms() {
  ArmKind read(String name, ArmKind fallback) {
    final value = Platform.environment[name];
    if (value == null || value.isEmpty) return fallback;
    final kind = ArmKind.of(value);
    if (kind == null) {
      throw StateError('$name=$value is not a server (java, pumpkin)');
    }
    return kind;
  }

  return (
    reference: read('PARITY_REFERENCE', ArmKind.java),
    candidate: read('PARITY_CANDIDATE', ArmKind.pumpkin),
  );
}

/// Why a parity test cannot run here, or null when it can.
///
/// [requireJava] is for the tests whose whole point is the Java reference; [requireProxy] is for the
/// ones that read the handshake off the wire, which only the recording proxy can see.
String? paritySkipReason({
  bool requireJava = true,
  bool requireProxy = false,
}) {
  final reason = PumpkinLab.skipReason();
  if (reason != null) return reason;
  final environment = DifferentialEnvironment.resolve();
  if (requireJava) {
    final unavailable = environment.javaUnavailable();
    if (unavailable != null) return unavailable;
  }
  if (requireProxy && environment.mctraceBinary == null) {
    return 'the parity test reads the handshake off the wire, which needs `mctrace`: set MCTRACE_BIN';
  }
  return null;
}

/// Runs [scenario] on both arms and returns the comparison.
///
/// [artifacts] keeps each arm's client trace, wire capture and console log in a directory of its
/// own — the evidence a failure is read from — and [log] prints progress, because a differential is
/// minutes of work and a silent one cannot be told from a hung one.
Future<DifferentialReport> runParity(
  Scenario scenario, {
  Directory? artifacts,
  File? clientQuery,
  bool compareTraces = true,
  ArmKind? reference,
  ArmKind? candidate,
  Duration settleAfter = const Duration(seconds: 4),
  Duration joinTimeout = const Duration(seconds: 120),
  void Function(String message)? log,
}) {
  final defaults = parityArms();
  final arms = (
    reference: reference ?? defaults.reference,
    candidate: candidate ?? defaults.candidate,
  );
  // Both clients join as the *same* client: a Create client, answering the `NeoForge` handshake
  // with Create's own channel set. Without that the two arms would not be comparable — a Java
  // server refuses a client that cannot answer, so its arm is a `NeoForge` client by construction,
  // while a plain bot on the plugin arm is a vanilla one, and the two flavours are told different
  // things (a `NeoForge` client is sent `neoforge:auxiliary_light_data` with every chunk, a vanilla
  // one is not). That difference is the harness's, not the mod's, and it would be reported as if it
  // were the plugin's.
  final query =
      clientQuery ??
      createChannelQuery(Directory.systemTemp.createTempSync('parity-query-'));
  return DifferentialRunner(
    environment: DifferentialEnvironment.resolve(),
    scenario: scenario,
    reference: arms.reference,
    candidate: arms.candidate,
    artifacts: artifacts,
    clientQuery: query,
    compareTraces: compareTraces,
    settleAfter: settleAfter,
    joinTimeout: joinTimeout,
    log: log,
  ).run();
}

/// Asserts that [report] is an agreement, and fails with the reason it is not.
///
/// A test whose comparison never ran is failed here rather than passed: an empty trace, an arm that
/// never joined and a missing binary are all reported as what they are, with the report attached.
void expectParity(DifferentialReport report, {String? what}) {
  final subject = what ?? 'the `${report.scenario.name}` rig';
  final failure = report.failure;
  if (failure != null) {
    fail(
      '$subject never got to compare (exit 2 — a harness problem, not a difference): $failure\n'
      '${report.render(all: true)}',
    );
  }
  final differential = report.differential;
  if (differential == null) {
    fail(
      '$subject produced no comparison (exit 2)\n${report.render(all: true)}',
    );
  }
  expect(
    differential.agrees,
    isTrue,
    reason:
        '$subject: ${report.reference.kind.description} and '
        '${report.candidate.kind.description} told their clients different things — '
        '${differential.divergences.length} difference(s), the first is '
        '`${differential.first?.describe()}`\n${report.render(all: true)}',
  );
}
