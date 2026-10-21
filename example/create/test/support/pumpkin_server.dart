// Boots the *real* Pumpkin binary with a plugin in `plugins/`, drives it over the console, and
// reads back the packet trace it wrote.
//
// The server is a separate process, so nothing this suite asserts on can be an artefact of a
// harness that shares the server's memory. Two things make it drivable without a Minecraft client
// of our own:
//
//  * the console — `setup_stdin_console` runs whenever stdin is not a TTY
//    (`crates/pumpkin-core/src/lib.rs:462`), so writing a line to the process's stdin runs that
//    command as the console sender, which has a world handle and permission level 4;
//  * the trace — `PUMPKIN_PACKET_TRACE=<path>` makes the server write one JSON line per packet it
//    enqueues to a client (`crates/pumpkin-core/src/net/packet_trace.rs`).
//
// What a *client* actually received comes from `pumpkin_client.dart`, which runs the headless
// client of `tools/pumpkin-tester` against the same server. `PumpkinLab` (`pumpkin_lab.dart`) owns
// both; every environment variable is documented in `example/create/README.md`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pumpkin_trace.dart';

/// Path helpers, so this file does not depend on `package:path` (which the plugin package does not
/// declare).
String joinPath(String first, String second) =>
    first.endsWith(Platform.pathSeparator)
    ? '$first$second'
    : '$first${Platform.pathSeparator}$second';

String baseName(String path) => path.split(Platform.pathSeparator).last;

/// Resolves the binaries and the plugin component the end-to-end tests need.
///
/// Everything is overridable from the environment so CI can point the suite at a build instead of
/// at someone's checkout, and a missing piece is reported as a reason to skip, never as a failure.
final class HarnessPaths {
  HarnessPaths._({
    required this.serverBinary,
    required this.testerBinary,
    required this.pluginComponent,
    required this.packageRootPath,
  });

  /// The `pumpkin` server binary (`PUMPKIN_BIN` or `PUMPKIN_SERVER_BIN`), or null when unset.
  final String? serverBinary;

  /// The `pumpkin-tester` binary (`PUMPKIN_TESTER_BIN`, else the server binary's directory).
  final String? testerBinary;

  /// The plugin component to load (`PUMPKIN_PLUGIN_WASM`, else `build/create.wasm`).
  final String pluginComponent;

  /// The `example/create` package directory.
  final String packageRootPath;

  static String? readEnv(List<String> names) {
    for (final name in names) {
      final value = Platform.environment[name];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Whether the component should be built when it is missing (`PUMPKIN_BUILD_PLUGIN=1`).
  static bool get buildPlugin => const ['1', 'true', 'yes']
      .contains((readEnv(['PUMPKIN_BUILD_PLUGIN']) ?? '').toLowerCase());

  /// The `example/create` package directory: the nearest ancestor of the working directory whose
  /// `pubspec.yaml` names this package, so the suite also runs from the workspace root.
  static Directory packageRoot() {
    var directory = Directory.current;
    for (var depth = 0; depth < 6; depth++) {
      final pubspec = File(joinPath(directory.path, 'pubspec.yaml'));
      if (pubspec.existsSync() &&
          pubspec.readAsStringSync().contains('name: create')) {
        return directory;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    return Directory.current;
  }

  static HarnessPaths resolve() {
    final root = packageRoot();
    final server = readEnv(['PUMPKIN_BIN', 'PUMPKIN_SERVER_BIN']);
    final testerEnv = readEnv(['PUMPKIN_TESTER_BIN']);
    final sibling = server == null
        ? null
        : joinPath(File(server).parent.path, 'pumpkin-tester');
    final tester = testerEnv ?? ((sibling != null && File(sibling).existsSync()) ? sibling : null);
    final component =
        readEnv(['PUMPKIN_PLUGIN_WASM']) ??
        joinPath(joinPath(root.path, 'build'), 'create.wasm');
    return HarnessPaths._(
      serverBinary: server,
      testerBinary: tester,
      pluginComponent: component,
      packageRootPath: root.path,
    );
  }

  /// Why the end-to-end suite cannot run, or null when it can.
  String? get unavailable {
    final server = serverBinary;
    if (server == null) {
      return 'no server binary: set PUMPKIN_BIN (or PUMPKIN_SERVER_BIN) to a built `pumpkin`, '
          'e.g. PUMPKIN_BIN=target/fast/pumpkin';
    }
    if (!File(server).existsSync()) {
      return 'no server binary at $server';
    }
    if (testerBinary == null) {
      return 'no `pumpkin-tester` next to $server: set PUMPKIN_TESTER_BIN (its `client` mode is '
          'the simulated client the relogin diff needs)';
    }
    if (!File(pluginComponent).existsSync() && !buildPlugin) {
      return 'no plugin component at $pluginComponent '
          '(set PUMPKIN_PLUGIN_WASM, or PUMPKIN_BUILD_PLUGIN=1 to build it)';
    }
    return null;
  }

  /// Builds the component with the SDK running this test, at most once per process.
  static Future<void> buildComponent(HarnessPaths paths) async {
    if (_built) return;
    final result = await Process.run(
      Platform.resolvedExecutable,
      const ['run', 'pumpkin_tools', 'build'],
      workingDirectory: paths.packageRootPath,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'pumpkin_tools build failed (${result.exitCode}):\n'
        '${result.stdout}\n${result.stderr}',
      );
    }
    _built = true;
  }

  static bool _built = false;
}

/// A booted `pumpkin` process with a scratch server directory around it.
final class PumpkinServer {
  PumpkinServer._(
    this._process,
    this.scratch,
    this.traceFile,
    this.port,
  );

  final Process _process;

  /// The throwaway server directory: its own `plugins/`, `pumpkin.toml` and world.
  final Directory scratch;

  /// The server-side trace: what the server enqueued for each connection.
  final File traceFile;

  /// The port this server bound. Ephemeral, never 25565, so a running server of the user's is
  /// never involved.
  final int port;

  /// Every line the server printed, ANSI escapes stripped.
  final List<String> logLines = [];

  final StringBuffer _all = StringBuffer();
  final Completer<void> _readySignal = Completer<void>();
  final List<({Pattern pattern, int from, Completer<void> completer})> _waiters = [];

  bool _running = true;

  static final RegExp _readyLine = RegExp(r'Server is now running');
  static final RegExp _fatalLine = RegExp(
    r'is already in use|Failed to initialize|The server has stopped',
  );
  static final RegExp _ansi = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

  /// The barrier command: a barrier needs a reply of its own, and `/list` always prints one.
  static const String syncCommand = 'list';
  static final RegExp syncReply = RegExp(r'players online');

  /// What the console says when a `setblock` landed, and when its position is not loaded yet.
  static final RegExp _changedBlock = RegExp(r'Changed the block at');
  static final RegExp _positionNotLoaded = RegExp(r'not loaded');

  static Duration get settleTime => Duration(
    milliseconds:
        int.tryParse(HarnessPaths.readEnv(['PUMPKIN_E2E_SETTLE_MS']) ?? '') ??
        1500,
  );

  static Duration get startupTimeout => Duration(
    seconds:
        int.tryParse(HarnessPaths.readEnv(['PUMPKIN_E2E_STARTUP_SECONDS']) ?? '') ??
        300,
  );

  static Duration get stopTimeout => Duration(
    seconds:
        int.tryParse(HarnessPaths.readEnv(['PUMPKIN_E2E_STOP_SECONDS']) ?? '') ??
        90,
  );

  /// Picks a free port.
  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  /// The server's configuration: a scratch world, no Bedrock, no online mode, no encryption (so a
  /// simulated client only has to read bare frames), plugins auto-approved, console on stdin.
  static String _config(int port) => '''
# Written by the Dart end-to-end harness (test/support/pumpkin_server.dart).
default_level_name = "world"
allow_nether = false
allow_end = false
allow_chat_reports = false
white_list = false
enforce_whitelist = false
op_permission_level = 4
spawn_protection = 0

[logging]
enabled = true
level = "info"
color = false
timestamp = false
file = ""

[world]
lighting = "default"

[networking.java]
enabled = true
address = "127.0.0.1:$port"
encryption = false
online_mode = false
view_distance = 8
simulation_distance = 8

[networking.java.compression]
enabled = false
threshold = 256
level = 4

[networking.java.authentication]
enabled = false

[networking.bedrock]
enabled = false

[networking.query]
enabled = false

[networking.management]
enabled = false

[networking.lan_broadcast]
enabled = false

[commands]
use_console = true
use_tty = false

[player_data]
save_player_data = false

[advancement]
save_advancements = false

[plugins]
enabled = true
hot_reload = false
ask_permission_confirmation = false
allow_unsigned = true
verify_signatures = false

[telemetry]
enabled = false
''';

  /// Boots the server with [HarnessPaths.pluginComponent] copied into its scratch `plugins/`.
  ///
  /// [pluginName] is what the loader logs when a plugin is up (`"Loaded create (…)"`), so a plugin
  /// that silently never loaded is reported here instead of surfacing later as an empty trace.
  static Future<PumpkinServer> start({
    required HarnessPaths paths,
    String? pluginName = 'create',
    Map<String, String> environment = const {},
  }) async {
    if (HarnessPaths.buildPlugin && !File(paths.pluginComponent).existsSync()) {
      await HarnessPaths.buildComponent(paths);
    }
    final unavailable = paths.unavailable;
    if (unavailable != null) {
      throw StateError('the end-to-end harness cannot start: $unavailable');
    }

    final scratch = Directory.systemTemp.createTempSync('pumpkin-e2e-');
    final pluginsDir = Directory(joinPath(scratch.path, 'plugins'))..createSync();
    File(
      paths.pluginComponent,
    ).copySync(joinPath(pluginsDir.path, baseName(paths.pluginComponent)));

    final port =
        int.tryParse(HarnessPaths.readEnv(['PUMPKIN_E2E_PORT']) ?? '') ??
        await _freePort();
    File(joinPath(scratch.path, 'pumpkin.toml')).writeAsStringSync(_config(port));

    final traceFile = File(joinPath(scratch.path, 'server.trace.jsonl'));
    final process = await Process.start(
      paths.serverBinary!,
      const [],
      workingDirectory: scratch.path,
      environment: {
        ...Platform.environment,
        'PUMPKIN_PACKET_TRACE': traceFile.absolute.path,
        ...environment,
      },
    );

    final server = PumpkinServer._(process, scratch, traceFile, port);
    server._pump(process.stdout);
    server._pump(process.stderr);
    await server._awaitReady(pluginName);
    return server;
  }

  void _pump(Stream<List<int>> stream) {
    stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            final clean = line.replaceAll(_ansi, '');
            logLines.add(clean);
            _all.writeln(clean);
            if (!_readySignal.isCompleted) {
              if (_fatalLine.hasMatch(clean)) {
                _readySignal.completeError(
                  StateError('the server failed to start: $clean'),
                );
              } else if (_readyLine.hasMatch(clean)) {
                _readySignal.complete();
              }
            }
            for (final waiter in [..._waiters]) {
              if (logLines.length > waiter.from &&
                  waiter.pattern.allMatches(clean).isNotEmpty) {
                _waiters.remove(waiter);
                if (!waiter.completer.isCompleted) waiter.completer.complete();
              }
            }
          },
          onDone: () {
            if (!_readySignal.isCompleted) {
              _readySignal.completeError(
                StateError('the server exited before it was ready'),
              );
            }
          },
        );
  }

  Future<void> _awaitReady(String? pluginName) async {
    try {
      await _readySignal.future.timeout(
        startupTimeout,
        onTimeout: () => throw StateError(
          'the server was not ready within ${startupTimeout.inSeconds}s:\n${logText()}',
        ),
      );
    } on Object {
      await stop();
      rethrow;
    }
    if (pluginName != null &&
        !logLines.any((line) => line.contains('Loaded $pluginName'))) {
      await stop();
      throw StateError(
        'the server started but never logged `Loaded $pluginName`, so nothing in this run would '
        'exercise the plugin:\n${logText()}',
      );
    }
  }

  bool get isRunning => _running;

  /// Everything the server has printed.
  String logText() => _all.toString();

  /// Runs one console command.
  Future<void> command(String command) async {
    if (!_running) {
      throw StateError('the server is not running; cannot run `$command`');
    }
    _process.stdin.write('$command\n');
    await _process.stdin.flush();
  }

  /// Waits until a line matching [pattern] is printed, considering only lines from [from] on.
  ///
  /// This is the harness's non-blind half: a barrier command's own reply says the commands typed
  /// before it have been dispatched, so nothing here gambles on a delay.
  Future<void> waitForOutput(
    Pattern pattern, {
    Duration? timeout,
    int from = 0,
  }) async {
    for (var i = from; i < logLines.length; i++) {
      if (pattern.allMatches(logLines[i]).isNotEmpty) return;
    }
    final completer = Completer<void>();
    _waiters.add((pattern: pattern, from: from, completer: completer));
    await completer.future.timeout(
      timeout ?? const Duration(seconds: 60),
      onTimeout: () => throw StateError(
        'the server never printed anything matching $pattern:\n'
        '${logLines.skip(from).join('\n')}',
      ),
    );
  }

  /// Lets the server tick: block writes, merges and packet flushes are tick-driven, so a scenario
  /// that only waits for its commands to return can assert on state the server has not sent yet.
  Future<void> settle([Duration? duration]) =>
      Future<void>.delayed(duration ?? settleTime);

  /// Waits until every command written so far has run, then lets the server tick.
  Future<void> sync() async {
    final from = logLines.length;
    await command(syncCommand);
    await waitForOutput(syncReply, from: from);
    await settle();
  }

  /// Runs [commands] in order, letting the server tick between them, and synchronizes at the end.
  Future<void> scenario(Iterable<String> commands) async {
    for (final command in commands) {
      await this.command(command);
      await settle();
    }
    await sync();
  }

  /// Runs [command] until its own reply matches [success].
  ///
  /// Chunk generation is asynchronous — a `forceload` marks a chunk long before it can be written
  /// to, and world generation on a loaded machine can be a second or more behind — so a scenario
  /// that types `setblock` once and hopes is flaky. The console's reply is the signal ("Changed the
  /// block at …" versus an error), so this retries on the reply rather than sleeping longer.
  ///
  /// [retryWhile] is what makes a refusal visible: a reply that matches it is retried (and so is no
  /// reply at all, which is what a command queued behind a busy server looks like); a reply that
  /// does not (a typo, a missing permission) fails at once, with the server's own words.
  Future<void> commandUntil(
    String command,
    Pattern success, {
    Pattern? retryWhile,
    Duration timeout = const Duration(minutes: 3),
    Duration interval = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var lastReply = '<the command was never answered>';
    while (DateTime.now().isBefore(deadline)) {
      final from = logLines.length;
      await this.command(command);
      try {
        await waitForOutput(success, from: from, timeout: interval);
        return;
      } on StateError {
        final reply = logLines.skip(from).join(' | ');
        if (reply.isNotEmpty) lastReply = reply;
        if (reply.isNotEmpty &&
            retryWhile != null &&
            retryWhile.allMatches(reply).isEmpty) {
          throw StateError(
            '`$command` was refused and the reply is not a retryable one: $reply\n'
            '${logText()}',
          );
        }
        await settle(const Duration(seconds: 1));
      }
    }
    throw StateError(
      '`$command` never succeeded within ${timeout.inSeconds}s; its last reply was: $lastReply\n'
      '${logText()}',
    );
  }

  /// Places a block, waiting for its chunk to be loaded first.
  ///
  /// `setblock` needs a *loaded* position; the console says "That position is not loaded" until the
  /// chunk is there, which is the reply this retries on.
  Future<void> placeBlock(TracePos at, String block) => commandUntil(
    'setblock ${at.x} ${at.y} ${at.z} $block',
    _changedBlock,
    retryWhile: _positionNotLoaded,
  );

  /// The server-side trace as it stands (safe to call while the server runs).
  PumpkinTrace readTrace() => PumpkinTrace.readWhileWriting(traceFile);

  /// Runs one command and returns everything the server printed while it ran.
  ///
  /// The window is closed by the [sync] barrier, so the returned lines are that command's own reply
  /// (plus the barrier's, which the caller can ignore) — this is how a test reads a fact out of the
  /// server instead of guessing it.
  Future<List<String>> outputOf(String command) async {
    final from = logLines.length;
    await this.command(command);
    await sync();
    return logLines.sublist(from);
  }

  /// The block position a client's player is standing at, as the *server* sees it.
  ///
  /// A scenario has to run where the client is: the server only sends block updates and block
  /// entities to players tracking the chunk, and a console `tp` does not move that tracking (it
  /// never sends the destination's chunk), so the position has to be read rather than assumed.
  Future<TracePos> playerPosition(String name) async {
    final reply = await outputOf('data get entity $name Pos');
    final labelled = reply.where((line) => line.contains('entity data')).join('\n');
    final text = labelled.isEmpty ? reply.join('\n') : labelled;
    final afterLabel = text.contains(':')
        ? text.substring(text.lastIndexOf(':') + 1)
        : text;
    final numbers = RegExp(r'-?\d+(?:\.\d+)?')
        .allMatches(afterLabel)
        .map((match) => double.parse(match.group(0)!))
        .toList();
    if (numbers.length < 3) {
      throw StateError(
        'could not read the position of $name from its reply: ${reply.join(' | ')}',
      );
    }
    return TracePos(
      numbers[0].floor(),
      numbers[1].floor(),
      numbers[2].floor(),
    );
  }

  /// Stops the server: the console's own `stop` first, signals only if it does not go.
  Future<void> stop({Duration? timeout}) async {
    if (!_running) return;
    try {
      _process.stdin.write('stop\n');
      await _process.stdin.flush();
    } on Object {
      // The process may already be gone; the wait below decides.
    }
    _running = false;
    try {
      await _process.exitCode.timeout(timeout ?? stopTimeout);
    } on TimeoutException {
      _process.kill(ProcessSignal.sigterm);
      try {
        await _process.exitCode.timeout(const Duration(seconds: 20));
      } on TimeoutException {
        _process.kill(ProcessSignal.sigkill);
        await _process.exitCode;
      }
    }
    try {
      await _process.stdin.close();
    } on Object {
      // Already closed.
    }
  }

  /// Stops the server and deletes the scratch directory, unless `PUMPKIN_E2E_KEEP=1` asked for it.
  ///
  /// The server's own console output is written to `<scratch>/server.log` either way: it is the only
  /// place a scenario's command errors, a plugin's warnings and a connection's kick reason are
  /// visible, and a test that fails without it is a test nobody can debug.
  Future<void> dispose() async {
    await stop();
    try {
      File(joinPath(scratch.path, 'server.log')).writeAsStringSync(logText());
    } on FileSystemException {
      // Nothing to write into (the directory is already gone).
    }
    if (HarnessPaths.readEnv(['PUMPKIN_E2E_KEEP']) == '1') {
      stdout.writeln('[e2e] kept the server directory at ${scratch.path}');
      return;
    }
    try {
      scratch.deleteSync(recursive: true);
    } on FileSystemException {
      // A leftover directory is not worth failing a test over.
    }
  }
}