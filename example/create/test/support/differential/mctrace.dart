// The recording TCP proxy: the only piece that can capture what a *Java* server puts on the wire.
//
// The plugin server can write down what it enqueued (`PUMPKIN_PACKET_TRACE`), but a NeoForge server
// cannot without a mod of its own — and the whole question here is what the two servers actually
// send. So a client connects through `mctrace`, which forwards both directions and writes one line
// per frame:
//
//   {"c":0,"dir":"c2s"|"s2c","t":<ms since the proxy started>,"id":<leading VarInt|null>,
//    "len":<frame length>,"data":"<hex of the whole frame, id included>"}
//
// `c` is the connection index, so a relogin is visible as a second connection rather than as one
// confusing stream.
//
// The proxy is deliberately not required: without the binary the differential still runs on the two
// clients' own traces, and says so. With it, two things are added — the *raw* evidence (frame
// counts and bytes per direction, which no decoder normalises away) and, through
// `mctrace decode --trace <file> [--dir s2c]`, a second semantic view of the same stream produced
// from the proxy's frames by the same decoder the client uses, which the differential cross-checks
// the client's own trace against.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../pumpkin_server.dart';
import '../pumpkin_trace.dart';
import 'game_server.dart' show freePort;

/// One captured frame.
final class ProxyFrame {
  ProxyFrame({
    required this.connection,
    required this.direction,
    required this.timeMillis,
    required this.id,
    required this.length,
    required this.data,
  });

  /// Which connection the frame belonged to (0 is the first).
  final int connection;

  /// `c2s` or `s2c`.
  final String direction;

  /// Milliseconds since the proxy started.
  final int timeMillis;

  /// The leading VarInt of the frame, decoded for convenience — not the packet id once the
  /// connection is compressed (a compressed frame starts with its uncompressed *length*, and the
  /// id is inside the zlib bytes), which is what `mctrace decode` exists for. Null when the frame
  /// had no VarInt at all.
  final int? id;

  /// The frame length on the wire.
  final int length;

  /// The frame's bytes exactly as they crossed the socket, id included.
  final List<int> data;

  bool get serverToClient => direction == 's2c';

  @override
  String toString() =>
      '[$connection $direction +${timeMillis}ms id=$id len=$length]';
}

/// `mctrace`, the recording proxy, in front of one server.
final class MctraceProxy {
  MctraceProxy._(this._process, this.port, this.capture, this._binary);

  final Process _process;
  final String _binary;

  /// The port a client connects to (the proxy's `--listen`).
  final int port;

  /// Where the frames are written.
  final File capture;

  final StringBuffer _output = StringBuffer();
  bool _running = true;

  /// The proxy binary, if one can be found.
  ///
  /// `MCTRACE_BIN` first, then next to the tester binary (both come out of the same build), so a
  /// checkout that built `pumpkin-tester` also has the proxy when it exists.
  static String? resolveBinary({String? testerBinary}) {
    final explicit = HarnessPaths.readEnv(['MCTRACE_BIN', 'PUMPKIN_MCTRACE_BIN']);
    if (explicit != null && File(explicit).existsSync()) return explicit;
    if (testerBinary != null) {
      final sibling = joinPath(
        File(testerBinary).parent.path,
        Platform.isWindows ? 'mctrace.exe' : 'mctrace',
      );
      if (File(sibling).existsSync()) return sibling;
    }
    return null;
  }

  /// Starts the proxy in front of `127.0.0.1:<upstreamPort>` and waits until it listens.
  static Future<MctraceProxy> start({
    required int upstreamPort,
    required File capture,
    required String binary,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final listen = await freePort();
    capture.parent.createSync(recursive: true);
    if (capture.existsSync()) capture.deleteSync();
    final process = await Process.start(binary, [
      '--listen',
      '127.0.0.1:$listen',
      '--upstream',
      '127.0.0.1:$upstreamPort',
      '--out',
      capture.absolute.path,
    ]);
    final proxy = MctraceProxy._(process, listen, capture, binary);
    proxy._output.write('mctrace --listen 127.0.0.1:$listen '
        '--upstream 127.0.0.1:$upstreamPort --out ${capture.path}\n');
    process.stdout
        .transform(utf8.decoder)
        .listen((chunk) => proxy._output.write(chunk));
    process.stderr
        .transform(utf8.decoder)
        .listen((chunk) => proxy._output.write(chunk));
    process.exitCode.then((code) {
      proxy._running = false;
      proxy._output.write('mctrace exited with $code\n');
    });
    // The listen socket is the proxy's contract with the runner: a client may connect the moment it
    // is there, and before it is there a connection would be refused.
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!proxy._running) {
        throw StateError('mctrace exited before it listened:\n${proxy._output}');
      }
      if (await _isListening(listen)) return proxy;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await proxy.stop();
    throw StateError('mctrace never listened on $listen:\n${proxy._output}');
  }

  /// What the proxy printed, for a failure message.
  String get output => _output.toString();

  /// Every frame captured so far (`readWhileWriting` semantics: a trailing half-written line is
  /// dropped, a malformed one is an error).
  List<ProxyFrame> frames() {
    if (!capture.existsSync()) return const [];
    final frames = <ProxyFrame>[];
    final text = capture.readAsStringSync();
    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(trimmed);
      } on FormatException {
        // A line the proxy was still writing; it is the last one, so stop here.
        break;
      }
      if (decoded is! Map<String, Object?>) break;
      frames.add(_frame(decoded));
    }
    return frames;
  }

  static ProxyFrame _frame(Map<String, Object?> line) {
    final hex = (line['data'] as String?) ?? '';
    final bytes = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return ProxyFrame(
      connection: (line['c'] as num?)?.toInt() ?? 0,
      direction: (line['dir'] as String?) ?? '?',
      timeMillis: (line['t'] as num?)?.toInt() ?? 0,
      id: (line['id'] as num?)?.toInt(),
      length: (line['len'] as num?)?.toInt() ?? bytes.length,
      data: bytes,
    );
  }

  /// What the proxy saw, as a sentence for the report.
  String get summary {
    final captured = frames();
    if (captured.isEmpty) return 'mctrace: no frames';
    final toClient = captured.where((frame) => frame.serverToClient).toList();
    final toServer = captured.where((frame) => !frame.serverToClient).toList();
    final bytes = captured.fold<int>(0, (sum, frame) => sum + frame.length);
    return 'mctrace: ${captured.length} frames ($bytes B) — '
        '${toClient.length} to the client, ${toServer.length} to the server, '
        '${captured.map((f) => f.connection).toSet().length} connection(s)';
  }

  /// The proxy's own semantic view of one direction, decoded by the same decoder the client uses.
  ///
  /// This is a *second* reading of the same stream: the client's trace says what the client made of
  /// the bytes, the proxy says what was on the wire, and the differential comparing both is how a
  /// packet the client's decoder quietly tolerates stops being invisible.
  Future<PumpkinTrace> decoded({
    String direction = 's2c',
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final result = await Process.run(_binary, [
      'decode',
      '--trace',
      capture.absolute.path,
      '--dir',
      direction,
    ]).timeout(timeout);
    if (result.exitCode != 0) {
      throw StateError(
        'mctrace decode failed (${result.exitCode}): ${result.stderr}',
      );
    }
    return PumpkinTrace.parse(
      result.stdout as String,
      source: '${capture.path} ($direction)',
    );
  }

  bool get isRunning => _running;

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _process.kill(ProcessSignal.sigterm);
    try {
      await _process.exitCode.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
      await _process.exitCode;
    }
  }
}

/// Whether something is listening on `127.0.0.1:[port]`.
///
/// The check is a *bind*, not a connect: connecting to the proxy would make it open an upstream
/// connection of its own, which the capture would then report as a connection that was never a
/// client — and the bot's connection would no longer be the first one. A port that a listener holds
/// cannot be bound again, and nothing is opened by trying.
Future<bool> _isListening(int port) async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await socket.close();
    return false;
  } on SocketException {
    return true;
  }
}