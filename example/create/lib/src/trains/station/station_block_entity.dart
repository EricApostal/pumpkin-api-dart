// `StationBlockEntity` (host): the station's station marker, its assembly state and the trains it
// assembles. The pure assembly scan and the wheel points live in `station_assembly.dart`; this
// class is the block entity glue: NBT, ticking, the assembly/disassembly and the package ports.
//
// Java -> Dart: the depot (`DepotBehaviour`) and the carriage contraption belong to the logistics
// and contraptions modules and are reached through the services in `api/trains.dart`; the
// `TrainLevel` comes from `Create.RAILWAYS.trainLevelById` (set by the entity host).
import 'dart:async';
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/decoration.dart' show DoorControlBehaviour;
import '../../api/redstone.dart' show RedstoneDisplayApi;
import '../../api/trains.dart';
import '../../common/bounds.dart';
import '../../common/data.dart' show Iterate;
import '../../common/direction.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../../contraptions/core/structure_transform.dart';
import '../../core/block_entity.dart';
import '../../core/nbt.dart' show NetworkNbt;
import '../../redstone/support/text.dart'
    show Txt, plainTextOfJson, tryParseJson;
import '../bogey/abstract_bogey_block.dart';
import '../bogey/abstract_bogey_block_entity.dart';
import '../bogey/bogey_blocks.dart' show railwayCasingKey;
import '../graph/edge_point_type.dart';
import '../manager/create.dart';
import '../manager/global_railway_manager.dart' show RailwayHooks;
import '../schedule/schedule_item.dart'
    show ScheduleItem, scheduleItemKey, trainScheduleComponent;
import '../support/runtime.dart';
import '../util/uuid.dart';
import 'host_ops.dart' show sendOverlay, shrinkHeld, trainsLang;
import 'station_block.dart';

/// `StationBlockEntity`.
final class StationBlockEntity extends CreateBlockEntity {
  static const String type = 'create:track_station';

  /// `assemblyAreas`: the track area of each station, by world and station position.
  static final Map<String, Map<Pos, BlockBounds>> assemblyAreas = {};

  late final TrackTargetingBehaviour<GlobalStation> edgePoint;
  late final DoorControlBehaviour doorControls;
  StationDepot? depot;

  final StationAssembly assembly = StationAssembly();

  int failedCarriageIndex = -1;
  TrainAssemblyException? lastException;

  // Display / sync state (`imminentTrain`, `trainPresent`, ...).
  String? imminentTrain;
  bool trainPresent = false;
  bool trainBackwards = false;
  bool trainCanDisassemble = false;
  bool trainHasSchedule = false;
  bool trainHasAutoSchedule = false;

  /// `lastDisassembledTrainName` (JSON of the component) and `lastDisassembledMapColorIndex`.
  String? lastDisassembledTrainName;
  int lastDisassembledMapColorIndex = 0;

  StationBlockEntity(super.worldId, super.pos) {
    lazyTickRate = 20;
    edgePoint = addBehaviour(
      TrackTargetingBehaviour<GlobalStation>(EdgePointType.STATION),
    );
    doorControls = addBehaviour(DoorControlBehaviour());
    final factory = Tr.loaded ? Tr.i.service<StationDepotFactory>() : null;
    if (factory != null) {
      depot = addBehaviour(factory.create(this, onChanged: applyAutoSchedule));
    }
  }

  Pos get _pos => pos.toPos();

  HostTrackLevel? get _trackLevel {
    final w = world;
    return w == null ? null : HostTrackLevel(w, store);
  }

  /// `getStation()`.
  GlobalStation? getStation() => edgePoint.getEdgePoint();

  // -- NBT -------------------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('FailedCarriageIndex', failedCarriageIndex);

    final name = lastDisassembledTrainName;
    if (name != null) tag.putString('PrevTrainName', name);
    tag.putInt('PrevTrainColor', lastDisassembledMapColorIndex);

    final exception = lastException;
    if (exception != null) {
      final e = NbtCompound();
      e.putString(
        'Component',
        jsonEncode(
          Txt.literal(
            trainsLang('create.${exception.translationKey}', exception.args),
          ).toJson(),
        ),
      );
      tag.putCompound('LastException', e);
    }

    if (!clientPacket) return;
    final imminent = imminentTrain;
    if (imminent == null) return;
    tag.putIntArray('ImminentTrain', uuidToInts(imminent));
    if (trainPresent) tag.putBool('TrainPresent', true);
    if (trainCanDisassemble) tag.putBool('TrainCanDisassemble', true);
    if (trainBackwards) tag.putBool('TrainBackwards', true);
    if (trainHasSchedule) tag.putBool('TrainHasSchedule', true);
    if (trainHasAutoSchedule) tag.putBool('TrainHasAutoSchedule', true);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    failedCarriageIndex = tag.getInt('FailedCarriageIndex') ?? 0;

    // `ForceFlag` is written only by the ponder scene (client side); Java reads it here, before the
    // client packet guard, so it is kept for parity.
    if (tag.containsKey('ForceFlag')) {
      trainPresent = tag.getBool('ForceFlag') ?? false;
    }

    final name = tag.getString('PrevTrainName');
    if (name != null) lastDisassembledTrainName = name;
    lastDisassembledMapColorIndex = tag.getInt('PrevTrainColor') ?? 0;

    final exception = tag.getCompound('LastException');
    if (exception != null) {
      final json = exception.getString('Component');
      lastException = json == null ? null : TrainAssemblyException(json);
    }

    if (!clientPacket) return;
    final imminent = tag.getIntArray('ImminentTrain');
    if (imminent == null || imminent.length != 4) {
      imminentTrain = null;
      trainPresent = false;
      trainCanDisassemble = false;
      trainBackwards = false;
      return;
    }
    imminentTrain = uuidFromInts(imminent);
    trainPresent = tag.getBool('TrainPresent') ?? false;
    trainCanDisassemble = tag.getBool('TrainCanDisassemble') ?? false;
    trainBackwards = tag.getBool('TrainBackwards') ?? false;
    trainHasSchedule = tag.getBool('TrainHasSchedule') ?? false;
    trainHasAutoSchedule = tag.getBool('TrainHasAutoSchedule') ?? false;
  }

  // -- Ticking ---------------------------------------------------------------------------------

  @override
  void lazyTick() {
    super.lazyTick();
    if (isAssembling()) refreshAssemblyInfo();
  }

  @override
  void tick() {
    super.tick();
    final w = world;
    if (w == null) return;

    final station = getStation();
    if (station == null) return;

    final train = station.getImminentTrain();
    final present =
        train != null && identical(train.getCurrentStation(), station);
    final canDisassemble = present && train.canDisassemble();
    final imminentId = train?.id;
    final hasSchedule = present && train.runtime.getSchedule() != null;
    final hasAutoSchedule = hasSchedule && train.runtime.isAutoSchedule;
    final newlyArrived = trainPresent != present;

    if (present && train.runtime.displayLinkUpdateRequested) {
      final api = Tr.i.service<RedstoneDisplayApi>();
      if (api != null) unawaited(api.notifyGatherers(w, pos));
      train.runtime.displayLinkUpdateRequested = false;
    }

    if (newlyArrived) applyAutoSchedule();

    if (newlyArrived ||
        trainCanDisassemble != canDisassemble ||
        imminentId != imminentTrain ||
        trainHasSchedule != hasSchedule ||
        trainHasAutoSchedule != hasAutoSchedule) {
      imminentTrain = imminentId;
      trainPresent = present;
      trainCanDisassemble = canDisassemble;
      trainBackwards = train != null && train.currentlyBackwards;
      trainHasSchedule = hasSchedule;
      trainHasAutoSchedule = hasAutoSchedule;
      sendData();
    }
  }

  // -- Assembly --------------------------------------------------------------------------------

  /// `isAssembling()`.
  bool isAssembling() =>
      (_trackLevel?.stateAt(_pos).flag(stationAssemblingProperty)) ?? false;

  /// `getAssemblyDirection()`.
  Direction? getAssemblyDirection() {
    final level = _trackLevel;
    if (level == null || !edgePoint.hasValidTrack()) return null;
    final targetPosition = edgePoint.getGlobalPosition();
    final trackState = edgePoint.getTrackBlockState();
    final track = edgePoint.getTrack()!;
    return assembly.getAssemblyDirection(
      level,
      track,
      targetPosition,
      trackState,
      edgePoint.getTargetDirection(),
    );
  }

  /// `refreshAssemblyInfo()`: scans the assembly track for bogeys.
  void refreshAssemblyInfo() {
    final level = _trackLevel;
    if (level == null || !edgePoint.hasValidTrack()) return;
    final station = getStation();
    if (station == null || station.getPresentTrain() != null) return;

    final targetPosition = edgePoint.getGlobalPosition();
    final trackState = edgePoint.getTrackBlockState();
    final track = edgePoint.getTrack()!;
    final changed = assembly.refresh(
      level,
      track,
      targetPosition,
      trackState,
      edgePoint.getTargetDirection(),
      maxLength: TrainSettings.current.maxAssemblyLength,
      maxBogeyCount: TrainSettings.current.maxBogeyCount,
    );
    if (!changed) return;

    final direction = assembly.assemblyDirection;
    if (direction == null) return;
    assemblyAreas.putIfAbsent(worldId, () => {})[_pos] = assembly.assemblyArea(
      targetPosition,
    );
  }

  /// `isValidBogeyOffset(i)`.
  bool isValidBogeyOffset(int i) => assembly.isValidBogeyOffset(i);

  /// `trackClicked(player, hand, track, state, pos)`: a click on the assembly track. Inside the
  /// assembly area this either cycles the size of an existing bogey or places a new one from the
  /// railway casing in the player's hand. Returns `true` when the click was handled.
  Future<bool> trackClicked(
    Player player,
    Hand hand,
    ITrackBlock track,
    BState state,
    Pos pos,
  ) async {
    refreshAssemblyInfo();
    final level = _trackLevel;
    final w = world;
    if (level == null || w == null) return false;

    final area = assemblyAreas[worldId]?[_pos];
    if (area == null || !area.isInside(pos)) return false;

    final upNormal = track.getUpNormal(level, pos, state);
    final up = posContaining(upNormal);
    final down = posContaining((-upNormal.$1, -upNormal.$2, -upNormal.$3));
    final bogeyOffset = pos.distManhattan(edgePoint.getGlobalPosition()) - 1;

    if (!isValidBogeyOffset(bogeyOffset)) {
      // Too close to an existing bogey: cycle that bogey's size instead.
      final direction = assembly.assemblyDirection;
      if (direction == null) return false;
      for (final upsideDown in Iterate.falseAndTrue) {
        for (var i = -1; i <= 1; i++) {
          final bogeyPos =
              pos.relative(direction, i) + (upsideDown ? down : up);
          final blockState = level.stateAt(bogeyPos);
          final bogey = AbstractBogeyBlock.byKey(blockState.key);
          if (bogey == null) continue;
          final oldBE = store.typed<AbstractBogeyBlockEntity>(
            worldId,
            bogeyPos.toBlockPos(),
          );
          if (oldBE == null) continue;

          final oldData = oldBE.getBogeyData();
          final newBlock = oldBE.getNextSize();
          if (newBlock.key == bogey.key) {
            sendOverlay(
              player,
              trainsLang('create.bogey.style.no_other_sizes'),
            );
          }
          await level.setBlock(bogeyPos, newBlock);
          final newBE = store.typed<AbstractBogeyBlockEntity>(
            worldId,
            bogeyPos.toBlockPos(),
          );
          if (newBE == null) continue;
          newBE.setBogeyData(oldData);
          // `IWrenchable.playRotateSound(level, bogeyPos)`.
          w.playCustomSound(
            soundName: 'create:wrench_rotate',
            category: SoundCategory.blocks,
            pos: bogeyPos.center,
            volume: 1,
            pitch: level.random.nextDouble() * 0.5 + 0.5,
          );
          return true;
        }
      }
      return false;
    }

    final heldKey = await player
        .getInventory()
        .getItemInHand(hand: hand)
        ?.getRegistryKey();
    if (player.getGamemode() != GameMode.creative &&
        heldKey != railwayCasingKey) {
      sendOverlay(player, trainsLang('create.train_assembly.requires_casing'));
      return false;
    }

    final anchorState = track.getBogeyAnchor(level, pos, state);
    final anchorBogey = AbstractBogeyBlock.byKey(anchorState.key);
    final upsideDown =
        player.getPitch() < 0 &&
        anchorBogey != null &&
        anchorBogey.canBeUpsideDown();

    final targetPos = upsideDown ? pos + down : pos + up;
    if (w.getBlockState(pos: targetPos.toBlockPos()).hardness == -1) {
      return false;
    }

    await level.destroyBlock(targetPos, true);

    var bogeyAnchor = anchorState;
    final bogey = AbstractBogeyBlock.byKey(bogeyAnchor.key);
    if (bogey != null) {
      bogeyAnchor = bogey.getVersion(bogeyAnchor, upsideDown);
    }
    bogeyAnchor = withWater(level, bogeyAnchor, pos)!;
    await level.setBlock(targetPos, bogeyAnchor);
    sendOverlay(player, trainsLang('create.train_assembly.bogey_created'));

    // `SoundType.NETHERITE_BLOCK`: the standard bogeys use it (`AllBlocks.SMALL_BOGEY`).
    w.playCustomSound(
      soundName: 'minecraft:block.netherite_block.place',
      category: SoundCategory.blocks,
      pos: pos.center,
      volume: 1,
      pitch: 0.8,
    );

    if (player.getGamemode() != GameMode.creative) {
      await shrinkHeld(player, hand);
    }

    return true;
  }

  /// `tryEnterAssemblyMode()`.
  bool tryEnterAssemblyMode() {
    final level = _trackLevel;
    if (level == null || !edgePoint.hasValidTrack()) return false;
    final targetPosition = edgePoint.getGlobalPosition();
    final trackState = edgePoint.getTrackBlockState();
    final track = edgePoint.getTrack()!;
    return StationAssembly.canEnterAssemblyMode(
      track,
      level,
      targetPosition,
      trackState,
    );
  }

  /// `enterAssemblyMode(sender)`.
  bool enterAssemblyMode(String? senderUuid) {
    if (isAssembling()) return false;
    tryDisassembleTrain(senderUuid);
    if (!tryEnterAssemblyMode()) return false;

    final level = _trackLevel;
    if (level == null) return false;
    final w = world;
    if (w == null) return false;

    unawaited(
      level.setBlock(
        _pos,
        level.stateAt(_pos).setFlag(stationAssemblingProperty, true),
      ),
    );
    refreshAssemblyInfo();

    if (!updateStationState((s) => s.assembling = true)) return false;
    final station = getStation();
    if (station != null) {
      final trainLevel = RailwayHooks.trainLevelById?.call(worldId);
      if (trainLevel == null) return true;
      for (final train in Create.RAILWAYS.sided(level).trains.values.toList()) {
        if (!identical(train.navigation.destination, station)) continue;
        final preferred = train.runtime.startCurrentInstruction(trainLevel);
        train.navigation.startNavigation(
          preferred ?? train.navigation.findPathTo([station], double.maxFinite),
        );
      }
    }
    return true;
  }

  /// `exitAssemblyMode()`.
  bool exitAssemblyMode() {
    if (!isAssembling()) return false;
    cancelAssembly();
    final level = _trackLevel;
    if (level == null) return false;
    unawaited(
      level.setBlock(
        _pos,
        level.stateAt(_pos).setFlag(stationAssemblingProperty, false),
      ),
    );
    return updateStationState((s) => s.assembling = false);
  }

  /// `tryDisassembleTrain(sender)`.
  bool tryDisassembleTrain(String? senderUuid) {
    final station = getStation();
    if (station == null) return false;
    final train = station.getPresentTrain();
    if (train == null) return false;

    final direction = getAssemblyDirection();
    if (direction == null) return false;
    final trackPosition = edgePoint.getGlobalPosition();
    if (!train.disassemble(direction, trackPosition.above)) return false;
    dropSchedule(senderUuid, train);
    return true;
  }

  /// `cancelAssembly()`.
  void cancelAssembly() {
    assembly.assemblyLength = 0;
    assemblyAreas[worldId]?.remove(_pos);
    clearException();
  }

  /// `updateName(name)`.
  bool updateName(String name) {
    if (!updateStationState((s) => s.name = name)) return false;
    sendData();
    return true;
  }

  /// `updateMapColor(color)`.
  void updateMapColor(int color) {
    final station = getStation();
    if (station == null) return;
    final train = station.getPresentTrain();
    if (train == null) return;
    train.mapColorIndex = color;
  }

  /// `updateStationState(update)`.
  bool updateStationState(void Function(GlobalStation station) update) {
    final station = getStation();
    final graphLocation = edgePoint.determineGraphLocation();
    if (station == null || graphLocation == null) return false;
    update(station);
    Create.RAILWAYS.sync.pointAdded(graphLocation.graph, station);
    Create.RAILWAYS.markTracksDirty();
    return true;
  }

  // -- Auto schedule ---------------------------------------------------------------------------

  /// `getAutoSchedule()`: the schedule item on the station's slot.
  ItemStack? getAutoSchedule() => depot?.heldItem;

  /// `applyAutoSchedule()`.
  void applyAutoSchedule() {
    final stack = getAutoSchedule();
    if (stack == null) return;
    final schedule = ScheduleItem.getSchedule(
      stack.customComponent(trainScheduleComponent),
    );
    if (schedule == null || schedule.entries.isEmpty) return;
    final station = getStation();
    if (station == null) return;
    final train = station.getImminentTrain();
    if (train == null || !identical(train.getCurrentStation(), station)) return;

    train.runtime.setSchedule(schedule, true);
    TrainFx.effects.playSound(worldId, _pos.center, 'confirm', 1, 1);
  }

  /// `dropSchedule(sender, train)`.
  Future<void> dropSchedule(String? senderUuid, Train? train) async {
    if (train == null) return;
    final tag = train.runtime.returnSchedule();
    if (tag == null) return;

    final stack = ItemStack.create(registryKey: scheduleItemKey, count: 1);
    stack.setCustomComponent(
      trainScheduleComponent,
      NetworkNbt.encode(tag.toNbt()),
    );

    if (senderUuid != null) {
      final bus = Tr.loaded ? Tr.i.bus : null;
      Player? sender;
      for (final p in bus?.roster.players ?? const <Player>[]) {
        if (p.getId().asString != senderUuid) continue;
        sender = p;
        break;
      }
      if (sender != null) {
        final hand = sender.getInventory().getItemInHand(hand: Hand.right);
        if (hand == null || await hand.getCount() <= 0) {
          await sender.give(stack);
          return;
        }
      }
    }

    final w = world;
    if (w == null) return;
    await w.dropItem(
      _pos.center,
      stack,
      velocity: (0.0, 0.0, 0.0),
      pickupDelay: 10,
    );
  }

  // -- Package ports ---------------------------------------------------------------------------

  /// `attachPackagePort(ppbe)`.
  void attachPackagePort(Object portBlockEntity) {
    final station = getStation();
    if (station == null) return;
    Tr.i.service<StationPackagePorts>()?.attach(station, portBlockEntity);
  }

  /// `removePackagePort(ppbe)`.
  void removePackagePort(Object portBlockEntity) {
    final station = getStation();
    if (station == null) return;
    Tr.i.service<StationPackagePorts>()?.remove(station, portBlockEntity);
  }

  // -- Assembly of the train -------------------------------------------------------------------

  /// `assemble(playerUUID)`: builds the carriages from the scanned bogeys and starts the train.
  void assemble(String playerUuid) {
    refreshAssemblyInfo();
    final locations = assembly.bogeyLocations;
    if (locations == null) return;
    if (locations[0] != 0) {
      _exception(
        const TrainAssemblyException(
          'train_assembly.frontmost_bogey_at_station',
        ),
      );
      return;
    }

    final level = _trackLevel;
    if (level == null || !edgePoint.hasValidTrack()) return;
    final trainLevel = RailwayHooks.trainLevelById?.call(worldId);
    final assembler = Tr.i.service<CarriageContraptionAssembly>();
    if (trainLevel == null || assembler == null) {
      _exception(
        const TrainAssemblyException('train_assembly.nothing_attached', [1]),
      );
      return;
    }

    final trackPosition = edgePoint.getGlobalPosition();
    final trackState = edgePoint.getTrackBlockState();
    final track = edgePoint.getTrack()!;
    final bogeyOffset = posContaining(
      track.getUpNormal(level, trackPosition, trackState),
    );
    final points = assembly.createTravellingPoints(
      level,
      track,
      trackPosition,
      trackState,
    );
    if (!points.isOk) {
      final error = points.error;
      if (error != null) {
        _exception(TrainAssemblyException(error.langKey, error.args));
      }
      return;
    }

    final graph = points.graph!;
    final contraptions = <CarriageContraption>[];
    final carriages = <Carriage>[];
    final spacing = <int>[];
    var atLeastOneForwardControls = false;

    var bogeyIndex = 0;
    while (bogeyIndex < assembly.bogeyCount) {
      final pointIndex = bogeyIndex * 2;
      if (bogeyIndex > 0) {
        spacing.add(locations[bogeyIndex] - locations[bogeyIndex - 1]);
      }

      final offset = locations[bogeyIndex] + 1;
      final bogeyPosOffset = trackPosition + bogeyOffset;
      final upsideDownOffset = (bogeyOffset.x, -bogeyOffset.y, bogeyOffset.z);
      final anchor =
          (assembly.upsideDownBogeys![bogeyIndex]
                  ? trackPosition + upsideDownOffset
                  : bogeyPosOffset)
              .relative(assembly.assemblyDirection!, offset);

      final contraption = assembler.assemble(worldId, trainLevel, anchor);
      if (contraption == null) {
        _exception(
          TrainAssemblyException('train_assembly.nothing_attached', [
            bogeyIndex + 1,
          ]),
        );
        return;
      }
      atLeastOneForwardControls |= contraption.hasForwardControls();
      contraption.setSoundQueueOffset(offset);

      final firstType = assembly.bogeyTypes![bogeyIndex]!;
      final firstUpsideDown = assembly.upsideDownBogeys![bogeyIndex];
      final firstBogeyPos = contraption.data.anchor;
      final firstData = store
          .typed<AbstractBogeyBlockEntity>(worldId, firstBogeyPos.toBlockPos())
          ?.getBogeyData();
      final firstBogey = CarriageBogey(
        firstType,
        firstUpsideDown,
        firstData,
        points.points[pointIndex],
        points.points[pointIndex + 1],
      );

      CarriageBogey? secondBogey;
      var bogeySpacing = 0;
      final secondBogeyPos = contraption.getSecondBogeyPos();
      if (secondBogeyPos != null) {
        final expectedSecondPos =
            (assembly.upsideDownBogeys![bogeyIndex + 1]
                    ? trackPosition + upsideDownOffset
                    : bogeyPosOffset)
                .relative(
                  assembly.assemblyDirection!,
                  locations[bogeyIndex + 1] + 1,
                );
        if (bogeyIndex == assembly.bogeyCount - 1 ||
            secondBogeyPos != expectedSecondPos) {
          _exception(
            const TrainAssemblyException(
              'train_assembly.not_connected_in_order',
            ),
            contraptions.length + 1,
          );
          return;
        }
        final secondData = store
            .typed<AbstractBogeyBlockEntity>(
              worldId,
              secondBogeyPos.toBlockPos(),
            )
            ?.getBogeyData();
        bogeySpacing = locations[bogeyIndex + 1] - locations[bogeyIndex];
        secondBogey = CarriageBogey(
          assembly.bogeyTypes![bogeyIndex + 1]!,
          assembly.upsideDownBogeys![bogeyIndex + 1],
          secondData,
          points.points[pointIndex + 2],
          points.points[pointIndex + 3],
        );
        bogeyIndex++;
      } else if (!firstType.allowsSingleBogeyCarriage()) {
        _exception(
          const TrainAssemblyException('train_assembly.single_bogey_carriage'),
          contraptions.length + 1,
        );
        return;
      }

      contraptions.add(contraption);
      carriages.add(Carriage(firstBogey, secondBogey, bogeySpacing));
      bogeyIndex++;
    }

    if (!atLeastOneForwardControls) {
      _exception(const TrainAssemblyException('train_assembly.no_controls'));
      return;
    }

    final train = Train(
      randomUuid(),
      playerUuid,
      graph,
      carriages,
      spacing,
      contraptions.any((c) => c.hasBackwardControls()),
      0,
    );

    final name = lastDisassembledTrainName;
    if (name != null) {
      final json = tryParseJson(name);
      train.name = json == null
          ? Txt.literal(name)
          : Txt.literal(plainTextOfJson(json));
      train.mapColorIndex = lastDisassembledMapColorIndex;
      lastDisassembledTrainName = null;
      lastDisassembledMapColorIndex = 0;
    }

    for (var i = 0; i < contraptions.length; i++) {
      carriages[i].setContraption(trainLevel, contraptions[i]);
    }

    final station = getStation();
    if (station != null) {
      train.setCurrentStation(station);
      station.reserveFor(train);
    }

    train.collectInitiallyOccupiedSignalBlocks();
    Create.RAILWAYS.addTrain(train);
    TrainFx.effects.sendAddTrain(train);
    clearException();
  }

  /// `noteDisassembledTrain(name, mapColorIndex)` (`TrainFx.effects`).
  void noteDisassembledTrain(Txt name, int mapColorIndex) {
    lastDisassembledTrainName = jsonEncode(name.toJson());
    lastDisassembledMapColorIndex = mapColorIndex;
  }

  void clearException() => _exception(null);

  void _exception(TrainAssemblyException? exception, [int carriage = -1]) {
    failedCarriageIndex = carriage;
    lastException = exception;
    sendData();
  }

  @override
  void onRemoved() {
    assemblyAreas[worldId]?.remove(_pos);
    super.onRemoved();
  }

  /// `transform(be, transform)`.
  void transform(StructureTransform transform) =>
      edgePoint.transform(transform);
}
