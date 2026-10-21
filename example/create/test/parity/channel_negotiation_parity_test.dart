// Parity at the registry/channel level: a client that has Create — and nothing else — must be able
// to join both servers, and both must agree on the channels and the versions.
//
// This is the level the connection failure lived at. A `NeoForge` server declares its payload
// channels during the configuration phase, and a client whose set does not match is refused before
// it ever sees the world (`neoforge:modded_network_setup_failed` names the channels). So the test
// asks both servers the same question with the *client's* set — the channels the plugin's own
// registry declares, which are the Create mod's — and then compares the answers:
//
//  * the Java mod must accept the set (a refusal means the manifest the plugin ships is not the
//    mod's own: a missing channel, or a version/flow the mod does not use);
//  * the plugin must accept it too, and negotiate the same `channel -> version` map. A plugin that
//    declares a channel Create does not have is refused here by name — which is what makes this
//    test catch a foreign declaration instead of tolerating it.
//
// The declaration is not visible to the client's own trace (it is a configuration-phase payload),
// so the run reads it from the recording proxy's decoded frames; the test skips, with the reason,
// when `mctrace` is not available.
//
// Run it with (see example/create/README.md):
//
// ```sh
// PUMPKIN_E2E=1 PUMPKIN_BIN=<build>/pumpkin PUMPKIN_TESTER_BIN=<build>/pumpkin-tester \
//   MCTRACE_BIN=<build>/mctrace PUMPKIN_PLUGIN_WASM=build/create.wasm \
//   puro dart test test/parity/channel_negotiation_parity_test.dart
// ```

@Tags(['e2e'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../support/differential/channel_manifest.dart';
import '../support/differential/handshake.dart';
import '../support/differential/parity.dart';
import '../support/differential/scenarios.dart';

void main() {
  group('the Create declaration', () {
    test('a client with only Create\'s channels joins both servers', () async {
      final scratch = Directory.systemTemp.createTempSync('parity-channels-');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final channels = createDeclaredChannels();
      final query = writeChannelQuery(
        File('${scratch.path}/create-channels.json'),
        channels,
      );

      final report = await runParity(
        handshakeScenario(),
        clientQuery: query,
        compareTraces: false,
        log: (message) => print('  $message'),
      );

      // 1. The reference arm is the Create mod. A client that answers with the plugin's manifest
      //    must be accepted by it: a refusal here means the manifest the plugin declares is not the
      //    mod's own registration (a missing channel, or a version/flow that is not the mod's).
      final referenceRefusal = refusedChannels(report.reference.proxyTrace);
      if (referenceRefusal.isNotEmpty) {
        fail(
          'the Java mod refused a client that answered with the ${channels.length} channel(s) the '
          'plugin declares, so the manifest is not the mod\'s own registration:\n'
          '${_refusals(referenceRefusal)}\n\n${report.render(all: true)}',
        );
      }
      final reference = negotiatedChannels(report.reference.proxyTrace);
      if (reference == null) {
        fail(
          'the Java arm never negotiated the Create channel set '
          '(its client ${report.reference.failure ?? 'joined but sent no neoforge:network'})\n'
          '${report.render(all: true)}',
        );
      }
      // The bot adds `NeoForge`'s own registrations to the answer (every `NeoForge` client has
      // them, and the registry synchronisation needs three of them), so the negotiated map is the
      // channels the client answered with *plus* `NeoForge`'s. What the mod has to accept is every
      // channel the plugin declares; a `create:`/`catnip:`/`ponder:` channel missing from the map
      // is one the plugin declares and the mod does not.
      final declared = {for (final channel in channels) channel.id};
      final notNegotiated = declared.difference(reference.keys.toSet());
      expect(
        notNegotiated,
        isEmpty,
        reason:
            'the Java mod did not negotiate channel(s) the plugin declares, so they are not in the '
            'mod\'s own registration: ${notNegotiated.toList()..sort()}\n'
            '${report.render(all: true)}',
      );

      // 2. The candidate arm is the plugin. A refusal names the channels it declares on top of
      //    Create — the connection failure this level exists to catch.
      final candidateRefusal = refusedChannels(report.candidate.proxyTrace);
      if (candidateRefusal.isNotEmpty) {
        fail(
          'the plugin refused a client that has only Create\'s channels: it declares channels a '
          'Create client does not have (a client is refused when a channel is required by one side '
          'and absent on the other):\n${_refusals(candidateRefusal)}\n\n'
          '${report.render(all: true)}',
        );
      }
      final candidate = negotiatedChannels(report.candidate.proxyTrace);
      if (candidate == null) {
        fail(
          'the plugin arm never negotiated the Create channel set '
          '(its client ${report.candidate.failure ?? 'joined but sent no neoforge:network'})\n'
          '${report.render(all: true)}',
        );
      }

      // 3. The two servers agree channel by channel, with the version each one uses.
      final extra = candidate.keys.toSet().difference(reference.keys.toSet());
      final missing = reference.keys.toSet().difference(candidate.keys.toSet());
      expect(
        extra,
        isEmpty,
        reason:
            'the plugin negotiated channel(s) the Java mod does not have: '
            '${extra.join(', ')}\n${report.render(all: true)}',
      );
      expect(
        missing,
        isEmpty,
        reason:
            'the plugin did not negotiate channel(s) the Java mod has: '
            '${missing.join(', ')}\n${report.render(all: true)}',
      );
      for (final id in reference.keys) {
        expect(
          candidate[id],
          reference[id],
          reason:
              'channel $id is negotiated at version `${candidate[id]}` by the plugin and '
              '`${reference[id]}` by the Java mod',
        );
      }
    });
  }, skip: paritySkipReason(requireProxy: true));
}

/// The refusal, one channel per line, with the reason the server gave.
String _refusals(Map<String, String> refused) {
  final sorted = refused.keys.toList()..sort();
  return [
    for (final id in sorted) '  $id — ${refused[id]}',
  ].join('\n');
}
