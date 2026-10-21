// The two servers the differential drives, behind one console.
//
// A differential is only worth anything if the two arms are driven *identically*, so the thing that
// is shared is the scenario driver, not the server: [GameServer] is what a server has to provide
// (a port, a log, a stdin console, a stop), and [ConsoleSession] is the console protocol both
// servers answer the same way, because the plugin ports the vanilla commands' replies verbatim.
//
// The Java side is a NeoForge dedicated server built from the *files of an existing install*: the
// loader jars (`libraries/`) and the mod jars (`mods/`) are symlinked, and everything the server
// writes — a fresh world, configs, logs — goes to a scratch directory of its own with its own port
// and `online-mode=false`, so an existing install is read but never touched and a player's running
// server is never involved. That is what makes a real Create server drivable by the harness: no
// launcher, no gradle, no human clicking Singleplayer.
//
// Ports are always picked as free ports (or from the harness's own environment), never the ones a
// user's servers listen on.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../pumpkin_server.dart';
import '../pumpkin_trace.dart';

/// A server the differential can boot, drive over its console and read the output of.
abstract interface class GameServer {
  /// What this arm is called in the report (`java`, `pumpkin`).
  String get label;

  /// The port a client connects to.
  int get port;

  /// The throwaway directory the server runs in.
  Directory get scratch;

  /// Every line the server printed, ANSI escapes stripped.
  List<String> get logLines;

  /// Everything the server printed, joined.
  String logText();

  bool get isRunning;

  /// Writes one command line to the server's console.
  Future<void> command(String line);

  /// Waits until a line matching [pattern] is printed, considering only lines from [from] on.
  Future<void> waitForOutput(Pattern pattern, {int from, Duration? timeout});

  /// Stops the server (its own `stop` first, signals only if it does not go).
  Future<void> stop();
}

/// The console protocol: the commands a scenario is written in, and the replies it waits for.
///
/// Every one of these exists because a scenario that sleeps and hopes is flaky: a command's own
/// reply says it ran, `/list` is the barrier that says everything typed before it has been
/// dispatched, and the tick-driven parts of a contraption (a bearing assembles on a *later* tick
/// than the one that changed its speed) are covered by an explicit settle.
final class ConsoleSession {
  ConsoleSession(this.server, {Duration? settle, Duration? timeout, this.log})
    : settle = settle ?? const Duration(milliseconds: 2000),
      timeout = timeout ?? const Duration(minutes: 3);

  final GameServer server;

  /// Where to say what is being run, so a long run shows its own progress instead of going quiet.
  final void Function(String message)? log;

  /// How long to let the server tick after a command.
  final Duration settle;

  /// How long a command may take before the run is a failure.
  final Duration timeout;

  /// The barrier command: `/list` always answers, so its reply says the queue is drained.
  static const String syncCommand = 'list';

  /// Both servers answer `/list` with the vanilla sentence.
  static final RegExp syncReply = RegExp(r'players online');

  /// What both servers say when a block write lands (the plugin ships the vanilla sentence).
  static final RegExp changedBlock = RegExp(
    r'Changed the block at|Successfully filled|No blocks were filled',
  );

  /// What both servers say while the target position's chunk is not ready for a write yet: the
  /// plugin says "That position is not loaded", vanilla says "Could not set the block" for a chunk
  /// that is still being force-loaded or generated. Both are worth retrying; anything else (an
  /// unknown block, a missing permission) is a failure with the server's own words.
  static final RegExp positionNotLoaded = RegExp(
    r'not loaded|Could not set the block',
  );

  /// What both servers say when a force-load lands.
  static final RegExp forceLoaded = RegExp(r'force loaded');

  /// Lets the server tick.
  Future<void> tick([Duration? duration]) =>
      Future<void>.delayed(duration ?? settle);

  /// Runs one command and waits for the server to answer it.
  Future<void> run(String command, Pattern reply, {Duration? timeout}) async {
    final from = server.logLines.length;
    await server.command(command);
    await server.waitForOutput(reply, from: from, timeout: timeout ?? this.timeout);
  }

  /// Waits until every command written so far has run, then lets the server tick.
  Future<void> sync() async {
    await run(syncCommand, syncReply);
    await tick();
  }

  /// Runs [commands] in order, letting the server tick between them, and synchronizes at the end.
  Future<void> scenario(Iterable<String> commands) async {
    for (final command in commands) {
      await this.command(command);
      await tick();
    }
    await sync();
  }

  /// Runs one command, letting the server tick after it.
  Future<void> command(String command) async {
    log?.call('${server.label}: $command');
    await server.command(command);
    await tick();
  }

  /// Runs [command] until its own reply matches [success].
  ///
  /// A reply that matches [retryWhile] (the chunk is not loaded yet) is retried, as is no answer at
  /// all; any other reply fails at once with the server's own words, so a typo or a refused command
  /// is reported instead of being retried for minutes.
  Future<void> until(
    String command,
    Pattern success, {
    Pattern? retryWhile,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var lastReply = '<the command was never answered>';
    while (DateTime.now().isBefore(deadline)) {
      final from = server.logLines.length;
      log?.call('${server.label}: $command');
      await server.command(command);
      try {
        await server.waitForOutput(
          success,
          from: from,
          timeout: const Duration(seconds: 3),
        );
        return;
      } on StateError {
        final reply = server.logLines.skip(from).join(' | ');
        if (reply.isNotEmpty) lastReply = reply;
        if (reply.isNotEmpty &&
            retryWhile != null &&
            retryWhile.allMatches(reply).isEmpty) {
          throw StateError(
            '`$command` was refused: $reply\n${server.logText()}',
          );
        }
        await tick(const Duration(seconds: 1));
      }
    }
    throw StateError(
      '`$command` never succeeded within ${timeout.inSeconds}s; its last reply was: $lastReply',
    );
  }

  /// Places a block, waiting for its chunk to be loaded first.
  Future<void> placeBlock(TracePos at, String block) => until(
    'setblock ${at.x} ${at.y} ${at.z} $block',
    changedBlock,
    retryWhile: positionNotLoaded,
  );

  /// Fills a box with one block, waiting for the chunks to be loaded.
  Future<void> fill(TracePos from, TracePos to, String block) => until(
    'fill ${from.x} ${from.y} ${from.z} ${to.x} ${to.y} ${to.z} $block',
    changedBlock,
    retryWhile: positionNotLoaded,
  );

  /// Force-loads a chunk column, so a scenario can be built without a player standing in it.
  Future<void> forceload(int chunkX, int chunkZ) =>
      until('forceload add $chunkX $chunkZ', forceLoaded);

  /// Everything the server printed while [command] ran, its own reply included.
  ///
  /// The window is closed by the [sync] barrier, so the returned lines are that command's answer —
  /// this is how the harness reads a fact out of a server instead of guessing it.
  Future<List<String>> outputOf(String command) async {
    final from = server.logLines.length;
    log?.call('${server.label}: $command');
    await server.command(command);
    await tick();
    // The barrier is a *second* command (`/list`), whose own reply says everything typed before it
    // has been dispatched — the reply to `command` itself says nothing of the sort, which is why
    // waiting for one here would hang until the timeout.
    final barrier = server.logLines.length;
    await server.command(syncCommand);
    await server.waitForOutput(syncReply, from: barrier, timeout: timeout);
    return [
      for (final line in server.logLines.sublist(from))
        if (!syncReply.hasMatch(line)) line,
    ];
  }

  /// The block position a connected client's player is standing at, as the *server* sees it.
  ///
  /// A scenario has to run where the client is: both servers only tell a client about the chunks it
  /// tracks (and, for entities, the range it is within), and a console `tp` does not move that
  /// tracking — so the position is read from the server, with the vanilla reply's own label
  /// (`has the following entity data:`) as the anchor of the numbers.
  Future<TracePos> playerPosition(String name) async {
    final reply = await outputOf('data get entity $name Pos');
    final text = reply.join('\n');
    final label = text.indexOf('entity data');
    if (label < 0) {
      throw StateError(
        'could not read the position of $name; the server answered: $text',
      );
    }
    final numbers = RegExp(r'-?\d+(?:\.\d+)?')
        .allMatches(text.substring(label))
        .map((match) => double.parse(match.group(0)!))
        .toList();
    if (numbers.length < 3) {
      throw StateError(
        'could not read the position of $name; the server answered: $text',
      );
    }
    return TracePos(numbers[0].floor(), numbers[1].floor(), numbers[2].floor());
  }

  /// What a block *is* on the server, per the server's own registry — the ground truth a trace's
  /// block-state ids cannot carry across servers.
  Future<String> blockAt(TracePos pos) async {
    final reply = await outputOf(
      'data get block ${pos.x} ${pos.y} ${pos.z}',
    );
    return reply.join(' | ');
  }
}

/// The Pumpkin arm: the harness's own [PumpkinServer] behind [GameServer].
///
/// Everything Pumpkin-specific — the scratch config, the plugin component, the packet trace it
/// writes for itself — stays in `pumpkin_server.dart`; this only makes it drivable side by side with
/// a Java server.
final class PumpkinArm implements GameServer {
  PumpkinArm._(this._server);

  final PumpkinServer _server;

  static Future<PumpkinArm> start({
    required HarnessPaths paths,
    String? pluginName = 'create',
  }) async {
    final unavailable = paths.unavailable;
    if (unavailable != null) {
      throw StateError('the Pumpkin arm cannot start: $unavailable');
    }
    return PumpkinArm._(
      await PumpkinServer.start(paths: paths, pluginName: pluginName),
    );
  }

  /// The wrapper's own server, for the trace it writes about what it enqueued.
  PumpkinServer get server => _server;

  @override
  String get label => 'pumpkin';

  @override
  int get port => _server.port;

  @override
  Directory get scratch => _server.scratch;

  @override
  List<String> get logLines => _server.logLines;

  @override
  String logText() => _server.logText();

  @override
  bool get isRunning => _server.isRunning;

  @override
  Future<void> command(String line) => _server.command(line);

  @override
  Future<void> waitForOutput(
    Pattern pattern, {
    int from = 0,
    Duration? timeout,
  }) => _server.waitForOutput(pattern, from: from, timeout: timeout);

  @override
  Future<void> stop() => _server.stop();

  /// Stops the server and removes its scratch directory unless the harness was asked to keep it.
  Future<void> dispose() => _server.dispose();
}

/// A NeoForge dedicated server, built from an existing install's jars in a scratch directory.
///
/// The install is only *read* (`libraries/` and `mods/` are symlinked), so a user's own server can
/// be the source of the mods without being disturbed: the run gets its own port, its own world, its
/// own configs and its own logs.
final class JavaNeoForgeServer implements GameServer {
  JavaNeoForgeServer._(this._process, this.scratch, this.port, this._logFile);

  final Process _process;
  final File _logFile;
  final Completer<void> _ready = Completer<void>();
  final List<({Pattern pattern, int from, Completer<void> completer})> _waiters =
      [];

  @override
  final Directory scratch;

  @override
  final int port;

  /// Every line the server printed, ANSI escapes stripped.
  @override
  final List<String> logLines = [];

  final StringBuffer _all = StringBuffer();
  bool _running = true;

  static final RegExp _ansi = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

  /// The line a booted server writes (`Done (2.469s)! For help, type "help"`).
  static final RegExp readyLine = RegExp(r'Done \(');

  /// The line that says the Create mod is loaded — the Java arm is only the *reference* if it is.
  static final RegExp createModLine = RegExp(r'\bCreate \S+ \(create\)');

  /// A boot that failed: a port clash, a mod that will not load, or a JVM that refused.
  static final RegExp fatalLine = RegExp(
    r'Failed to start the minecraft server|already in use|Failed to initialize|Exception in thread "main"',
  );

  @override
  String get label => 'java';

  @override
  bool get isRunning => _running;

  /// The server's own log on disk, kept next to the world for a post-mortem.
  File get logFile => _logFile;

  /// Boots an install at [install] (`libraries/` + `mods/`, as a NeoForge server installer leaves
  /// it; `~/Documents/mctesting` is one).
  static Future<JavaNeoForgeServer> start({
    required Directory install,
    int? port,
    int seed = 20261020,
    Duration startup = const Duration(minutes: 6),
    String javaBin = 'java',
    String maxHeap = '3G',
  }) async {
    final libraries = Directory(joinPath(install.path, 'libraries'));
    final mods = Directory(joinPath(install.path, 'mods'));
    if (!libraries.existsSync()) {
      throw StateError('no NeoForge libraries in ${install.path}');
    }
    if (!mods.existsSync()) {
      throw StateError('no mods/ in ${install.path}');
    }
    final argsFile = _findArgsFile(libraries);
    if (argsFile == null) {
      throw StateError(
        'no `unix_args.txt` under ${libraries.path}/net/neoforged/neoforge/*: '
        'the install does not look like a NeoForge server',
      );
    }

    final scratch = Directory.systemTemp.createTempSync('java-diff-');
    Link(joinPath(scratch.path, 'libraries')).createSync(libraries.path);
    Link(joinPath(scratch.path, 'mods')).createSync(mods.path);
    File(joinPath(scratch.path, 'eula.txt')).writeAsStringSync('eula=true\n');

    final boundPort = port ?? await freePort();
    File(
      joinPath(scratch.path, 'server.properties'),
    ).writeAsStringSync(_properties(boundPort, seed));

    final logFile = File(joinPath(scratch.path, 'server.log'));
    final process = await Process.start(
      javaBin,
      [
        '-Xmx$maxHeap',
        // The install's own argument file already carries the classpath and the module exports;
        // everything in it is relative, which is why the scratch directory symlinks `libraries`.
        '@libraries/${_relativeArgsPath(argsFile)}',
        '--nogui',
      ],
      workingDirectory: scratch.path,
    );
    final server = JavaNeoForgeServer._(process, scratch, boundPort, logFile);
    server._pump(process.stdout);
    server._pump(process.stderr);
    await server._awaitReady(startup);
    return server;
  }

  /// The `unix_args.txt` of the newest loader version in the install.
  static File? _findArgsFile(Directory libraries) {
    final loaderRoot = Directory(
      joinPath(joinPath(joinPath(libraries.path, 'net'), 'neoforged'), 'neoforge'),
    );
    if (!loaderRoot.existsSync()) return null;
    final versions = loaderRoot.listSync().whereType<Directory>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final version in versions) {
      final args = File(joinPath(version.path, 'unix_args.txt'));
      if (args.existsSync()) return args;
    }
    return null;
  }

  static String _relativeArgsPath(File argsFile) {
    final parts = argsFile.path.split(Platform.pathSeparator);
    final loader = parts.indexOf('libraries');
    return parts.sublist(loader + 1).join('/');
  }

  /// The server's configuration: a fresh deterministic world, offline (a headless client cannot
  /// authenticate), and nothing else listening.
  static String _properties(int port, int seed) => '''
# Written by the Dart differential harness (test/support/differential/game_server.dart).
server-port=$port
server-ip=127.0.0.1
online-mode=false
enforce-secure-profile=false
white-list=false
enable-rcon=false
enable-query=false
level-name=world
level-seed=$seed
level-type=minecraft\\:normal
gamemode=creative
spawn-protection=0
allow-flight=true
view-distance=8
simulation-distance=8
entity-broadcast-range-percentage=100
max-players=20
sync-chunk-writes=false
difficulty=easy
# A server that pauses when nobody is online serves no logins: the differential boots a server and
# then joins it, so the world must keep running while the client connects.
pause-when-empty-seconds=0
motd=mctrace differential
''';

  void _pump(Stream<List<int>> stream) {
    stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            final clean = line.replaceAll(_ansi, '');
            logLines.add(clean);
            _all.writeln(clean);
            if (!_ready.isCompleted) {
              if (fatalLine.hasMatch(clean)) {
                _ready.completeError(
                  StateError('the Java server failed to start: $clean'),
                );
              } else if (readyLine.hasMatch(clean)) {
                _ready.complete();
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
            if (!_ready.isCompleted) {
              _ready.completeError(
                StateError('the Java server exited before it was ready'),
              );
            }
          },
        );
  }

  Future<void> _awaitReady(Duration timeout) async {
    try {
      await _ready.future.timeout(
        timeout,
        onTimeout: () => throw StateError(
          'the Java server was not ready within ${timeout.inMinutes} min:\n${logText()}',
        ),
      );
    } on Object {
      await stop();
      rethrow;
    }
    if (!logLines.any(createModLine.hasMatch)) {
      await stop();
      throw StateError(
        'the Java server started without the Create mod, so it is not a reference for this '
        'scenario:\n${logText()}',
      );
    }
  }

  @override
  String logText() => _all.toString();

  @override
  Future<void> command(String line) async {
    if (!_running) {
      throw StateError('the Java server is not running; cannot run `$line`');
    }
    _process.stdin.write('$line\n');
    await _process.stdin.flush();
  }

  @override
  Future<void> waitForOutput(
    Pattern pattern, {
    int from = 0,
    Duration? timeout,
  }) async {
    for (var i = from; i < logLines.length; i++) {
      if (pattern.allMatches(logLines[i]).isNotEmpty) return;
    }
    final completer = Completer<void>();
    _waiters.add((pattern: pattern, from: from, completer: completer));
    await completer.future.timeout(
      timeout ?? const Duration(seconds: 60),
      onTimeout: () => throw StateError(
        'the Java server never printed anything matching $pattern:\n'
        '${logLines.skip(from).join('\n')}',
      ),
    );
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      _process.stdin.write('stop\n');
      await _process.stdin.flush();
    } on Object {
      // The process may already be gone; the wait below decides.
    }
    try {
      await _process.exitCode.timeout(const Duration(seconds: 90));
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

  /// Stops the server and writes its console output next to the world, unless it is kept.
  Future<void> dispose({bool keep = false}) async {
    await stop();
    try {
      _logFile.writeAsStringSync(logText());
    } on FileSystemException {
      // Nothing to write into.
    }
    if (keep) return;
    try {
      scratch.deleteSync(recursive: true);
    } on FileSystemException {
      // A leftover directory is not worth failing over.
    }
  }
}

/// A free port on the loopback interface (never a port somebody else is listening on).
Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}