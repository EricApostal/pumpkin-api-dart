import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pumpkin_tools/src/core_modules.dart';
import 'package:test/test.dart';

/// The `pumpkin.core_modules` block of a plugin's own pubspec is what links a
/// core module into exactly that plugin's component: a build hook would also
/// run while a package depending on the plugin is built, and linking the
/// module there fails.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pumpkin-core-modules');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  void writePubspec(String contents) {
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(contents);
  }

  /// The entrypoint of the package, as the build command resolves it
  /// (`bin/main.dart`).
  File writeEntrypoint() {
    final entrypoint = File(p.join(root.path, 'bin', 'main.dart'))
      ..createSync(recursive: true);
    entrypoint.writeAsStringSync('void main() {}');
    return entrypoint;
  }

  void writeModule(String relativePath) {
    final module = File(p.join(root.path, relativePath))
      ..createSync(recursive: true);
    module.writeAsStringSync('\\0asm');
  }

  const jolt = 'name: sable\n'
      'pumpkin:\n'
      '  core_modules:\n'
      '    - name: jolt\n'
      '      path: native/jolt/jolt.wasm\n';

  test('reads the module the package declares', () {
    writePubspec(jolt);
    writeModule('native/jolt/jolt.wasm');

    final modules = readCoreModules(writeEntrypoint());

    expect(modules, hasLength(1));
    expect(modules.single.name, 'jolt');
    // The path is relative to the package root, not to the working directory
    // the build was started in.
    expect(
      modules.single.file.path,
      p.join(root.path, 'native/jolt/jolt.wasm'),
    );
    expect(modules.single.file.existsSync(), isTrue);
  });

  test('reads several modules in the declared order', () {
    writePubspec(
      'name: sable\n'
      'pumpkin:\n'
      '  core_modules:\n'
      '    - name: jolt\n'
      '      path: native/jolt/jolt.wasm\n'
      '    - name: lua\n'
      '      path: native/lua/lua.wasm\n',
    );
    writeModule('native/jolt/jolt.wasm');
    writeModule('native/lua/lua.wasm');

    final modules = readCoreModules(writeEntrypoint());

    expect(modules.map((m) => m.name), ['jolt', 'lua']);
  });

  test('accepts an absolute module path', () {
    final module = File(p.join(root.path, 'lua.wasm'))..createSync();
    module.writeAsStringSync('\\0asm');
    writePubspec(
      'name: cc_tweaked\n'
      'pumpkin:\n'
      '  core_modules:\n'
      '    - name: lua\n'
      '      path: ${module.path}\n',
    );

    expect(
      readCoreModules(writeEntrypoint()).single.file.path,
      module.path,
    );
  });

  test('returns no modules when the package declares none', () {
    writePubspec('name: create\n');
    writePubspec('name: create\ndependencies:\n  sable:\n');

    expect(readCoreModules(writeEntrypoint()), isEmpty);
  });

  test('returns no modules when there is no pubspec at all', () {
    expect(readCoreModules(writeEntrypoint()), isEmpty);
  });

  test('finds the package root from the entrypoint, not the cwd', () {
    writePubspec(jolt);
    writeModule('native/jolt/jolt.wasm');
    final nested = File(p.join(root.path, 'tool', 'deep', 'main.dart'))
      ..createSync(recursive: true);

    expect(packageRootOf(nested).path, root.path);
  });

  test('falls back to the entrypoint directory outside a package', () {
    final orphan = Directory(p.join(root.path, 'loose'))..createSync();
    final entrypoint = File(p.join(orphan.path, 'main.dart'))
      ..writeAsStringSync('void main() {}');

    expect(packageRootOf(entrypoint).path, orphan.path);
    expect(readCoreModules(entrypoint), isEmpty);
  });

  test('rejects a module file that does not exist', () {
    writePubspec(jolt);

    expect(
      () => readCoreModules(writeEntrypoint()),
      throwsA(
        isA<CoreModuleDeclarationError>().having(
          (e) => e.message,
          'message',
          contains('native/jolt/jolt.wasm does not exist'),
        ),
      ),
    );
  });

  test('rejects core_modules that is not a list', () {
    writePubspec('name: sable\npumpkin:\n  core_modules: jolt\n');

    expect(
      () => readCoreModules(writeEntrypoint()),
      throwsA(
        isA<CoreModuleDeclarationError>().having(
          (e) => e.message,
          'message',
          contains('to be a list'),
        ),
      ),
    );
  });

  test('rejects an entry without a name or a path', () {
    writePubspec(
      'name: sable\n'
      'pumpkin:\n'
      '  core_modules:\n'
      '    - path: native/jolt/jolt.wasm\n',
    );

    expect(
      () => readCoreModules(writeEntrypoint()),
      throwsA(
        isA<CoreModuleDeclarationError>().having(
          (e) => e.message,
          'message',
          contains('non-empty module name'),
        ),
      ),
    );

    writePubspec(
      'name: sable\n'
      'pumpkin:\n'
      '  core_modules:\n'
      '    - name: jolt\n',
    );

    expect(
      () => readCoreModules(writeEntrypoint()),
      throwsA(
        isA<CoreModuleDeclarationError>().having(
          (e) => e.message,
          'message',
          contains('module file, relative to'),
        ),
      ),
    );
  });

  test('rejects a pumpkin block that is not a map', () {
    writePubspec('name: sable\npumpkin: sable\n');

    expect(
      () => readCoreModules(writeEntrypoint()),
      throwsA(
        isA<CoreModuleDeclarationError>().having(
          (e) => e.message,
          'message',
          contains('`pumpkin`'),
        ),
      ),
    );
  });
}