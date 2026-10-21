// Runs one scenario against both servers, records both, and reports the first semantic difference.
//
//   puro dart run tool/diff_servers.dart                       # Java reference vs Pumpkin
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
// The scenario below is Create's: it is the contraption rig the user's own replay uses. The
// machinery underneath (`test/support/differential/`) knows nothing about Create, so the same tool
// compares any two servers for any plugin.

import 'dart:convert';
import 'dart:io';

import '../test/support/differential/differential_run.dart';
import '../test/support/differential/game_server.dart';
import '../test/support/differential/scenario.dart';
import '../test/support/differential/trace_diff.dart';
import '../test/support/pumpkin_trace.dart';

const String usage = '''
usage: dart run tool/diff_servers.dart [options]

  --scenario NAME     the rig to run (default: contraption)
  --reference KIND    the server that is presumed right (java, pumpkin; default java)
  --candidate KIND    the server under test (default pumpkin)
  --bot NAME          the name the simulated client joins with (default Watcher)
  --java-dir DIR      the NeoForge install to mirror (default \$MCTRACE_JAVA_DIR or
                      ~/Documents/mctesting)
  --out DIR           copy each arm's client trace, wire capture and console log there
  --json FILE         write the machine-readable result (divergences, exit reason) there
  --keep              keep each arm's scratch directory (world, plugin configs, logs)
  --all               print every difference, not just the first
  --settle MS         how long to let the servers tick after the scenario (default 4000)
  --join TIMEOUT_S    how long a client may take to join (default 120)

environment: PUMPKIN_BIN, PUMPKIN_TESTER_BIN, PUMPKIN_PLUGIN_WASM, MCTRACE_BIN, MCTRACE_JAVA_DIR
''';

/// The rig: a bearing driven by a creative motor, carrying one stone.
///
/// This is the shape of the user's replay, and it is built out of the console alone (no player has
/// to place anything):
///
///  * a `create:creative_motor` is the rotation source; it drives the block in front of it, so the
///    layout along z is structure (the contraption's content), bearing, motor;
///  * a bearing assembles the block in front of it on a later tick than the one that starts it
///    turning, which is why the motor is placed last and the run then settles;
///  * the rig is built in the air directly above the client, because a server only tells a client
///    about what it tracks: a rig anywhere else produces no packets at all, and the two servers put
///    the world spawn at different heights, so the only position that means the same thing on both
///    is "where this server says the client is".
///
/// The one stone is deliberate: the bearing's search starts at the block in front of it and captures
/// that block without glue, so a plain stone floor (which the two worldgen implementations disagree
/// about) is never captured and the payload stays one block — a difference in the payload is then
/// about the plugin, not about the world.
Scenario contraptionScenario() => Scenario(
  name: 'contraption',
  description:
      'a mechanical bearing driven by a creative motor assembles one stone into a contraption',
  box: const RigBox(
    xMin: -1,
    xMax: 1,
    yMin: -2,
    yMax: 2,
    zMin: -2,
    zMax: 4,
  ),
  anchorOf: (player) => TracePos(player.x, player.y + 5, player.z),
  build: (anchor) {
    final bearing = TracePos(anchor.x, anchor.y, anchor.z + 1);
    final motor = TracePos(anchor.x, anchor.y, anchor.z + 2);
    return [
      // The contraption's content first, so the bearing has something to capture.
      ScenarioStep('setblock ${anchor.x} ${anchor.y} ${anchor.z} minecraft:stone'),
      ScenarioStep(
        'setblock ${bearing.x} ${bearing.y} ${bearing.z} '
        'create:mechanical_bearing[facing=north]',
      ),
      // Then the power: the bearing queues an assembly when its speed changes, and performs it on a
      // following tick.
      ScenarioStep(
        'setblock ${motor.x} ${motor.y} ${motor.z} '
        'create:creative_motor[facing=north]',
      ),
    ];
  },
  probes: (anchor) {
    final bearing = TracePos(anchor.x, anchor.y, anchor.z + 1);
    final motor = TracePos(anchor.x, anchor.y, anchor.z + 2);
    // A `setblock` in a far corner of the same column is the marker: the command runs only if the
    // block *is* the one the rig asked for, and the write is what lands in the console log (a
    // `say` would not). Each probe gets its own marker position, so "matched" cannot be another
    // probe's write.
    ScenarioProbe marker(TracePos at, String block, int index) => ScenarioProbe(
      'execute if block ${at.x} ${at.y} ${at.z} $block run '
      'setblock ${anchor.x} ${anchor.y + 30 + index} ${anchor.z} minecraft:redstone_block',
      expected: ConsoleSession.changedBlock,
    );
    return [
      marker(anchor, 'minecraft:stone', 0),
      marker(bearing, 'create:mechanical_bearing', 1),
      marker(motor, 'create:creative_motor', 2),
      // …and what each server says those block entities *are*, which is where a plugin's own
      // additions to a block entity's data show up next to the mod's.
      ScenarioProbe(
        'data get block ${bearing.x} ${bearing.y} ${bearing.z}',
        expected: RegExp('create:mechanical_bearing'),
      ),
      ScenarioProbe(
        'data get block ${motor.x} ${motor.y} ${motor.z}',
        expected: RegExp('create:creative_motor|create:motor'),
      ),
    ];
  },
  expected: ScenarioPrecondition.contraptionSpawned(),
);

final Map<String, Scenario Function()> scenarios = {
  'contraption': contraptionScenario,
};

Future<int> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options == null) {
    stderr.writeln(usage);
    return 2;
  }
  final scenarioFactory = scenarios[options.scenario];
  if (scenarioFactory == null) {
    stderr.writeln('no scenario `${options.scenario}`; known: ${scenarios.keys.join(', ')}');
    stderr.writeln(usage);
    return 2;
  }
  final scenario = scenarioFactory();
  final environment = DifferentialEnvironment.resolve(
    javaInstall: options.javaDir,
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
      keep: keep,
      all: all,
      settle: settle,
      joinTimeout: join,
    );
  }
}

