import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wasm_tools/wasm_tools.dart';
import 'package:yaml/yaml.dart';

/// Thrown when the plugin's own `pubspec.yaml` declares core modules that
/// cannot be linked.
final class CoreModuleDeclarationError implements Exception {
  final String message;

  CoreModuleDeclarationError(this.message);

  @override
  String toString() => 'Invalid core module declaration: $message';
}

/// The core WebAssembly modules the package owning [entrypoint] declares, in
/// the order its `pubspec.yaml` lists them.
///
/// ```yaml
/// pumpkin:
///   core_modules:
///     - name: jolt
///       path: native/jolt/jolt.wasm
/// ```
///
/// `name` is the module Dart imports as (`@pragma('wasm:import', 'jolt.…')`,
/// including its `memory`), and `path` is relative to the package root.
///
/// This must not be a build hook: a hook of package A also runs while a
/// package that depends on A is built, so a hook's core module is linked into
/// the dependents' components too, where nothing imports it (`dart2wasm`
/// compiles the import away) and the link fails with `Expected compiled app to
/// export {host_call}`. Reading the built package's own pubspec reaches only
/// its own component.
///
/// Throws [CoreModuleDeclarationError] when the block is malformed or names a
/// file that does not exist.
List<CoreModuleInput> readCoreModules(File entrypoint) {
  final root = packageRootOf(entrypoint);
  final pubspec = File(p.join(root.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return const [];
  final parsed = loadYaml(pubspec.readAsStringSync());
  if (parsed is! YamlMap) {
    throw CoreModuleDeclarationError('${pubspec.path} is not a map.');
  }
  final pumpkin = parsed['pumpkin'];
  if (pumpkin == null) return const [];
  if (pumpkin is! YamlMap) {
    throw CoreModuleDeclarationError(
      'Expected `pumpkin` in ${pubspec.path} to be a map, found `$pumpkin`.',
    );
  }
  final modules = pumpkin['core_modules'];
  if (modules == null) return const [];
  if (modules is! YamlList) {
    throw CoreModuleDeclarationError(
      'Expected `pumpkin.core_modules` in ${pubspec.path} to be a list, found '
      '`$modules`.',
    );
  }
  return [
    for (final entry in modules) _coreModule(root, pubspec, modules, entry),
  ];
}

/// The package root of [entrypoint]: the nearest ancestor directory holding a
/// `pubspec.yaml`.
///
/// Falls back to the entrypoint's own directory when there is none, so a file
/// compiled outside a package simply declares no core modules.
Directory packageRootOf(File entrypoint) {
  final entrypointDir = entrypoint.absolute.parent;
  for (var dir = entrypointDir;;) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) return entrypointDir;
    dir = parent;
  }
}

CoreModuleInput _coreModule(
  Directory root,
  File pubspec,
  YamlList modules,
  Object? entry,
) {
  if (entry is! YamlMap) {
    throw CoreModuleDeclarationError(
      'Expected each `pumpkin.core_modules` entry in ${pubspec.path} to be a '
      'map of `name` and `path`, found `$entry` in `$modules`.',
    );
  }
  final name = entry['name'];
  final path = entry['path'];
  if (name is! String || name.isEmpty) {
    throw CoreModuleDeclarationError(
      'Expected `name` in ${pubspec.path} to be the non-empty module name Dart '
      'imports from, found `$name` in `$entry`.',
    );
  }
  if (path is! String || path.isEmpty) {
    throw CoreModuleDeclarationError(
      'Expected `path` in ${pubspec.path} to be the module file, relative to '
      'the package root, found `$path` in `$entry`.',
    );
  }
  final file = File(p.normalize(p.join(root.path, path)));
  if (!file.existsSync()) {
    throw CoreModuleDeclarationError('Core module $path does not exist.');
  }
  return CoreModuleInput(name, file);
}