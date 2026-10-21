// The differential itself: boot both servers, put a recording proxy in front of each, join a client
// through it, drive the *same* scenario on both, and compare what the two clients were told.
//
// The shape of a run, and why each piece is there:
//
//   server (Java NeoForge | Pumpkin)  ← the two things being compared, each on a free port
//        ↑ mctrace (optional)         ← the bytes, both directions, server-agnostic
//        ↑ pumpkin-tester client       ← a real protocol client: the semantic record, and the thing
//                                        that makes the server *send* anything at all
//   console (stdin)                   ← the scenario, typed identically into both
//
// Nothing in here knows about Create: a scenario supplies the rig and the region, this supplies the
// two arms, the client, the capture and the comparison, so the same runner works for any plugin and
// any mod (which is the point — the difference between the two servers, not between two features).
//
// A run is *fail-closed*: an arm that never joined, a scenario that never assembled on the server
// that works, or a trace that is empty is reported as an arm failure (exit 2) instead of being
// compared, because "both traces are empty" would otherwise read as agreement.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../pumpkin_server.dart';
import '../pumpkin_trace.dart';
import 'game_server.dart';
import 'mctrace.dart';
import 'scenario.dart';
import 'trace_diff.dart';

/// Which server an arm is.
enum ArmKind {
  java('java', 'Java NeoForge'),
  pumpkin('pumpkin', 'Pumpkin');

  const ArmKind(this.id, this.description);

  final String id;
  final String description;

  static ArmKind? of(String name) {
    for (final kind in values) {
      if (kind.id == name || kind.name == name) return kind;
    }
    return null;
  }
}

/// What the runner needs from the environment, resolved once.
final class DifferentialEnvironment {
  DifferentialEnvironment._({
    required this.paths,
    required this.javaInstall,
    required this.mctraceBinary,
  });

  final HarnessPaths paths;

  /// The NeoForge install whose jars the Java arm is built from (`MCTRACE_JAVA_DIR`, else
  /// `~/Documents/mctesting`), or null when there is none.
  final Directory? javaInstall;

  /// `mctrace`, when it has been built.
  final String? mctraceBinary;

  static DifferentialEnvironment resolve({String? javaInstall}) {
    final paths = HarnessPaths.resolve();
    final requested =
        javaInstall ??
        HarnessPaths.readEnv(['MCTRACE_JAVA_DIR', 'JAVA_SERVER_DIR']);
    Directory? install;
    if (requested != null) {
      final candidate = Directory(requested);
      if (!candidate.existsSync()) {
        throw StateError('the Java install $requested does not exist');
      }
      install = candidate;
    } else {
      final home = Platform.environment['HOME'];
      if (home != null) {
        final candidate = Directory(joinPath(home, 'Documents/mctesting'));
        if (candidate.existsSync()) install = candidate;
      }
    }
    return DifferentialEnvironment._(
      paths: paths,
      javaInstall: install,
      mctraceBinary: MctraceProxy.resolveBinary(
        testerBinary: paths.testerBinary,
      ),
    );
  }

  /// Why the Java arm cannot run, or null when it can.
  String? javaUnavailable() {
    final install = javaInstall;
    if (install == null) {
      return 'no NeoForge install: set MCTRACE_JAVA_DIR to a server install with `libraries/` and '
          '`mods/` (the one whose Create jar works)';
    }
    if (!Directory(joinPath(install.path, 'libraries')).existsSync()) {
      return '${install.path} has no `libraries/`, so it is not a NeoForge server install';
    }
    if (!Directory(joinPath(install.path, 'mods')).existsSync()) {
      return '${install.path} has no `mods/`';
    }
    return null;
  }

  /// Why the Pumpkin arm cannot run, or null when it can.
  String? pumpkinUnavailable() => paths.unavailable;
}

/// One side of the comparison: the server, what went in front of it, and what came out.
final class DifferentialArm {
  DifferentialArm({
    required this.role,
    required this.kind,
    required this.server,
    required this.console,
    required this.botName,
    required this.traceFile,
    this.proxy,
    this.bot,
    this.failure,
  });

  /// `reference` (the server that works) or `candidate`.
  final String role;
  final ArmKind kind;
  final GameServer? server;
  final ConsoleSession? console;
  final String botName;

  /// What the client received.
  final File traceFile;

  /// The proxy in front of this arm, when one could be started.
  final MctraceProxy? proxy;

  final Process? bot;

  /// Why this arm produced nothing usable, if it did.
  String? failure;

  /// The client's own record, once the bot has stopped.
  PumpkinTrace? clientTrace;

  /// The scenario's ground-truth replies.
  final List<String> probes = [];

  /// The anchor the rig was built at, as this server sees it.
  TracePos? anchor;

  /// The proxy's own decoded view of the server→client direction, when it could be read.
  PumpkinTrace? proxyTrace;

  /// What the proxy captured, read before the scratch directory is removed.
  String? proxySummary;

  /// Where the raw frames were written (a copy lives on under `--out`, when one was asked for).
  String? capturePath;

  /// The client process's exit code, null while it is still running.
  int? botExitCode;

  /// Whether the client has already been stopped, so stopping it twice is not attempted.
  bool botStopped = false;

  /// Why the proxy's view is missing, when it is.
  String? proxyNote;

  /// The client process's output, for a failure message.
  final StringBuffer botOutput = StringBuffer();

  String get describe => '$role ($kind), bot $botName';

  /// The client's trace, normalised against the anchor and the scenario's box.
  NormalisedTrace? normalised(Scenario scenario) {
    final trace = clientTrace;
    final at = anchor;
    if (trace == null || at == null) return null;
    return NormalisedTrace.of(
      trace,
      label: '$role-${kind.id}',
      origin: at,
      box: scenario.box,
      client: botName,
    );
  }
}

/// Everything one run produced.
final class DifferentialReport {
  DifferentialReport({
    required this.scenario,
    required this.reference,
    required this.candidate,
    required this.differential,
    required this.proxyCheck,
    required this.notes,
    required this.failure,
    required this.environment,
  });

  final Scenario scenario;
  final DifferentialArm reference;
  final DifferentialArm candidate;

  /// The comparison of the two clients' traces, null when an arm failed before it had one.
  final Differential? differential;

  /// The same comparison over the proxy's decoded frames, when the proxy could be read.
  final Differential? proxyCheck;

  final List<String> notes;

  /// Why the run is not a comparison (an arm failed), if it is not.
  final String? failure;

  final DifferentialEnvironment environment;

  /// 0 when the two servers agree, 1 when they differ, 2 when the run never got to compare.
  int get exitCode {
    if (failure != null) return 2;
    final comparison = differential;
    if (comparison == null) return 2;
    return comparison.agrees ? 0 : 1;
  }

  /// The report: what was run, the first difference, and the ground truth behind it.
  String render({bool all = false}) {
    final lines = <String>[
      'differential: ${reference.kind.description} (reference) vs '
          '${candidate.kind.description} (candidate) — scenario `${scenario.name}`',
      '  ${scenario.description}',
      '  rig on the reference at ${reference.anchor} (client player), '
          'on the candidate at ${candidate.anchor}',
      '  comparing ${scenario.box} around each anchor',
    ];
    for (final arm in [reference, candidate]) {
      lines.add(
        '  ${arm.kind.description} arm: port ${arm.server?.port}, '
        'scratch ${arm.server?.scratch.path}',
      );
      if (arm.proxy != null) lines.add('  ${arm.proxy!.summary}');
    }
    if (reference.probes.isNotEmpty || candidate.probes.isNotEmpty) {
      lines
        ..add('')
        ..add('ground truth (what each server says the rig is):');
      for (final probe in reference.probes) {
        lines.add('  ${reference.kind.id}: $probe');
      }
      for (final probe in candidate.probes) {
        lines.add('  ${candidate.kind.id}: $probe');
      }
    }
    if (failure != null) {
      lines
        ..add('')
        ..add('THE RUN DID NOT GET TO COMPARE: $failure');
    } else if (differential != null) {
      lines
        ..add('')
        ..add(differential!.report(all: all));
    }
    if (proxyCheck != null) {
      lines
        ..add('')
        ..add('proxy evidence (the frames on the wire, decoded independently):')
        ..add(proxyCheck!.agrees
            ? '  the proxy sees the same events as the client did'
            : '  ${proxyCheck!.first!.describe()}');
    }
    for (final note in notes) {
      lines.add('note: $note');
    }
    return lines.join('\n');
  }

  /// The machine-readable result, so the same run can drive a CI job.
  Map<String, Object?> toJson() => {
    'scenario': scenario.name,
    'reference': reference.kind.id,
    'candidate': candidate.kind.id,
    'anchors': {
      'reference': reference.anchor?.toString(),
      'candidate': candidate.anchor?.toString(),
    },
    'failure': failure,
    'agrees': differential?.agrees,
    'firstDifference': differential == null || differential!.agrees
        ? null
        : {
            'check': differential!.first!.check,
            'subject': differential!.first!.subject,
            'reference': differential!.first!.reference,
            'candidate': differential!.first!.candidate,
            'eventIndex': differential!.first!.timeline,
          },
    'differences': [
      for (final divergence in differential?.divergences ?? const <Divergence>[])
        {'check': divergence.check, 'subject': divergence.subject},
    ],
    'traces': {
      'reference': reference.traceFile.path,
      'candidate': candidate.traceFile.path,
    },
    'captures': {
      'reference': reference.capturePath,
      'candidate': candidate.capturePath,
    },
    'probes': {
      'reference': reference.probes,
      'candidate': candidate.probes,
    },
    'notes': notes,
  };
}

/// Runs the differential.
final class DifferentialRunner {
  DifferentialRunner({
    required this.environment,
    required this.scenario,
    this.reference = ArmKind.java,
    this.candidate = ArmKind.pumpkin,
    this.botName = 'Watcher',
    this.keep = false,
    this.settleAfter = const Duration(seconds: 4),
    this.joinTimeout = const Duration(seconds: 120),
    this.artifacts,
    this.log,
  });

  final DifferentialEnvironment environment;
  final Scenario scenario;
  final ArmKind reference;
  final ArmKind candidate;
  final String botName;
  final bool keep;

  /// How long to let the servers tick after the scenario, so a tick-driven assembly has happened
  /// and its packets have been flushed before the client is disconnected.
  final Duration settleAfter;
  final Duration joinTimeout;

  /// Where to copy the traces, captures and console logs (`--out`), when the caller wants the
  /// evidence kept outside the scratch directories.
  final Directory? artifacts;

  /// Progress, line by line: a differential is minutes of work, and a run that goes quiet for six
  /// of them cannot be told from a run that has hung.
  final void Function(String message)? log;

  final List<String> notes = [];

  Future<DifferentialReport> run() async {
    final started = <DifferentialArm>[];
    DifferentialArm? referenceArm;
    DifferentialArm? candidateArm;
    String? failure;
    try {
      _say('starting the reference arm (${reference.description})');
      referenceArm = await _startArm('reference', reference);
      started.add(referenceArm);
      failure = referenceArm.failure;
      if (failure == null) {
        _say('starting the candidate arm (${candidate.description})');
        candidateArm = await _startArm('candidate', candidate);
        started.add(candidateArm);
        failure = candidateArm.failure;
      }
      if (failure == null) {
        await _drive(referenceArm);
        _say('reference arm done; driving the candidate arm');
        await _drive(candidateArm!);
        await _collect(referenceArm);
        await _collect(candidateArm);
      }
    } on Object catch (error, stack) {
      failure = 'the harness failed: $error\n$stack';
    } finally {
      for (final arm in started.reversed) {
        await _stopArm(arm);
      }
    }

    final referenceField = referenceArm ?? _missing('reference', reference);
    final candidateField = candidateArm ?? _missing('candidate', candidate);
    failure ??= _precondition(referenceField);
    Differential? comparison;
    Differential? proxyCheck;
    if (failure == null) {
      final referenceTrace = referenceField.normalised(scenario);
      final candidateTrace = candidateField.normalised(scenario);
      if (referenceTrace == null || candidateTrace == null) {
        failure = 'an arm produced no trace to compare';
      } else {
        comparison = Differential.compare(referenceTrace, candidateTrace);
      }
      final referenceProxy = referenceField.proxyTrace;
      final candidateProxy = candidateField.proxyTrace;
      if (referenceProxy != null && candidateProxy != null) {
        proxyCheck = Differential.compare(
          NormalisedTrace.of(
            referenceProxy,
            label: '${reference.id}-proxy',
            origin: referenceField.anchor!,
            box: scenario.box,
          ),
          NormalisedTrace.of(
            candidateProxy,
            label: '${candidate.id}-proxy',
            origin: candidateField.anchor!,
            box: scenario.box,
          ),
        );
      }
    }
    if (referenceField.traceFile.existsSync() ||
        candidateField.traceFile.existsSync()) {
      notes.add(
        'traces: ${referenceField.traceFile.path} and ${candidateField.traceFile.path}'
        '${keep ? '' : ' (scratch directories are removed; set --keep to inspect them)'}',
      );
    }
    return DifferentialReport(
      scenario: scenario,
      reference: referenceField,
      candidate: candidateField,
      differential: comparison,
      proxyCheck: proxyCheck,
      notes: notes,
      failure: failure,
      environment: environment,
    );
  }

  void _say(String message) => log?.call(message);

  DifferentialArm _missing(String role, ArmKind kind) => DifferentialArm(
    role: role,
    kind: kind,
    server: null,
    console: null,
    botName: botName,
    traceFile: File('${Directory.systemTemp.path}/never-written-$role.jsonl'),
    failure: 'this arm never started',
  );

  /// The reference arm must have produced what the scenario says it produces.
  String? _precondition(DifferentialArm referenceArm) {
    final expected = scenario.expected;
    if (expected == null) return null;
    final trace = referenceArm.normalised(scenario);
    if (trace == null) return 'the reference arm has no trace';
    if (!expected.test(trace)) {
      return 'the scenario did not produce its own result on the reference arm '
          '(${referenceArm.kind.description}): expected ${expected.description}, but its trace '
          'has ${trace.events.length} comparable events. This is a harness problem, not a server '
          'difference — the rig never assembled on the server that works, so there is nothing to '
          'compare. Console tail:\n${_tail(referenceArm.server?.logLines ?? const [])}';
    }
    return null;
  }

  /// Boots one arm: the server, the proxy, and the client through it.
  Future<DifferentialArm> _startArm(String role, ArmKind kind) async {
    if (kind == ArmKind.java) {
      final reason = environment.javaUnavailable();
      if (reason != null) {
        return DifferentialArm(
          role: role,
          kind: kind,
          server: null,
          console: null,
          botName: botName,
          traceFile: File('${Directory.systemTemp.path}/never-written-$role.jsonl'),
          failure: 'the Java arm cannot start: $reason',
        );
      }
    } else {
      final reason = environment.pumpkinUnavailable();
      if (reason != null) {
        return DifferentialArm(
          role: role,
          kind: kind,
          server: null,
          console: null,
          botName: botName,
          traceFile: File('${Directory.systemTemp.path}/never-written-$role.jsonl'),
          failure: 'the Pumpkin arm cannot start: $reason',
        );
      }
    }

    GameServer server;
    try {
      server = switch (kind) {
        ArmKind.java => await JavaNeoForgeServer.start(
          install: environment.javaInstall!,
        ),
        ArmKind.pumpkin => await PumpkinArm.start(paths: environment.paths),
      };
    } on Object catch (error) {
      return DifferentialArm(
        role: role,
        kind: kind,
        server: null,
        console: null,
        botName: botName,
        traceFile: File('${Directory.systemTemp.path}/never-written-$role.jsonl'),
        failure: 'the ${kind.id} server did not start: $error',
      );
    }

    _say(
      '$role: ${kind.description} is up on port ${server.port} '
      '(${server.scratch.path})',
    );
    final console = ConsoleSession(server, log: log);
    MctraceProxy? proxy;
    final binary = environment.mctraceBinary;
    if (binary != null) {
      try {
        proxy = await MctraceProxy.start(
          upstreamPort: server.port,
          capture: File(joinPath(server.scratch.path, 'capture-$role.jsonl')),
          binary: binary,
        );
        _say('$role: mctrace is recording on port ${proxy.port}');
      } on Object catch (error) {
        notes.add('no proxy on the $role arm: $error');
        _say('$role: no proxy ($error)');
      }
    } else {
      notes.add(
        'no mctrace binary (set MCTRACE_BIN), so the raw wire frames are not captured; '
        'the comparison uses the clients\' own traces',
      );
    }

    final traceFile = File(joinPath(server.scratch.path, 'client-$role.jsonl'));
    final bot = await Process.start(
      environment.paths.testerBinary!,
      [
        'client',
        '--addr',
        '127.0.0.1:${proxy?.port ?? server.port}',
        '--name',
        botName,
        '--trace',
        traceFile.absolute.path,
        // The Java arm needs the mirrored NeoForge handshake: a modded server refuses a client whose
        // channel answer does not match its own declaration, and a standalone client has no
        // declaration to answer with.
        if (kind == ArmKind.java) '--mirror',
      ],
    );
    final arm = DifferentialArm(
      role: role,
      kind: kind,
      server: server,
      console: console,
      botName: botName,
      traceFile: traceFile,
      proxy: proxy,
      bot: bot,
    );
    _say('$role: joining a client as `${arm.botName}` through port '
        '${proxy?.port ?? server.port}');
    bot.stdout.transform(utf8.decoder).listen(arm.botOutput.write);
    bot.stderr.transform(utf8.decoder).listen(arm.botOutput.write);
    unawaited(bot.exitCode.then((code) => arm.botExitCode = code));

    final joined = await _awaitJoin(arm);
    if (joined != null) {
      arm.failure = joined;
      await copyArtifacts(arm);
      await _stopArm(arm);
    }
    return arm;
  }

  /// Waits until the client is in the world, or explains why it never got there.
  Future<String?> _awaitJoin(DifferentialArm arm) async {
    final deadline = DateTime.now().add(joinTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!File(arm.traceFile.path).existsSync() &&
          await _botExited(arm)) {
        return 'the ${arm.kind.id} client exited before it joined:\n'
            '${arm.botOutput.toString().trim()}\n'
            '${_tail(arm.server?.logLines ?? const [], 20)}'
            '${_mirrorHint(arm)}';
      }
      final trace = PumpkinTrace.readWhileWriting(arm.traceFile);
      if (trace.chunks.isNotEmpty) {
        _say('${arm.role}: the client is in the world');
        return null;
      }
      if (await _botExited(arm)) {
        return 'the ${arm.kind.id} client exited before it joined:\n'
            '${arm.botOutput.toString().trim()}\n'
            '${_tail(arm.server?.logLines ?? const [], 20)}'
            '${_mirrorHint(arm)}';
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return 'the ${arm.kind.id} client did not join within ${joinTimeout.inSeconds}s:\n'
        '${arm.botOutput.toString().trim()}\n'
        '${_tail(arm.server?.logLines ?? const [], 20)}';
  }

  /// A hint when the client was refused because the bot's CLI does not know `--mirror` yet.
  String _mirrorHint(DifferentialArm arm) {
    final output = arm.botOutput.toString();
    if (arm.kind != ArmKind.java || !output.contains('usage: pumpkin-tester client')) {
      return '';
    }
    return '\nThis `pumpkin-tester` does not implement `--mirror` (its usage line does not list '
        'it), which is what a NeoForge server requires of a client that has to answer its channel '
        'query. The Java arm is pending that flag; until then the differential still runs against '
        'two Pumpkin arms (`--candidate pumpkin --reference pumpkin`).';
  }

  Future<bool> _botExited(DifferentialArm arm) async {
    if (arm.bot == null) return true;
    // The exit code is recorded as soon as it is known, so asking is a field read and never a
    // race against a process that exits between two polls.
    return arm.botExitCode != null;
  }

  /// Runs the scenario and the probes on one arm.
  Future<void> _drive(DifferentialArm arm) async {
    final console = arm.console;
    final server = arm.server;
    if (console == null || server == null) return;
    final player = await console.playerPosition(arm.botName);
    final anchor = scenario.anchorOf(player);
    arm.anchor = anchor;
    notes.add(
      '${arm.role}: the client stands at $player, the rig is built at $anchor '
      '(the client tracking only covers its own chunks, so the rig has to be there)',
    );
    await runScenario(console, scenario, anchor);
    _say('${arm.role}: the rig is built; letting it tick');
    await console.tick(settleAfter);
    await console.sync();
    arm.probes.addAll(await runProbes(console, scenario, anchor));
    _say('${arm.role}: scenario done (${arm.probes.length} ground-truth probes)');
  }

  /// Stops the client, drains its trace, reads the proxy's capture, and stops the server.
  Future<void> _collect(DifferentialArm arm) async {
    _say('${arm.role}: stopping the client and reading its trace');
    await _stopBot(arm);
    if (arm.traceFile.existsSync()) {
      arm.clientTrace = PumpkinTrace.read(arm.traceFile);
    }
    final proxy = arm.proxy;
    if (proxy != null) {
      // Read while the scratch directory still exists: both of these read files it holds.
      arm.proxySummary = proxy.summary;
      arm.capturePath = proxy.capture.path;
      try {
        arm.proxyTrace = await proxy.decoded();
      } on Object catch (error) {
        arm.proxyNote = '$error';
        notes.add(
          "the ${arm.role} arm's proxy frames could not be decoded: $error",
        );
      }
    }
    await copyArtifacts(arm);
    await _stopArm(arm);
  }

  /// Keeps this arm's evidence under `--out`, before the scratch directory goes.
  Future<void> copyArtifacts(DifferentialArm arm) async {
    final into = artifacts;
    if (into == null) return;
    into.createSync(recursive: true);
    void copy(File file, String name) {
      if (!file.existsSync()) return;
      file.copySync(joinPath(into.path, name));
    }

    copy(arm.traceFile, 'client-${arm.role}-${arm.kind.id}.jsonl');
    final capture = arm.proxy?.capture;
    if (capture != null) {
      copy(capture, 'capture-${arm.role}-${arm.kind.id}.jsonl');
    }
    final server = arm.server;
    if (server != null) {
      File(
        joinPath(into.path, 'console-${arm.role}-${arm.kind.id}.log'),
      ).writeAsStringSync(server.logText());
    }
  }

  /// Stops the client, whose trace is complete once it exits.
  Future<void> _stopBot(DifferentialArm arm) async {
    if (arm.botStopped) return;
    arm.botStopped = true;
    final bot = arm.bot;
    if (bot == null) return;
    // Closing stdin is the client's own stop, which lets it flush its last lines.
    try {
      await bot.stdin.close();
    } on Object {
      // Already gone.
    }
    try {
      await bot.exitCode.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      bot.kill(ProcessSignal.sigterm);
      await bot.exitCode;
    }
  }

  /// Stops the server and whatever was in front of it.
  Future<void> _stopArm(DifferentialArm arm) async {
    await _stopBot(arm);
    await arm.proxy?.stop();
    _say('${arm.role}: stopping the server');
    final server = arm.server;
    if (server is PumpkinArm) {
      await server.dispose();
    } else if (server is JavaNeoForgeServer) {
      await server.dispose(keep: keep);
    } else {
      await server?.stop();
    }
  }

  /// The last lines of a log, for a failure message.
  static String _tail(List<String> lines, [int count = 12]) {
    final tail = lines.length > count
        ? lines.sublist(lines.length - count)
        : lines;
    return 'console tail:\n${tail.join('\n')}\n';
  }
}