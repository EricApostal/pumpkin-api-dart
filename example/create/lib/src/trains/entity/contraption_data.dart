// The minimal view of a contraption the train code needs (pure). The contraptions module owns
// the real `Contraption`; its carriage contraption wraps a [CarriageContraption] (the train
// specific part) and implements [ContraptionData] for it. `lib/src/api/trains.dart` exports this.
import '../../api/block_state.dart';
import '../../common/direction.dart' show Axis;
import '../../common/pos.dart';
import '../util/ctag.dart';
import 'carriage_storage.dart';
import 'train_level.dart';

/// `StructureTemplate.StructureBlockInfo`: the state and the block entity data of a block of a
/// contraption.
final class ContraptionBlockInfo {
  final BState state;
  final CTag? nbt;

  const ContraptionBlockInfo(this.state, [this.nbt]);
}

/// What the train code asks of the `Contraption` a carriage entity carries.
abstract interface class ContraptionData {
  /// `contraption.getBlocks()`: the captured blocks by local position.
  Map<Pos, ContraptionBlockInfo> getBlocks();

  /// `contraption.anchor`: the world position the contraption was assembled at.
  Pos get anchor;

  /// `contraption.toLocalPos(pos)`.
  Pos toLocalPos(Pos pos);

  /// `contraption.getSeats()`: local positions of the seats, in seat index order.
  List<Pos> getSeats();

  /// `contraption.getSeatMapping()`: passenger uuid -> seat index.
  Map<String, int> getSeatMapping();

  /// `contraption.getSeatOf(uuid)`: the local position of the seat of the passenger, or `null`.
  Pos? getSeatOf(String passengerUuid);

  /// `contraption.getActors().forEach(... MovementBehaviour.cancelStall(context))`.
  void cancelActorStalls();

  /// `contraption.startMoving(level)`.
  void startMoving(TrainLevel level);

  /// `contraption.onEntityInitialize(level, entity)`; [entity] is the `CarriageContraptionEntity`.
  void onEntityInitialize(TrainLevel level, Object entity);

  /// The contraption's own cargo (`contraption.storage`, a `TrainCargoManager` for carriage
  /// contraptions) taken out of the contraption: the contraption keeps an empty
  /// `MountedStorageManager` instead (`swapStorageAfterAssembly`).
  CarriageStorage? takeStorage();

  /// `contraption.isHiddenInPortal(localPos)` / `contraption.getSimplifiedEntityColliders()`:
  /// the train part decides which blocks and colliders are hidden while the carriage is in a
  /// portal (`CarriageContraption` overrides both in Java).
  void setPortalHiding(
    bool Function(Pos localPos) hiddenInPortal,
    bool Function() collidersHidden,
  );

  /// `contraption.storage = storage` (`returnStorageForDisassembly`).
  void returnStorage(CarriageStorage storage);

  /// `contraption.removeBlocksFromWorld(level, BlockPos.ZERO)`: the structure is taken out of the
  /// world while the carriage entity shows it. The station calls this before it creates the train
  /// (`StationBlockEntity.assemble`, Java `StationBlockEntity.java:885-887`).
  Future<void> removeBlocksFromWorld();

  /// `contraption.expandBoundsAroundAxis(Axis.Y)`: the bounds of an assembled carriage grow along
  /// the axis its bogeys sit on.
  void expandBoundsAroundAxis(Axis axis);
}
