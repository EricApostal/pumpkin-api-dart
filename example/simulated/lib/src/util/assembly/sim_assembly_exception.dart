// `com.simibubi.create.content.contraptions.AssemblyException`, as far as
// Simulated raises its own: the alignment, world-bound, distance and speed
// checks of the physics assembler.
//
// The Java class carries a translation key and its arguments. The port keeps
// the key and the formatted message so the command and the UI can show the same
// text.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.util.assembly.SimAssemblyException

/// An assembly failure with a translation key.
final class SimAssemblyException implements Exception {
  /// The translation key (`simulated:gui.assembly.exception.too_fast`).
  final String translationKey;

  /// The arguments of the message.
  final List<Object?> arguments;

  const SimAssemblyException(this.translationKey, [this.arguments = const []]);

  /// `structureTooLarge`: the structure has more blocks than the config allows.
  factory SimAssemblyException.structureTooLarge(int maxBlocks) =>
      SimAssemblyException('simulated:gui.assembly.exception.structure_too_large', [maxBlocks]);

  /// `couldNotAlign`: the disassembly alignment did not converge in time.
  static SimAssemblyException couldNotAlign() =>
      const SimAssemblyException('simulated:gui.assembly.exception.could_not_align');

  /// `outOfWorld`: the structure would leave the build height.
  static SimAssemblyException outOfWorld() =>
      const SimAssemblyException('simulated:gui.assembly.exception.out_of_world');

  /// `tooFarFromGround`: mid-air disassembly is disabled and there is no terrain
  /// near the structure.
  static SimAssemblyException tooFarFromGround() =>
      const SimAssemblyException('simulated:gui.assembly.exception.too_far_from_ground');

  /// `tooFast`: the structure moves too fast to be placed back.
  static SimAssemblyException tooFast() =>
      const SimAssemblyException('simulated:gui.assembly.exception.too_fast');

  /// `sameSubLevel`: the bearing and its plate ended up in the same sub-level.
  static SimAssemblyException sameSubLevel() =>
      const SimAssemblyException('simulated:gui.assembly.exception.same_sub_level');

  /// `unmovableBlock`: a block of the structure refuses to move.
  factory SimAssemblyException.unmovableBlock((int, int, int) pos, String blockKey) =>
      SimAssemblyException('create:gui.assembly.exception.unmovable_block', [pos.$1, pos.$2, pos.$3, blockKey]);

  /// The Sable component's assembly backend is not installed, so the assembly
  /// cannot run (see `SimAssemblyHelper.assembleBlocks`).
  static SimAssemblyException noBackend() =>
      const SimAssemblyException('simulated:gui.assembly.exception.no_backend');

  /// `unloadedChunk`: the structure reaches a chunk that is not loaded.
  factory SimAssemblyException.unloadedChunk((int, int, int) pos) =>
      SimAssemblyException('create:gui.assembly.exception.unloaded_chunk', [pos.$1, pos.$2, pos.$3]);

  @override
  String toString() => 'SimAssemblyException($translationKey, $arguments)';
}
