// Writes Simulated's channel declaration as the `--query` file
// `pumpkin-tester client` reads, so the 37 channels can be announced to a
// running server (a differential check, not part of the package).
import 'dart:convert';
import 'dart:io';

import 'package:simulated/simulated.dart';

void main(List<String> args) {
  final out = args.isEmpty ? '/tmp/sim_channels.json' : args.first;
  final channels = [
    for (final c in simChannels)
      {'id': c.id, 'version': c.version, 'phase': 'play', 'flow': c.serverbound ? 'serverbound' : 'clientbound', 'optional': c.optional},
  ];
  File(out).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({'channels': channels}));
  stdout.writeln('$out: ${channels.length} channels');
}
