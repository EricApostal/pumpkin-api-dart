// Writes the payload channel set a client that has Create and the Create-family
// mods (Sable, Simulated, Aeronautics, Offroad) answers the server's
// `neoforge:register` query with, in the format `pumpkin-tester client --query`
// takes. NeoForge's own registrations are added by the bot, so they are not in
// the file.
//
//   dart run tool/dump_client_channels.dart [--out <file>]
//
// Create's channels come from the same registration the plugin declares
// (`registerPayloadChannels`); the addons' come from the port inventory's channel
// table, `docs/aero-port-manifest.json`. The inventory is a snapshot of the Java
// mods, not of this repository, so this tool stays usable without the addon
// packages: a client that has the mods announces exactly what the Java mods
// register, and the tables in the addon packages are checked against the same
// file by `test/compat_negotiation_test.dart`.
import 'dart:convert';
import 'dart:io';

import 'package:create/src/core/payload.dart';
import 'package:create/src/protocol/codec_compiler.dart';
import 'package:create/src/protocol/payload_hub.dart';

final class _Player {
  const _Player();
}

void main(List<String> args) {
  var out = '/tmp/client_channels.json';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--out' && i + 1 < args.length) out = args[++i];
  }

  final payloads = PayloadRegistry<_Player>();
  final hub = PayloadHub<_Player>(
    schemas: PayloadSchemas.manifest,
    sink: (level, message) => stderr.writeln('${level.name}: $message'),
    describePlayer: (p) => 'player',
  );
  registerPayloadChannels<_Player>(payloads, hub);

  final manifest = jsonDecode(File('../../docs/aero-port-manifest.json').readAsStringSync()) as Map<String, Object?>;

  final channels = <Map<String, Object?>>[
    for (final payload in payloads.declared)
      {
        'id': payload.id,
        'version': payload.version,
        'phase': 'play',
        'flow': payload.serverbound ? 'serverbound' : 'clientbound',
        'optional': payload.optional,
      },
    for (final channel in (manifest['channels']! as List<Object?>).cast<Map<String, Object?>>())
      {
        'id': channel['id'],
        'version': channel['version'],
        'phase': channel['phase'],
        'flow': channel['flow'],
        'optional': channel['optional'],
      },
  ];

  final file = File(out);
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({'channels': channels})}\n');
  final flows = <String, int>{};
  for (final channel in channels) {
    final flow = channel['flow']! as String;
    flows[flow] = (flows[flow] ?? 0) + 1;
  }
  stdout.writeln('${channels.length} channel(s) -> ${file.path}: $flows');
}
