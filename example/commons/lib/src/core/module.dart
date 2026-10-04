import 'package:pumpkin_api/pumpkin_api.dart';

import 'clock.dart';
import 'permissions.dart';
import 'services.dart';
import 'storage.dart';

/// A self-contained slice of the plugin: its own commands, data, messages and
/// permissions. Modules talk to each other only through [Services] (see
/// `api.dart`), never by importing each other's internals.
///
/// Layout of a module `foo`:
///
/// ```text
/// lib/src/foo/
///   model.dart        dart_mappable data (+ model.mapper.dart, generated)
///   service.dart      the logic - plain Dart, no server bindings, unit tested
///   permissions.dart  the module's PermNodes
///   commands.dart     command registration
///   ui.dart           menus, boss bars, titles (only if needed)
///   foo_module.dart   FooModule: wires the above together
/// ```
abstract base class Module {
  /// Short lowercase name, also the folder under the data folder.
  String get name;

  /// Modules that must be loaded first because this one uses their services.
  List<String> get dependsOn => const [];

  /// Registered with the server before [onLoad].
  List<PermNode> get permissions => const [];

  void onLoad(ModuleHost host);

  /// The plugin is unloading. Documents are saved right after all modules.
  void onUnload() {}
}

/// What a module gets to work with.
final class ModuleHost {
  final String moduleName;
  final Context context;
  final Services services;
  final Documents docs;
  final Clock clock;
  final Logger log;

  ModuleHost({
    required this.moduleName,
    required this.context,
    required this.services,
    required this.docs,
    required this.clock,
  }) : log = Logger(moduleName);

  /// The module's message templates, editable by server owners in
  /// `messages/<module>.json`. Keys missing from the file are added.
  MessageCatalog messages(
    Map<String, String> defaults, {
    String prefix = '&8[&6Commons&8] &r',
  }) => context.files.messageCatalog(
    'messages/$moduleName.json',
    defaults: defaults,
    prefix: prefix,
  );
}
