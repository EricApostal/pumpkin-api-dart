// One end-to-end run: a real server, the clients joined to it, and one shutdown.
//
// A test that expresses Create-specific meaning from the client's side reads like this:
//
// ```dart
// final lab = await PumpkinLab.boot();
// addTearDown(lab.shutdown);
// final watcher = await lab.connect('Watcher');
// await lab.scenario(['forceload add -16 -16 16 16', 'setblock 4 70 0 create:fluid_tank']);
// final trace = watcher.readTrace();
// expect(trace.blockEntityAt(const TracePos(4, 70, 0)), isNotNull);
// ```
//
// The suite is off unless `PUMPKIN_E2E=1`, because it needs a built server binary and a built
// plugin component. See `example/create/README.md`.

import 'dart:io';

import 'pumpkin_client.dart';
import 'pumpkin_server.dart';
import 'pumpkin_trace.dart';

/// A server, the clients attached to it, and their traces.
final class PumpkinLab {
  PumpkinLab._(this.server, this.paths);

  final PumpkinServer server;
  final HarnessPaths paths;

  final List<TestClient> clients = [];

  /// The throwaway directory the server runs in (its world, `plugins/` and traces live there).
  Directory get scratch => server.scratch;

  /// The port the server listens on.
  int get port => server.port;

  /// Boots the server with the plugin loaded, or throws with the reason it cannot.
  static Future<PumpkinLab> boot({String? pluginName = 'create'}) async {
    final reason = skipReason();
    if (reason != null) throw StateError('the end-to-end harness is unavailable: $reason');
    final paths = HarnessPaths.resolve();
    final server = await PumpkinServer.start(paths: paths, pluginName: pluginName);
    return PumpkinLab._(server, paths);
  }

  /// Connects a simulated client called [name] and waits until it is in the world.
  Future<TestClient> connect(
    String name, {
    bool neoforge = false,
    bool Function(PumpkinTrace trace)? ready,
  }) async {
    final client = await TestClient.connect(
      paths: paths,
      port: server.port,
      name: name,
      scratch: scratch,
      neoforge: neoforge,
      ready: ready,
    );
    clients.add(client);
    return client;
  }

  /// Runs console commands in order, letting the server tick between them.
  Future<void> scenario(Iterable<String> commands) => server.scenario(commands);

  /// Where a connected client's player actually is, so a scenario can be placed next to it.
  ///
  /// The server only tells a client about the chunks it tracks, so placing the scenario anywhere
  /// else produces no packets at all — and a console `tp` does not change that (it never sends the
  /// destination's chunk), which is why this reads the position instead of moving the client.
  Future<TracePos> playerPosition(String client) =>
      server.playerPosition(client);

  /// Disconnects every client, stops the server, and removes the scratch directory.
  Future<void> shutdown() async {
    for (final client in clients.reversed) {
      await client.stop();
    }
    clients.clear();
    await server.dispose();
  }

  /// Why the end-to-end suite should be skipped, or null when it can run.
  ///
  /// The suite is slow (a first run AOT-compiles the plugin component) and needs built binaries, so
  /// `puro dart test` leaves it out: it says *why* instead of failing.
  static String? skipReason() {
    if (!enabled) {
      return 'the end-to-end suite needs a real server run: set PUMPKIN_E2E=1 '
          '(see example/create/README.md)';
    }
    return HarnessPaths.resolve().unavailable;
  }

  /// Whether `PUMPKIN_E2E` asks for the end-to-end suite.
  static bool get enabled => const ['1', 'true', 'yes']
      .contains((HarnessPaths.readEnv(['PUMPKIN_E2E']) ?? '').toLowerCase());
}