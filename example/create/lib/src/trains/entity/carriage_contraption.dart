// `CarriageContraption` (pure): the train specific part of the contraption of a carriage - how the
// bogeys and controls of the assembled blocks are counted, which sides have a conductor (a blaze
// burner or a seat next to controls), the arrival sounds and the part of the contraption that is
// hidden while the carriage is in a portal. The contraption itself (block capture, the structure,
// actors, seats) belongs to the contraptions module and is reached through [ContraptionData].
//
// Using it: the contraptions module's carriage contraption owns one [CarriageContraption], calls
// [capture] for every block it captures, [checkAssembly] when the search is done and
// [writeNBT] / [readNBT] next to its own NBT; `data` is the module's view of the contraption.
import '../../api/block_state.dart';
import '../../common/data.dart';
import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../bogey/abstract_bogey_block.dart';
import '../util/ctag.dart';
import 'arrival_sound_queue.dart';
import 'carriage_contraption_entity.dart';
import 'carriage_storage.dart';
import 'contraption_data.dart';

/// `AssemblyException` of the train assembly: a lang key of Create (`create.train_assembly.*`)
/// with its arguments.
final class TrainAssemblyException implements Exception {
  final String translationKey;
  final List<Object> args;

  const TrainAssemblyException(this.translationKey, [this.args = const []]);

  @override
  String toString() => 'TrainAssemblyException($translationKey, $args)';
}

class CarriageContraption {
  late ContraptionData data;

  Direction assemblyDirection;
  bool forwardControls = false;
  bool backwardControls = false;

  Couple<bool> blockConductors = Couple.create(false, false);
  Map<Pos, Couple<bool>> conductorSeats = {};
  ArrivalSoundQueue soundQueue = ArrivalSoundQueue();

  // during assembly only
  int bogeys = 0;
  bool sidewaysControls = false;
  Pos? secondBogeyPos;
  final List<Pos> assembledBlockConductors = [];

  // render
  int portalCutoffMin = _intMin;
  int portalCutoffMax = _intMax;

  static const int _intMin = -0x80000000;
  static const int _intMax = 0x7fffffff;

  /// `ConductorBlockInteractionBehavior.isValidConductor(state)` by block key: the blocks that
  /// act as a conductor when they are next to controls. Create has the blaze burner (any lit
  /// state).
  static final Map<String, bool Function(BState)> conductorBlocks = {
    'create:blaze_burner': (state) => state['blaze'] != 'none',
  };

  /// `AllBlocks.TRAIN_CONTROLS`.
  static const String controlsKey = 'create:controls';

  CarriageContraption(this.assemblyDirection);

  void setSoundQueueOffset(int offset) {
    soundQueue.offset = offset;
  }

  /// The train part of `capture(world, pos)`: [blockState] is the block at world position [pos].
  void capture(BState blockState, Pos pos) {
    if (ArrivalSoundQueue.isPlayable(blockState)) {
      final axis = assemblyDirection.axis;
      final anchorCoord = VecHelper.getCoordinatePos(data.anchor, axis);
      final posCoord = VecHelper.getCoordinatePos(pos, axis);
      soundQueue.add((posCoord - anchorCoord) * assemblyDirection.axisDirection.step, data.toLocalPos(pos));
    }

    if (AbstractBogeyBlock.byKey(blockState.key) != null) {
      bogeys++;
      if (bogeys == 2) secondBogeyPos = pos;
    }

    final conductor = conductorBlocks[blockState.key];
    if (conductor != null && conductor(blockState)) {
      assembledBlockConductors.add(data.toLocalPos(pos));
    }

    if (blockState.key == controlsKey) {
      final facing = blockState.dir('facing') ?? Direction.north;
      if (facing.axis != assemblyDirection.axis) {
        sidewaysControls = true;
      } else {
        final forwards = facing == assemblyDirection;
        if (forwards) {
          forwardControls = true;
        } else {
          backwardControls = true;
        }
      }
    }
  }

  /// The rest of `assemble(world, pos)` after the structure search: returns `false` when the
  /// structure cannot be a carriage (one block or no bogey), throws a [TrainAssemblyException]
  /// for too many bogeys and sideways controls.
  bool checkAssembly() {
    final blocks = data.getBlocks();
    if (blocks.length <= 1) return false;
    if (bogeys == 0) return false;
    if (bogeys > 2) throw TrainAssemblyException('train_assembly.too_many_bogeys', [bogeys]);
    if (sidewaysControls) throw const TrainAssemblyException('train_assembly.sideways_controls');

    for (final blazePos in assembledBlockConductors) {
      for (final direction in Iterate.directionsInAxis(assemblyDirection.axis)) {
        if (inControl(blazePos, direction)) blockConductors.set(direction != assemblyDirection, true);
      }
    }
    for (final seatPos in data.getSeats()) {
      for (final direction in Iterate.directionsInAxis(assemblyDirection.axis)) {
        if (inControl(seatPos, direction)) {
          conductorSeats.putIfAbsent(seatPos, () => Couple.create(false, false)).set(direction != assemblyDirection, true);
        }
      }
    }

    // The contraption hides the blocks and colliders outside the portal cut while a carriage is
    // entering or leaving a portal (`CarriageContraption.isHiddenInPortal`).
    data.setPortalHiding(isHiddenInPortal, () => !notInPortal());

    return true;
  }

  bool inControl(Pos pos, Direction direction) {
    final controlsPos = pos.relative(direction);
    final info = data.getBlocks()[controlsPos];
    if (info == null) return false;
    if (info.state.key != controlsKey) return false;
    return info.state.dir('facing') == direction.opposite;
  }

  /// `swapStorageAfterAssembly(cce)`: the cargo of the contraption moves to the global carriage,
  /// which manages it from then on.
  void swapStorageAfterAssembly(CarriageContraptionEntity cce) {
    final carriage = cce.getCarriage()!;
    if (!carriage.hasStorage) {
      final taken = data.takeStorage();
      if (taken != null) carriage.storage = taken;
    }
    storageProxy = carriage.storage;
  }

  /// `storageProxy`: the cargo the carriage manages (`getStorage()`).
  CarriageStorage? storageProxy;

  void returnStorageForDisassembly(CarriageStorage storage) {
    data.returnStorage(storage);
  }

  /// The train part of `writeNBT(registries, spawnPacket)`.
  void writeNBT(CTag tag) {
    // `Direction.name()`, lower case: `readEnum` matches the constant name.
    tag.putString('AssemblyDirection', assemblyDirection.name);
    tag.putBoolean('FrontControls', forwardControls);
    tag.putBoolean('BackControls', backwardControls);
    tag.putBoolean('FrontBlazeConductor', blockConductors.getFirst());
    tag.putBoolean('BackBlazeConductor', blockConductors.getSecond());
    tag.putCompoundList('ConductorSeats', [
      for (final e in conductorSeats.entries)
        CTag()
          ..putBlockPos('Pos', e.key)
          ..putBoolean('Forward', e.value.getFirst())
          ..putBoolean('Backward', e.value.getSecond()),
    ]);
    soundQueue.serialize(tag);
  }

  /// The train part of `readNBT(world, nbt, spawnData)`.
  void readNBT(CTag nbt) {
    assemblyDirection = _readDirection(nbt, 'AssemblyDirection');
    forwardControls = nbt.getBoolean('FrontControls');
    backwardControls = nbt.getBoolean('BackControls');
    blockConductors = Couple.create(nbt.getBoolean('FrontBlazeConductor'), nbt.getBoolean('BackBlazeConductor'));
    conductorSeats.clear();
    for (final c in nbt.getCompoundList('ConductorSeats')) {
      conductorSeats[c.getBlockPos('Pos')] = Couple.create(c.getBoolean('Forward'), c.getBoolean('Backward'));
    }
    soundQueue = ArrivalSoundQueue();
    soundQueue.deserialize(nbt);
  }

  static Direction _readDirection(CTag tag, String key) {
    final name = tag.getString(key).toLowerCase();
    for (final d in Direction.values) {
      if (d.name == name) return d;
    }
    return Direction.values[0];
  }

  bool canBeStabilized(Direction facing, Pos localPos) => false;

  Direction getAssemblyDirection() => assemblyDirection;

  bool hasForwardControls() => forwardControls;

  bool hasBackwardControls() => backwardControls;

  Pos? getSecondBogeyPos() => secondBogeyPos;

  /// `isHiddenInPortal(localPos)`: whether the block is outside the visible part, or on the seam.
  bool isHiddenInPortal(Pos localPos) {
    if (notInPortal()) return false;
    final coord = _coordAlongMovementAxis(localPos);
    return !withinVisibleCoord(coord) || atSeamCoord(coord);
  }

  bool isHiddenInPortalCoord(int posAlongMovementAxis) {
    if (notInPortal()) return false;
    return !withinVisibleCoord(posAlongMovementAxis) || atSeamCoord(posAlongMovementAxis);
  }

  bool notInPortal() => portalCutoffMin == _intMin && portalCutoffMax == _intMax;

  int _coordAlongMovementAxis(Pos localPos) {
    final facing = assemblyDirection;
    final axis = facing.clockWise.axis;
    return axis.choose(localPos.$3, localPos.$2, localPos.$1) * -facing.axisDirection.step;
  }

  /// `atSeam(localPos)`.
  bool atSeam(Pos localPos) => atSeamCoord(_coordAlongMovementAxis(localPos));

  /// `withinVisible(localPos)`.
  bool withinVisible(Pos localPos) => withinVisibleCoord(_coordAlongMovementAxis(localPos));

  /// `atSeam(posAlongMovementAxis)`.
  bool atSeamCoord(int posAlongMovementAxis) =>
      posAlongMovementAxis == portalCutoffMin || posAlongMovementAxis == portalCutoffMax;

  /// `withinVisible(posAlongMovementAxis)`.
  bool withinVisibleCoord(int posAlongMovementAxis) =>
      posAlongMovementAxis > portalCutoffMin && posAlongMovementAxis < portalCutoffMax;
}
