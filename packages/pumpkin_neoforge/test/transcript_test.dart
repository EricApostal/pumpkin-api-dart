// Transcripts of what the library sends to a NeoForge client, replayed by the
// strict Python client (example/modbridge/testclient/test_neoforge_client.py).
// This test regenerates them and fails if the checked-in files are stale:
//
//   UPDATE_TRANSCRIPTS=1 puro dart test test/transcript_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:pumpkin_neoforge/lonsdaleite.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart';
import 'package:test/test.dart';

import 'support/rig.dart';

const _dir = '../../example/modbridge/testclient/transcripts';

Future<Map<String, Object?>> _record(NeoForgeNegotiation negotiation) async {
  final rig = Rig(
    lonsdaleiteSpec(),
    options: NeoForgeServerOptions(
      negotiation: negotiation,
      announceTimeout: const Duration(seconds: 2),
      queryTimeout: const Duration(seconds: 2),
      syncTimeout: const Duration(seconds: 2),
      taskTimeout: const Duration(seconds: 2),
    ),
  )..begin(preBrand: negotiation == NeoForgeNegotiation.full);
  ScriptedClient(rig);
  // The full mode talks before the brand, then the brand, then the start hold.
  var preBrand = <(String, List<int>)>[];
  if (negotiation == NeoForgeNegotiation.full) {
    await rig.runPreBrand();
    preBrand = [...rig.transport.sent];
    rig.transport.sent.clear();
    rig.toStart();
  }
  await rig.runStart();
  final start = [...rig.transport.sent];
  rig.transport.sent.clear();
  await rig.runFinish();
  final finish = [...rig.transport.sent];
  expect(rig.results.single.outcome, NeoForgeOutcome.accepted);

  Map<String, Object?> encode((String, List<int>) message) => {
    'channel': message.$1,
    // zlib + base64: the registries are large
    'z': base64Encode(zlib.encode(message.$2)),
  };
  return {
    'description':
        'Messages the pumpkin_neoforge library sends for the Lonsdaleite spec '
        '(${negotiation.name} negotiation), in order. brand: the server brand '
        'that precedes them (Pumpkin sends it before the start hold, after the '
        'pre-brand messages of the full mode).',
    'negotiation': negotiation.name,
    'brand': 'Pumpkin',
    if (negotiation == NeoForgeNegotiation.full)
      'preBrand': [for (final m in preBrand) encode(m)],
    'start': [for (final m in start) encode(m)],
    'finish': [for (final m in finish) encode(m)],
  };
}

/// The (channel, bytes) pairs of a transcript phase.
List<(String, List<int>)> _messages(Object? phase) => [
  for (final m in (phase! as List<Object?>).cast<Map<String, Object?>>())
    (m['channel']! as String, zlib.decode(base64Decode(m['z']! as String))),
];

void main() {
  for (final negotiation in NeoForgeNegotiation.values) {
    test('${negotiation.name} transcript is current', () async {
      final transcript = await _record(negotiation);
      final file = File('$_dir/lonsdaleite_${negotiation.name}.json');
      if (Platform.environment['UPDATE_TRANSCRIPTS'] == '1') {
        file.createSync(recursive: true);
        file.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(transcript)}\n',
        );
      }
      expect(
        file.existsSync(),
        isTrue,
        reason: 'missing transcript; regenerate with UPDATE_TRANSCRIPTS=1',
      );
      // Compare the decompressed messages, not the compressed text (zlib
      // output may differ between versions).
      final stored =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      for (final phase in [
        if (negotiation == NeoForgeNegotiation.full) 'preBrand',
        'start',
        'finish',
      ]) {
        final want = _messages(transcript[phase]);
        final have = _messages(stored[phase]);
        expect(
          [for (final (c, _) in have) c],
          [for (final (c, _) in want) c],
          reason: '$phase: stale transcript (UPDATE_TRANSCRIPTS=1)',
        );
        for (var i = 0; i < want.length; i++) {
          expect(
            have[i].$2,
            want[i].$2,
            reason: '$phase #$i ${want[i].$1}: stale transcript',
          );
        }
      }
    });
  }
}
