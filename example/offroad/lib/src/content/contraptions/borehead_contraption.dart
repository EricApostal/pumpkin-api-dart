// `BoreheadBearingContraption`: a bearing contraption that refuses to assemble
// without a rock cutting wheel and without somewhere to put what it mines.
//
// Pure: no host imports.
//
// Java: `content/contraptions/borehead_contraption/BoreheadBearingContraption.java`
//       (71 lines)
// ignore_for_file: implementation_imports
import 'package:create/src/common/common.dart' show Pos;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/contraptions/bearing/bearing_contraptions.dart' show BearingContraption;
import 'package:create/src/contraptions/core/contraption.dart' show CapturedBlock;
import 'package:create/src/contraptions/core/level.dart' show ContraptionLevel;
import 'package:create/src/contraptions/core/structure_info.dart' show AssemblyException;

import '../../index/offroad_ids.dart';

/// `BoreheadBearingContraption`.
final class BoreheadBearingContraption extends BearingContraption {
  BoreheadBearingContraption([Direction direction = Direction.north]) : super(false, direction);

  /// `rockCuttingWheelAmount` (`BoreheadBearingContraption.java:21`): how many
  /// rock cutting wheels the structure has.
  int rockCuttingWheelAmount = 0;

  /// `getType()` (`BoreheadBearingContraption.java:51`).
  @override
  String get typeId => OffroadIds.boreheadContraption;

  /// `assemble(world, pos)` (`BoreheadBearingContraption.java:36`): the base
  /// capture, then the two rules of the borehead.
  @override
  Future<bool> assemble(ContraptionLevel level, Pos pos) async {
    final assembled = await super.assemble(level, pos);

    if (rockCuttingWheelAmount < 1) {
      // `OffroadLang.translate("exceptions.borehead_bearing.insuffecient_rockcutting_wheels")`
      // (`BoreheadBearingContraption.java:40`; the Java key keeps its typo).
      throw AssemblyException('offroad.exceptions.borehead_bearing.insuffecient_rockcutting_wheels');
    }

    // `((MountedStorageAccessor) this.storage).getItemsBuilder().isEmpty()`
    // (`BoreheadBearingContraption.java:43`). The port has no accessor for the
    // builder, and `MountedStorageManager.initialize()` is idempotent
    // (`Contraption.onEntityCreated` calls it again), so the check runs on the
    // built view instead.
    storage.initialize();
    if (storage.allItemStorages.isEmpty) {
      // `OffroadLang.translate("exceptions.borehead_bearing.insuffecient_inventory_blocks")`
      // (`BoreheadBearingContraption.java:44`).
      throw AssemblyException('offroad.exceptions.borehead_bearing.insuffecient_inventory_blocks');
    }

    return assembled;
  }

  /// `addBlock(level, pos, capture)` (`BoreheadBearingContraption.java:56`): a
  /// captured rock cutting wheel counts towards [rockCuttingWheelAmount].
  @override
  void addBlock(ContraptionLevel level, Pos pos, CapturedBlock captured) {
    super.addBlock(level, pos, captured);
    if (captured.info.state.key == OffroadIds.rockCuttingWheel) rockCuttingWheelAmount++;
  }

  /// `getSimWrappedStorage()` (`BoreheadBearingContraption.java:64`): the
  /// contraption's items as one Simulated `InventoryLoaderWrapper`.
  ///
  /// TODO(parity): `BoreheadBearingContraption.java:64-70` builds it from
  /// `SimInventoryService.INSTANCE.getWrappedAllItemsFromContraption`; the
  /// Simulated port's inventory service has no contraption-wide wrapper yet
  /// (`example/simulated` keeps `SingleSlotContainer`-style storages), and
  /// `BoreheadAttachedStorage` — the storage type the borehead inserts into —
  /// is not ported either (`content/blocks/borehead_bearing/BoreheadAttachedStorage.java`,
  /// `service/OffroadMountedStorageService.java`).
  Object? get simWrappedStorage => null;
}