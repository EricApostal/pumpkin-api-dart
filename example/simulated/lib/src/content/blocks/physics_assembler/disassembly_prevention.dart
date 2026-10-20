// `dev.simulated_team.simulated.content.blocks.physics_assembler.DisassemblyPrevention`:
// whether a sub-level may be disassembled from a given assembler.
//
// When `primaryDisassembly` is on, only the assembler that assembled a sub-level
// may disassemble it; the position of that assembler is stored on the sub-level.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.content.blocks.physics_assembler.assembly_preventer.DisassemblyPrevention
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports

import 'package:create/src/common/pos.dart' show Pos;

import '../../../util/assembly/sim_assembly_exception.dart';

/// The check that stops a non-primary assembler from disassembling a sub-level.
abstract final class DisassemblyPrevention {
  /// The position of the assembler that assembled the sub-level, by sub-level
  /// UUID. The plugin fills this from the sub-level's saved data.
  static final Map<String, Pos> primaryAssemblers = {};

  /// The primary assembler of [subLevelId], or `null`.
  static Pos? primaryAssemblerOf(String subLevelId) => primaryAssemblers[subLevelId];

  /// `checkSubLevelForPrimary(level, toCheck)`.
  ///
  /// Throws [SimAssemblyException] when [toCheck] is not the primary assembler
  /// of the sub-level it stands on.
  static void checkSubLevelForPrimary({
    required bool primaryDisassembly,
    required String? containingSubLevelId,
    required Pos toCheck,
  }) {
    if (!primaryDisassembly || containingSubLevelId == null) return;

    final primary = primaryAssemblerOf(containingSubLevelId);
    if (primary == null) return;
    if (primary == toCheck) return;

    throw const SimAssemblyException('simulated:gui.assembly.prevent_disassembly');
  }

  /// Records [pos] as the primary assembler of [subLevelId].
  static void setPrimary(String subLevelId, Pos? pos) {
    if (pos == null) {
      primaryAssemblers.remove(subLevelId);
    } else {
      primaryAssemblers[subLevelId] = pos;
    }
  }

  /// Forgets every record (server stop, tests).
  static void clear() => primaryAssemblers.clear();
}
