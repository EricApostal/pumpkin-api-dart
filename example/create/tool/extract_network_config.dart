// Extracts the network payload wire formats, config defaults, stress table and
// tags of the Create mod from its Java sources / generated data.
//
//   dart run tool/extract_network_config.dart [--create <repo>] [--out <dir>]
//
// Output (all in lib/src/manifest): network.g.dart, config_defaults.g.dart,
// stress.g.dart, tags.g.dart, REPORT_network.md. Only dart:io / dart:convert.
import 'dart:io';

import '../lib/src/manifest/types_network.dart';
import 'src/config_extract.dart';
import 'src/emit.dart';
import 'src/net_extract.dart';

const _defaultCreate = '/Users/eric/Documents/development/languages/java/Create';

void main(List<String> args) {
  var create = _defaultCreate;
  String? outDir;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--create') create = args[++i];
    if (args[i] == '--out') outDir = args[++i];
  }
  final scriptDir = File.fromUri(Platform.script).parent.parent.path; // example/create
  outDir ??= '$scriptDir/lib/src/manifest';
  Directory(outDir).createSync(recursive: true);

  // ---------------------------------------------------------------- network
  final net = extractNetwork(create);
  File('$outDir/network.g.dart').writeAsStringSync(emitNetwork(net.payloads));

  // ----------------------------------------------------------------- config
  final cfg = extractConfig(create);
  File('$outDir/config_defaults.g.dart').writeAsStringSync(emitConfig(cfg.entries));
  File('$outDir/stress.g.dart').writeAsStringSync(emitStress(cfg.stress, cfg.constants));

  // ------------------------------------------------------------------- tags
  final tags = extractTags(create);
  File('$outDir/tags.g.dart').writeAsStringSync(emitTags(tags.tags));

  File('$outDir/REPORT_network.md').writeAsStringSync(buildReport(net, cfg, tags));
  stdout.writeln('payloads: ${net.payloads.length} '
      '(serverbound ${net.payloads.where((p) => p.direction == NetDirection.serverbound).length}, '
      'clientbound ${net.payloads.where((p) => p.direction == NetDirection.clientbound).length}), '
      'unverified ${net.payloads.where((p) => !p.verified).length}');
  stdout.writeln('config entries: ${cfg.entries.length}, stress blocks: ${cfg.stress.length}');
  stdout.writeln('tags: ${tags.tags.length} from ${tags.fileCount} files');
}
