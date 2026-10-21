// A simulated client: the headless client of `tools/pumpkin-tester`, in its `client` mode.
//
// Dart cannot speak the Minecraft protocol, and a server-side trace can never by itself say what a
// client *received* — so the client is a process of its own, driven by the same suite:
//
//   pumpkin-tester client --addr 127.0.0.1:<port> --name <A> --trace <path> [--neoforge]
//
// It joins, records every packet it receives as one JSON line (the shape of
// `pumpkin_trace.dart`, plus `"dir":"recv"`, with the bundle delimiters as lines of their own), and
// stays until its stdin closes. Spawning it is also how the suite controls *when* a client joins,
// which is what the relogin diff is built on.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pumpkin_server.dart';
import 'pumpkin_trace.dart';

/// The first line of [file] that is not a JSON object, for a failure message.
String _firstBadLine(File file, FormatException error) {
  final text = file.existsSync() ? file.readAsStringSync() : '';
  for (final line in const LineSplitter().convert(text)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    try {
      if (jsonDecode(trimmed) is! Map<String, Object?>) return line;
    } on FormatException {
      return line;
    }
  }
  return error.message;
}

/// One simulated client connected to a running server.
final class TestClient {
  TestClient._(this._process, this.name, this.traceFile);

  final Process _process;

  /// The name the client joined with, as the server sees it.
  final String name;

  /// The client-side trace: what this client received.
  final File traceFile;

  /// Everything the client process printed, for a failure message.
  final StringBuffer output = StringBuffer();

  bool _running = true;

  /// Spawns a client and waits until its trace shows it is in the world.
  ///
  /// [ready] decides when the client counts as joined; the default is "the server sent it a chunk",
  /// which is a fact about the received stream, not a delay.
  static Future<TestClient> connect({
    required HarnessPaths paths,
    required int port,
    required String name,
    required Directory scratch,
    bool neoforge = false,
    bool Function(PumpkinTrace trace)? ready,
    Duration? timeout,
  }) async {
    final tester = paths.testerBinary;
    if (tester == null) {
      throw StateError(
        'no `pumpkin-tester` binary: set PUMPKIN_TESTER_BIN to one with its `client` mode built',
      );
    }
    final traceFile = File(
      joinPath(scratch.path, 'client-$name.trace.jsonl'),
    );
    final process = await Process.start(tester, [
      'client',
      '--addr',
      '127.0.0.1:$port',
      '--name',
      name,
      '--trace',
      traceFile.absolute.path,
      if (neoforge) '--neoforge',
    ]);
    final client = TestClient._(process, name, traceFile);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(client.output.writeln);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(client.output.writeln);
    await client.joined(
      ready: ready,
      timeout: timeout ?? Duration(
        seconds:
            int.tryParse(HarnessPaths.readEnv(['PUMPKIN_E2E_JOIN_SECONDS']) ?? '') ??
            60,
      ),
    );
    return client;
  }

  /// Waits until the client's own trace shows the state [ready] describes.
  ///
  /// This tails the trace file the client is writing, and gives up as soon as the client process
  /// exits (a client that never joins has to fail loudly, not hang the suite).
  Future<void> joined({
    bool Function(PumpkinTrace trace)? ready,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final isReady = ready ?? (PumpkinTrace trace) => trace.chunks.isNotEmpty;
    final deadline = DateTime.now().add(timeout);
    var exited = false;
    unawaited(
      _process.exitCode.then((code) {
        exited = true;
        output.writeln('[client $name exited with $code]');
      }),
    );
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (traceFile.existsSync()) {
          final trace = PumpkinTrace.readWhileWriting(traceFile);
          if (isReady(trace)) return;
        }
      } on FormatException catch (error) {
        // A trace that is not readable is a fault of whoever wrote it, not of the test: say so
        // with the line that broke instead of letting the exception read as a test bug.
        throw StateError(
          'the trace of client $name is not readable (${error.message}):\n'
          '${_firstBadLine(traceFile, error)}\n'
          'its output:\n${output.toString()}',
        );
      }
      if (exited) {
        throw StateError(
          'client $name exited before it joined:\n${output.toString()}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError(
      'client $name did not join within ${timeout.inSeconds}s\n'
      'its trace: ${traceFile.existsSync() ? PumpkinTrace.readWhileWriting(traceFile).describe() : '<none>'}\n'
      'its output:\n${output.toString()}',
    );
  }

  /// What this client has received so far (safe to call while it is still connected).
  PumpkinTrace readTrace() => PumpkinTrace.readWhileWriting(traceFile);

  bool get isRunning => _running;

  /// Disconnects: closing stdin is the client's own "stop", which lets it exit cleanly.
  Future<void> stop({Duration timeout = const Duration(seconds: 20)}) async {
    if (!_running) return;
    _running = false;
    try {
      await _process.stdin.close();
    } on Object {
      // Already closed.
    }
    try {
      await _process.exitCode.timeout(timeout);
    } on TimeoutException {
      _process.kill(ProcessSignal.sigterm);
      try {
        await _process.exitCode.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        _process.kill(ProcessSignal.sigkill);
        await _process.exitCode;
      }
    }
    // The client's own output (its summary line, its join errors) next to its trace, so a failure
    // is diagnosable from the kept run directory alone.
    try {
      File(
        joinPath(traceFile.parent.path, 'client-$name.log'),
      ).writeAsStringSync(output.toString());
    } on FileSystemException {
      // Nothing to write into (the directory is already gone).
    }
  }
}