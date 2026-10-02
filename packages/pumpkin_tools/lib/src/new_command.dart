import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

/// Where `pumpkin new` points generated projects at, until the packages are
/// published on pub.dev.
const _repository = 'https://github.com/EricApostal/pumpkin-api-dart';

/// `pumpkin new <name>`: scaffolds a new plugin package.
final class NewCommand extends Command<int> {
  @override
  String get name => 'new';

  @override
  String get description => 'Creates a new Pumpkin plugin package.';

  @override
  String get invocation => 'pumpkin new <name>';

  @override
  Future<int> run() async {
    final name = switch (argResults!.rest) {
      [final name] => name,
      _ => usageException('Expected the name of the plugin to create.'),
    };
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      usageException(
        '"$name" is not a valid package name. Use lowercase letters, digits '
        'and underscores, starting with a letter.',
      );
    }

    final directory = Directory(name);
    if (directory.existsSync()) {
      stderr.writeln('${directory.path} already exists.');
      return 73;
    }

    final files = {
      'pubspec.yaml': _pubspec(name),
      'bin/main.dart': _main(name),
      'analysis_options.yaml': 'include: package:lints/recommended.yaml\n',
      '.gitignore': '.dart_tool/\nbuild/\n',
      'README.md': _readme(name),
    };
    for (final MapEntry(:key, :value) in files.entries) {
      final file = File(p.join(directory.path, key));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(value);
    }

    print('Created $name/. Next:');
    print('  cd $name');
    print('  dart pub get');
    print('  pumpkin build');
    return 0;
  }

  static String _pubspec(String name) => '''
name: $name
description: A Pumpkin plugin written in Dart.
publish_to: none

environment:
  sdk: ^3.13.0-0

dependencies:
  pumpkin_api:
    git:
      url: $_repository
      path: packages/pumpkin_api

dev_dependencies:
  lints: ^6.1.0

# Remove these once the packages are published on pub.dev.
dependency_overrides:
  wasm_components:
    git:
      url: $_repository
      path: packages/wasm_components
  wasm_tools:
    git:
      url: $_repository
      path: packages/wasm_tools
''';

  static String _main(String name) => '''
import 'package:pumpkin_api/pumpkin_api.dart';

void main() => runPlugin(MyPlugin());

final class MyPlugin extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(
    name: '$name',
    version: '0.1.0',
    description: 'A Pumpkin plugin written in Dart.',
  );

  @override
  void onLoad(Context context) {
    logger.info('$name loaded!');

    context.listen(Events.playerJoin, (server, event) {
      logger.info('\${event.player.getName()} joined the server');
    });
  }
}
''';

  static String _readme(String name) => '''
# $name

A [Pumpkin](https://github.com/Pumpkin-MC/Pumpkin) plugin written in Dart.

```sh
dart pub get
pumpkin build
```

Then copy `build/$name.wasm` into your server's `plugins/` directory.
''';
}
