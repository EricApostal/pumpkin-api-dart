/// The redstone module's API for the other modules (published by `RedstoneModule`), and the
/// provider interfaces the redstone module consumes from them.
///
/// **Published by redstone** (`ctx.services.require<...>()`, available from `onServerLoaded`):
///  * [RedstoneLinkNetworkHandler] (`Create.REDSTONE_LINK_NETWORK_HANDLER`): the per world
///    frequency networks. [LinkBehaviour] joins a block entity to it (stock links, the redstone
///    requester): `entity.addBehaviour(LinkBehaviour.transmitter(...))`.
///  * [RedstoneDisplayApi]: the display link registries (`DisplaySource.BY_BLOCK`...), the
///    gatherer notifications (`DisplayLinkBlock.notifyGatherers` / `sendToGatherers`) and
///    `SmartObserverBlock.onFunnelTransfer`.
///  * [PanelSupportBehaviour] (see `panel_support.dart`).
///
/// **Consumed by redstone** (provide them with `ctx.services.provide<...>()`, optional, the
/// display sources show nothing for data nobody provides): [KineticDisplayData],
/// [BoilerDisplayData], [ElevatorDisplayData], [TrainDisplayData], [ItemFlowDisplayData],
/// [SeatDisplayData], [FlapDisplayAccess], [ObservableProbe] (through [RedstoneObservables]),
/// [ItemFilterApi], [ClipboardApi], [FactoryPanelAccess].
library;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../common/common.dart';
import '../redstone/display/display_core.dart' show DisplaySource, DisplayTarget, FlapControllerView, TrainPredictionView;
import '../redstone/support/text.dart' show Txt;

export '../redstone/display/display_core.dart'
    show
        DisplayLinkContext,
        DisplayEnv,
        DisplaySource,
        DisplayTarget,
        DisplayTargetStats,
        FlapControllerView,
        FlapLayoutSpec,
        FlapSectionSpec,
        FlapTarget,
        GaugeEntryView,
        TrainPredictionView;
export '../redstone/display/display_sources.dart' show AccumulatedItemCountDisplaySource, GatheredDataLink;
export '../redstone/link/frequency.dart' show Frequency, NetworkKey;
export '../redstone/link/link_behaviour.dart' show LinkBehaviour;
export '../redstone/link/link_network.dart' show RedstoneLinkNetworkHandler, RedstoneLinkable;
export '../redstone/support/text.dart' show Txt;
export 'panel_support.dart';

/// The display link registries and the notifications other modules send to display links.
abstract interface class RedstoneDisplayApi {
  /// Registers a display source for the blocks [blockKeys] (`DisplaySource.BY_BLOCK.add`).
  /// A source with a new id is added to the id registry as well.
  void registerSource(DisplaySource source, Iterable<String> blockKeys);

  /// Registers a display target for the blocks [blockKeys] (`DisplayTarget.BY_BLOCK.register`).
  void registerTarget(DisplayTarget target, Iterable<String> blockKeys);

  /// `DisplayLinkBlock.notifyGatherers(level, pos)`: the data of the block at [pos] changed, the
  /// display links reading it refresh.
  Future<void> notifyGatherers(World world, BlockPos pos);

  /// `DisplayLinkBlock.sendToGatherers(..., AccumulatedItemCountDisplaySource.class)` with
  /// `itemReceived(be, amount)`: items passed a tunnel at [pos].
  Future<void> itemReceived(World world, BlockPos pos, int amount);

  /// `SmartObserverBlock.onFunnelTransfer(world, funnelPos, transferred)`: a funnel moved
  /// an item; the observers pointing at it with a matching filter fire.
  Future<void> onFunnelTransfer(World world, BlockPos funnelPos, String itemKey);
}

// -- Provider interfaces -----------------------------------------------------------------------------------

/// Kinetic data for the speedometer, stressometer and cuckoo clock sources (kinetics module).
abstract interface class KineticDisplayData {
  /// `SpeedGaugeBlockEntity.getSpeed()`, `null` if the block entity at [pos] is not a speedometer.
  double? speedGaugeSpeed(String worldId, Pos pos);

  /// `StressGaugeBlockEntity.getNetworkStress()` / `getNetworkCapacity()`, `null` if not a stressometer.
  ({double stress, double capacity})? stressGaugeNetwork(String worldId, Pos pos);

  /// `CuckooClockBlockEntity.getSpeed()`, `null` if not a cuckoo clock.
  double? cuckooClockSpeed(String worldId, Pos pos);
}

/// The boiler status texts of a fluid tank (fluids module).
abstract interface class BoilerDisplayData {
  /// `BoilerData` of the controller of the tank at [pos]: `getHeatLevelTextComponent()`,
  /// `getSizeComponent(!forFlap, forFlap, RESET)`, `getWaterComponent(...)`, `getHeatComponent(...)`.
  /// `null` if there is no tank (the source shows nothing).
  ({Txt heatLevel, Txt size, Txt water, Txt heat})? boilerTexts(String worldId, Pos pos, {required bool forFlapDisplay});
}

/// The elevator contact's last reported floor (contraptions module).
abstract interface class ElevatorDisplayData {
  /// `ElevatorContactBlockEntity.lastReportedCurrentFloor`, `null` if not an elevator contact.
  String? lastReportedFloor(String worldId, Pos pos);
}

/// Trains (trains module).
abstract interface class TrainDisplayData {
  /// `TrackObserver.getCurrentTrain()` name of the observer at [pos], `null` for none.
  Txt? observedTrainName(String worldId, Pos pos);

  /// `ScheduleRuntime.getWaitingStatus` of the train waiting at the station at [pos], `null` for
  /// none (see `TrainStatusDisplaySource` for the conditions).
  Txt? trainStatus(String worldId, Pos pos);

  /// `GlobalStation.name` of the station at [pos].
  String? stationName(String worldId, Pos pos);

  /// `GlobalTrainDisplayData.prepare(filter, maxRows)`.
  List<TrainPredictionView> predictions(String filter, int maxRows);
}

/// Items on belts, depots and ejectors (kinetics / logistics modules).
abstract interface class ItemFlowDisplayData {
  /// The display name of the item at the centre of the belt, depot or ejector at [pos]
  /// (`handleCenteredProcessingOnAllItems(.25f, ...)`): `null` if the block has no such
  /// behaviour (`TransportedItemStackHandlerBehaviour`), `''` if it holds no item there.
  String? centeredItemName(String worldId, Pos pos);
}

/// Seats (contraptions module).
abstract interface class SeatDisplayData {
  /// The display name of the first passenger of the seat entity at [pos]: `null`/`''` for none.
  String? passengerName(String worldId, Pos pos);
}

/// The display board (decoration module): the `FlapDisplayBlockEntity` controller.
abstract interface class FlapDisplayAccess {
  FlapControllerView? controllerAt(String worldId, Pos pos);
}

/// Something the smart observer / threshold switch can look at besides item and fluid containers
/// (belts and depots with `TransportedItemStackHandlerBehaviour`, pipes with
/// `FluidTransportBehaviour`, chain conveyors, funnels). Register with
/// [RedstoneObservables.register] in `onServerLoaded`.
abstract interface class ObservableProbe {
  /// Whether the block entity at [pos] is something this probe observes (placement uses it to pick the
  /// observer's direction).
  bool canObserve(String worldId, Pos pos);

  /// `SmartObserverBlockEntity.tick` detection: `null` if the probe does not handle [pos]; else
  /// whether an item or fluid accepted by the filter is passing now.
  bool? detect(String worldId, Pos pos, ObserverFilter filter);

  /// Packages looping on a chain conveyor at [pos] that pass the filter (`getLoopingPackages`):
  /// their addresses; `null` if the probe does not handle [pos].
  List<String>? loopingPackageAddresses(String worldId, Pos pos, ObserverFilter filter) => null;

  /// `ThresholdSwitchObservable` of the block entity at [pos]: `null` if it is not observable.
  ThresholdObservation? observation(String worldId, Pos pos) => null;
}

/// The filter an observer applies (`FilteringBehaviour.test`).
abstract interface class ObserverFilter {
  bool get isEmpty;
  bool testItem(String itemKey);
  bool testFluid(String fluidKey);
}

/// `ThresholdSwitchObservable`: a value a threshold switch can watch (a pulley's rope length).
final class ThresholdObservation {
  final int min;
  final int max;
  final int current;
  final Txt Function(int value) format;

  const ThresholdObservation({required this.min, required this.max, required this.current, required this.format});
}

/// The service that collects the [ObservableProbe]s.
abstract interface class RedstoneObservables {
  void register(ObservableProbe probe);
}

/// List and attribute filter items (logistics module): the redstone filter slots store only the
/// filter item; matching a stack against a filter item (`create:filter`, `create:attribute_filter`)
/// is the logistics module's `FilterItemStack`.
abstract interface class ItemFilterApi {
  /// Whether [candidateItem] passes the filter item [filterItem] (a plain item matches itself).
  bool testItem(String worldId, String filterItem, String candidateItem);

  /// Whether [fluidKey] passes the filter item (a bucket filter matches its fluid).
  bool testFluid(String worldId, String filterItem, String fluidKey);
}

/// The clipboard (equipment module): nixie tubes display the first entry of a clipboard.
abstract interface class ClipboardApi {
  /// `ClipboardEntry.getLastViewedEntries(stack).getFirst().text` as plain text, `null` for none.
  Future<String?> firstEntryText(ItemStack clipboard);
}
