// `com.simibubi.create.content.contraptions.AssemblyException`, as far as
// Simulated raises its own: the alignment, world-bound, distance and speed
// checks of the physics assembler.
//
// The Java class carries a `Component`; the port keeps the same message in the two
// shapes this code can express it: a translation key with its arguments (Java's
// `CreateLang.translateDirect("gui.assembly.exception." + key)` and Simulated's
// `SimLang.translate("gui.assembly.exception." + key)`) or, for the failures that
// exist only in the port, a literal text. Both render to the component JSON
// `AssemblyException.write` stores, which is the text a client resolves with its own
// lang when it shows the failure (the goggles overlay).
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.util.assembly.SimAssemblyException
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports

import 'dart:convert';

import 'package:create/src/contraptions/core/structure_info.dart' show BlockNameArg;

/// An assembly failure with its message.
final class SimAssemblyException implements Exception {
  /// The full translation key (`simulated.gui.assembly.exception.tooFast`), or
  /// `null` when the message is the literal [text].
  final String? translationKey;

  /// The literal message of a failure that has no key in any lang file, or `null`
  /// when the message is a translation. Java raises none of these: they are port
  /// infrastructure failures, and the client can never resolve an invented key, so
  /// it would show the key itself.
  final String? text;

  /// The arguments of the translation: numbers, strings and [BlockNameArg]s
  /// (`state.getBlock().getName()`).
  final List<Object?> arguments;

  const SimAssemblyException.key(this.translationKey, [this.arguments = const []]) : text = null;

  const SimAssemblyException.text(String this.text)
    : translationKey = null,
      arguments = const [];

  /// `structureTooLarge`: the structure has more blocks than the config allows
  /// (`new AssemblyException("structureTooLarge", max)`).
  factory SimAssemblyException.structureTooLarge(int maxBlocks) =>
      SimAssemblyException.key('create.gui.assembly.exception.structureTooLarge', [maxBlocks]);

  /// `couldNotAlign`: the disassembly alignment did not converge in time.
  static SimAssemblyException couldNotAlign() =>
      const SimAssemblyException.key('simulated.gui.assembly.exception.couldNotAlign');

  /// `outOfWorld`: the structure would leave the build height.
  static SimAssemblyException outOfWorld() =>
      const SimAssemblyException.key('simulated.gui.assembly.exception.outOfWorld');

  /// `tooFarFromGround`: mid-air disassembly is disabled and there is no terrain
  /// near the structure.
  static SimAssemblyException tooFarFromGround() =>
      const SimAssemblyException.key('simulated.gui.assembly.exception.tooFarFromGround');

  /// `tooFast`: the structure moves too fast to be placed back.
  static SimAssemblyException tooFast() =>
      const SimAssemblyException.key('simulated.gui.assembly.exception.tooFast');

  /// `sameSubLevel`: the bearing and its plate ended up in the same sub-level.
  static SimAssemblyException sameSubLevel() =>
      const SimAssemblyException.key('simulated.gui.assembly.exception.sameSubLevel');

  /// `unmovableBlock`: a block of the structure refuses to move
  /// (`AssemblyException.unmovableBlock(pos, state)`).
  factory SimAssemblyException.unmovableBlock((int, int, int) pos, String blockKey) =>
      SimAssemblyException.key('create.gui.assembly.exception.unmovableBlock', [
        pos.$1,
        pos.$2,
        pos.$3,
        BlockNameArg(blockKey),
      ]);

  /// The Sable component's assembly backend is not installed, so the assembly
  /// cannot run (see `SimAssemblyHelper.assembleBlocks`). Port-only: Java calls
  /// Sable directly and raises nothing here.
  static SimAssemblyException noBackend() =>
      const SimAssemblyException.text('The sub-level assembly backend is not available on this server');

  /// The Sable component refused the assembly; its reply carries the error. Port
  /// only, as [noBackend].
  static SimAssemblyException backendError(String message) => SimAssemblyException.text(message);

  /// `unloadedChunk`: the structure reaches a chunk that is not loaded
  /// (`AssemblyException.unloadedChunk(pos)`).
  factory SimAssemblyException.unloadedChunk((int, int, int) pos) =>
      SimAssemblyException.key('create.gui.assembly.exception.chunkNotLoaded', [pos.$1, pos.$2, pos.$3]);

  /// The message as the JSON of a text component (`ComponentSerialization.CODEC`),
  /// the value `AssemblyException.write` stores in `LastException.Component`.
  ///
  /// Every argument becomes a component, the way `Component.translatable(key, args)`
  /// does it, so the client's codec reads the message back unchanged.
  String toComponentJson() => jsonEncode({
    if (text != null) 'text': text else 'translate': translationKey,
    if (arguments.isNotEmpty) 'with': [for (final a in arguments) _componentArg(a)],
  });

  /// `AssemblyException.read`: the message of the stored component JSON, or `null`
  /// when it is not a plain translation or literal.
  static SimAssemblyException? fromComponentJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final text = decoded['text'];
    if (text is String) return SimAssemblyException.text(text);
    final key = decoded['translate'];
    if (key is! String) return null;
    final args = decoded['with'];
    return SimAssemblyException.key(key, [
      for (final a in args is List ? args : const <Object?>[]) _argumentOf(a),
    ]);
  }

  @override
  String toString() => 'SimAssemblyException(${translationKey ?? text}, $arguments)';
}

/// The component of one message argument (`Component.translatable`'s conversion of
/// a non-component argument, and `Block.getName()` for a [BlockNameArg]).
Object _componentArg(Object? argument) => switch (argument) {
  BlockNameArg a => a.toJsonValue(),
  // A component argument the class was built from already.
  Map<Object?, Object?> a => a,
  _ => {'text': '$argument'},
};

/// The argument behind the component JSON of [_componentArg], kept as-is for the
/// components ([BlockNameArg]s and nested text) this class only passes through.
Object? _argumentOf(Object? json) {
  if (json is Map) {
    final text = json['text'];
    if (text is String && json.length == 1) return text;
  }
  return json;
}