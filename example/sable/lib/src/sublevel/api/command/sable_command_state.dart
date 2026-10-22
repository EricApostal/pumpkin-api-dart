// What the `/sable` commands need from the plugin at run time.
//
// The Java commands read the level off the `CommandSourceStack` and the helper
// off `Sable.HELPER`. The Dart plugin's command layer hands a command a
// `CommandSender` and a `World`, but a `World` is a host handle and Sable's
// model talks to `SableLevel`, so the plugin installs a resolver here.
//
// Pure: no host imports (the `Object?` world is the plugin's own handle).
import 'dart:math' as math;

import '../../host/sub_level_host.dart';

/// The level resolver: a host world handle to the model's level view.
typedef SableLevelResolver = SableLevel Function(Object? world);

/// The runtime state of the `/sable` commands.
///
/// The selector's `@t`/`@v` lookups are not here: the command layer resolves
/// them from the sender it already has (see `command_support.dart`), which is
/// all the port can do while it has no entity-collision tracking.
final class SableCommandState {
  /// Resolves a host world to the model's level view.
  final SableLevelResolver levelOf;

  /// The random source for `@r`.
  final math.Random random;

  SableCommandState({
    required this.levelOf,
    math.Random? random,
  }) : random = random ?? math.Random();

  /// A state whose level resolver fails with a precise message, for a plugin
  /// that has not installed one yet.
  factory SableCommandState.uninstalled() => SableCommandState(
    levelOf: (world) => throw StateError(
      'HOST GAP: the /sable commands need a World -> SableLevel resolver; '
      'call SableCommandState(levelOf: ...) from the plugin entry point.',
    ),
  );
}
