// The Java arm on its own: a real NeoForge dedicated server, built from an install this machine
// already has, driven over its own console.
//
// This is the half of the differential that does not need a client, and it is the half that had no
// automation before: an existing NeoForge install (its `libraries/` and `mods/`, symlinked, so the
// install is only read) plus a scratch directory with its own `server.properties` is enough to have
// the *Java mod* answering the same console commands the plugin answers — which is what makes the
// comparison of the two servers' traffic possible at all.
//
// It is off unless `PUMPKIN_E2E=1`, like the rest of `test/e2e/`, and it skips with a reason when
// there is no install to boot (see `README.md`, "Differential against a Java server").

@Tags(['e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'package:test/test.dart';

import '../support/differential/game_server.dart';
import '../support/differential/differential_run.dart';
import '../support/pumpkin_lab.dart';
import '../support/pumpkin_trace.dart';

void main() {
  group('the Java arm', () {
    test('boots a dedicated server from an install and answers the console', () async {
      final environment = DifferentialEnvironment.resolve();
      JavaNeoForgeServer? server;
      addTearDown(() => server?.dispose());

      server = await JavaNeoForgeServer.start(
        install: environment.javaInstall!,
      );
      expect(server.isRunning, isTrue);
      // `JavaNeoForgeServer.start` only returns once the server is booted *and* the Create mod is in
      // it: without the mod there is no reference to compare against.
      expect(
        server.logLines.any(JavaNeoForgeServer.createModLine.hasMatch),
        isTrue,
        reason: 'the log should name the Create mod:\n${server.logText()}',
      );

      final console = ConsoleSession(server);

      // The barrier itself: `/list` answers on a server nobody has joined.
      await console.run(ConsoleSession.syncCommand, ConsoleSession.syncReply);

      // A force-load, then a block write in that chunk — the two console moves the contraption
      // scenario needs, with the replies the scenario waits for.
      await console.forceload(0, 0);
      await console.placeBlock(const TracePos(0, 64, 0), 'minecraft:stone');
      expect(
        await console.blockAt(const TracePos(0, 64, 0)),
        contains('minecraft:stone'),
        reason: 'the server should report the block it was just told to place',
      );

      // A player that is not there is a loud failure, not an empty position: the scenario reads the
      // client's position from the server, and a silent zero would build the rig in the wrong place.
      await expectLater(
        console.playerPosition('Nobody'),
        throwsA(isA<StateError>()),
      );
    });
  }, skip: _skipReason());
}

String? _skipReason() {
  final reason = PumpkinLab.skipReason();
  if (reason != null && !PumpkinLab.enabled) return reason;
  final environment = DifferentialEnvironment.resolve();
  return environment.javaUnavailable();
}