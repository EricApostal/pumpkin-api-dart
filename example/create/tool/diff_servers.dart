// Runs one scenario against both servers, records both, and reports the first semantic difference.
//
//   puro dart run tool/diff_servers.dart                       # Java reference vs Pumpkin
//   puro dart run tool/diff_servers.dart --scenario fluid_tank
//   puro dart run tool/diff_servers.dart --candidate pumpkin --reference pumpkin
//   puro dart run tool/diff_servers.dart --out /tmp/differential --json /tmp/differential.json
//
// One command, no human: the Java arm is a NeoForge dedicated server built from the jars of an
// existing install (`MCTRACE_JAVA_DIR`, default `~/Documents/mctesting`) in a scratch directory of
// its own, the Pumpkin arm is the plugin under `PUMPKIN_PLUGIN_WASM`, both are driven over their
// console with the same commands, and a `pumpkin-tester client` joins each through a recording
// `mctrace` proxy. What the two clients were told is then compared by `trace_diff.dart`.
//
// Exit codes are the automation contract: 0 the two arms agree, 1 they differ (the report names the
// first difference), 2 the run never got to compare (an arm failed to start or to join) — and 2 is
// never a difference, so a broken environment cannot masquerade as a finding.
//
// The rigs are Create's, and they live in `test/support/differential/scenarios.dart` so that the
// `test/parity/` suite runs exactly the same ones. The machinery underneath
// (`test/support/differential/`) knows nothing about Create, so the same tool compares any two
// servers for any plugin.

import 'dart:convert';
import 'dart:io';

import '../test/support/differential/channel_manifest.dart';
import '../test/support/differential/differential_run.dart';
import '../test/support/differential/scenario.dart';
import '../test/support/differential/scenarios.dart';

const String usage = '''
usage: dart run tool/diff_servers.dart [options]

  --scenario NAME     the rig to run (contraption, fluid_tank; default contraption)
  --reference KIND    the server that is presumed right (java, pumpkin; default java)
  --candidate KIND    the server under test (default pumpkin)
  --bot NAME          the name the simulated client joins with (default Watcher)
  --java-dir DIR      the NeoForge install to mirror (default \$MCTRACE_JAVA_DIR or
                      ~/Documents/mctesting)
  --out DIR           copy each arm's client trace, wire capture and console log there
  --json FILE         write the machine-readable result (divergences, exit reason) there
  --query FILE        the channels both clients answer the `NeoForge` handshake with (default: the
                      channels this plugin declares, so both arms get the same Create client)
  --keep              keep each arm's scratch directory (world, plugin configs, logs)
  --all               print every difference, not just the first
  --settle MS         how long to let the servers tick after the scenario (default 4000)
  --join TIMEOUT_S    how long a client may take to join (default 120)

environment: PUMPKIN_BIN, PUMPKIN_TESTER_BIN, PUMPKIN_PLUGIN_WASM, MCTRACE_BIN, MCTRACE_JAVA_DIR
''';

Future<int> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options == null) {
    stderr.writeln(usage);
    return 2;
  }
  final scenarioFactory = parityScenarios[options.scenario];
  if (scenarioFactory == null) {
    stderr.writeln(
      'no scenario `${options.scenario}`; known: ${parityScenarios.keys.join(', ')}',
    );
    stderr.writeln(usage);
    return 2;
  }
  final Scenario scenario = scenarioFactory();
  final environment = DifferentialEnvironment.resolve(
    javaInstall: options.javaDir,
  );
  // Both clients answer the handshake with the same set, which is what makes the two arms
  // comparable: a vanilla client on one arm is told less than a `NeoForge` one by construction
  // (the host sends `neoforge:auxiliary_light_data` only to a `NeoForge` client), and the
  // comparison would report the harness's choice as if it were the plugin's.
  final clientQuery =
      options.query ??
      createChannelQuery(
        Directory.systemTemp.createTempSync('differential-query-'),
      );
  final runner = DifferentialRunner(
    environment: environment,
    scenario: scenario,
    reference: options.reference,
    candidate: options.candidate,
    botName: options.bot,
    keep: options.keep,
    settleAfter: options.settle,
    joinTimeout: options.joinTimeout,
    artifacts: options.out,
    clientQuery: clientQuery,
    log: (message) => stdout.writeln('  $message'),
  );
  stdout.writeln(
    'differential: ${scenario.name} — ${options.reference.description} (reference) vs '
    '${options.candidate.description} (candidate)',
  );
  stdout.writeln(
    '  pumpkin=${environment.paths.serverBinary ?? '<unset>'} '
    'plugin=${environment.paths.pluginComponent} '
    'tester=${environment.paths.testerBinary ?? '<unset>'} '
    'mctrace=${environment.mctraceBinary ?? '<unset>'} '
    'java=${environment.javaInstall?.path ?? '<none>'}',
  );
  final report = await runner.run();
  stdout.writeln(report.render(all: options.all));
  final json = options.json;
  if (json != null) {
    json.parent.createSync(recursive: true);
    json.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
    );
    stdout.writeln('result written to ${json.path}');
  }
  return report.exitCode;
}

/// The command line, parsed once.
final class _Options {
  _Options({
    required this.scenario,
    required this.reference,
    required this.candidate,
    required this.bot,
    required this.javaDir,
    required this.out,
    required this.json,
    required this.query,
    required this.keep,
    required this.all,
    required this.settle,
    required this.joinTimeout,
  });

  final String scenario;
  final ArmKind reference;
  final ArmKind candidate;
  final String bot;
  final String? javaDir;
  final Directory? out;
  final File? json;
  final File? query;
  final bool keep;
  final bool all;
  final Duration settle;
  final Duration joinTimeout;

  static _Options? parse(List<String> arguments) {
    var scenario = 'contraption';
    var reference = ArmKind.java;
    var candidate = ArmKind.pumpkin;
    var bot = 'Watcher';
    String? javaDir;
    Directory? out;
    File? json;
    File? query;
    var keep = false;
    var all = false;
    var settle = const Duration(seconds: 4);
    var join = const Duration(seconds: 120);
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      String? value() => i + 1 < arguments.length ? arguments[++i] : null;
      switch (argument) {
        case '--scenario':
          final next = value();
          if (next == null) return null;
          scenario = next;
        case '--reference':
        case '--candidate':
          final next = value();
          if (next == null) return null;
          final kind = ArmKind.of(next);
          if (kind == null) {
            stderr.writeln('unknown server `$next` (java, pumpkin)');
            return null;
          }
          if (argument == '--reference') {
            reference = kind;
          } else {
            candidate = kind;
          }
        case '--bot':
          final next = value();
          if (next == null) return null;
          bot = next;
        case '--java-dir':
          javaDir = value();
          if (javaDir == null) return null;
        case '--out':
          final next = value();
          if (next == null) return null;
          out = Directory(next);
        case '--json':
          final next = value();
          if (next == null) return null;
          json = File(next);
        case '--query':
          final next = value();
          if (next == null) return null;
          query = File(next);
        case '--keep':
          keep = true;
        case '--all':
          all = true;
        case '--settle':
          final next = int.tryParse(value() ?? '');
          if (next == null) return null;
          settle = Duration(milliseconds: next);
        case '--join':
          final next = int.tryParse(value() ?? '');
          if (next == null) return null;
          join = Duration(seconds: next);
        case '--help':
        case '-h':
          return null;
        default:
          stderr.writeln('unknown option `$argument`');
          return null;
      }
    }
    if (reference == candidate) {
      // Two identical arms are how the tooling itself is checked (it proves the comparison has no
      // false positives), so it is allowed — but a *difference* between them would mean the
      // scenario is not deterministic, which is worth saying out loud.
      stderr.writeln(
        'note: both arms are ${reference.id}; this checks the comparison, not a server difference',
      );
    }
    return _Options(
      scenario: scenario,
      reference: reference,
      candidate: candidate,
      bot: bot,
      javaDir: javaDir,
      out: out,
      json: json,
      query: query,
      keep: keep,
      all: all,
      settle: settle,
      joinTimeout: join,
    );
  }
}
