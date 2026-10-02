import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:wasm_tools/wasm_tools.dart';
import 'package:yaml/yaml.dart';

/// `pumpkin build`: compiles the plugin in the current directory to a
/// WebAssembly component that Pumpkin can load.
final class BuildCommand extends Command<int> {
  BuildCommand() {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Where to write the plugin. Defaults to build/<package>.wasm.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Print the compiler\'s detailed progress.',
      );
  }

  @override
  String get name => 'build';

  @override
  String get description => 'Compiles a plugin to a .wasm component.';

  @override
  String get invocation => 'pumpkin build [entrypoint (default: bin/main.dart)]';

  @override
  Future<int> run() async {
    final results = argResults!;
    final entrypoint = File(switch (results.rest) {
      [] => p.join('bin', 'main.dart'),
      [final path] => path,
      _ => usageException('Expected at most one entrypoint.'),
    });
    if (!entrypoint.existsSync()) {
      stderr.writeln(
        'Could not find ${entrypoint.path}. Run this from the plugin\'s '
        'directory, or pass the entrypoint explicitly.',
      );
      return 66;
    }

    if (!_sdkSupportsStandalone()) {
      stderr.writeln(
        'Pumpkin plugins need Dart 3.14 or newer: older SDKs compile to Wasm '
        'exception instructions that the server\'s runtime rejects.\n'
        'You are running Dart ${Platform.version.split(' ').first}. Use the dev '
        'channel or Flutter master, for example with puro:\n'
        '  puro use master',
      );
      return 69;
    }

    final output = File(results.option('output') ?? _defaultOutput());
    output.parent.createSync(recursive: true);

    hierarchicalLoggingEnabled = true;
    final logger = Logger('pumpkin')
      ..level = results.flag('verbose') ? Level.ALL : Level.WARNING;
    logger.onRecord.listen((record) => stderr.writeln(record.message));

    final stopwatch = Stopwatch()..start();
    try {
      await ComponentCompiler(
        CompilerOptions(entrypoint, output),
        logger,
      ).run();
    } on CompilerFailure catch (e) {
      stderr.writeln('Build failed: ${e.message}');
      return 1;
    }

    final kib = (output.lengthSync() / 1024).toStringAsFixed(0);
    final seconds = (stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1);
    print('Built ${output.path} ($kib KiB) in ${seconds}s.');
    print('Copy it into your server\'s plugins/ directory to use it.');
    return 0;
  }

  /// Whether the running Dart SDK emits the new Wasm exception-handling
  /// instructions (`try_table`), which landed in the 3.14 development cycle.
  bool _sdkSupportsStandalone() {
    final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(Platform.version);
    if (match == null) return true; // Unknown format, let the compiler decide.
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    return major > 3 || (major == 3 && minor >= 14);
  }

  String _defaultOutput() {
    var name = 'plugin';
    final pubspec = File('pubspec.yaml');
    if (pubspec.existsSync()) {
      final parsed = loadYaml(pubspec.readAsStringSync());
      if (parsed is YamlMap && parsed['name'] is String) {
        name = parsed['name'] as String;
      }
    }
    return p.join('build', '$name.wasm');
  }
}
