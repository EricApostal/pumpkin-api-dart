// `CarriageEntityHandler` (pure): keeps carriage entities from living in chunks that do not tick
// entities. The host calls [onEntityEnterSection] when a carriage entity enters another chunk
// section (`EntityEvent.EnteringSection` with `didChunkChange`).
import '../../common/pos.dart';
import 'carriage_contraption_entity.dart';
import 'train_level.dart';

abstract final class CarriageEntityHandler {
  /// [sectionCenter] is `SectionPos.center()` of the new section.
  static void onEntityEnterSection(CarriageContraptionEntity cce, Pos sectionCenter) {
    if (!isActiveChunk(cce.level, sectionCenter)) cce.leftTickingChunks = true;
  }

  static void validateCarriageEntity(CarriageContraptionEntity entity) {
    if (!entity.isAlive) return;
    final level = entity.level;
    if (!isActiveChunk(level, posContaining(entity.position))) entity.leftTickingChunks = true;
  }

  static bool isActiveChunk(TrainLevel level, Pos pos) => level.isActiveChunk(pos);
}
