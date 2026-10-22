// The display link framework as pure logic: `DisplaySource`, `DisplayTarget`,
// `DisplayLinkContext`, `DisplayTargetStats` and the registries that associate sources
// and targets with blocks. The sources and targets themselves are in `display_sources.dart`
// and `display_targets.dart`; the host glue provides a [DisplayEnv].
import '../../api/block_state.dart';
import '../../common/common.dart';
import '../support/text.dart';
import 'config_tag.dart';

export '../support/text.dart' show Txt;

/// `DisplayTargetStats`.
final class DisplayTargetStats {
  final int maxRows;
  final int maxColumns;
  final DisplayTarget type;

  const DisplayTargetStats(this.maxRows, this.maxColumns, this.type);
}

/// A scoreboard line (`PlayerScore`).
final class ScoreLine {
  final String owner;
  final int value;

  const ScoreLine(this.owner, this.value);
}

/// What the display sources and targets may ask of the world. Implemented over the host
/// (`HostDisplayEnv`) and by fakes in tests. Everything that is another module's data goes
/// through the provider interfaces of `api/redstone.dart`.
abstract interface class DisplayEnv {
  /// `World.getId()` of the world the display link is in.
  String get worldId;

  /// `level.getGameTime()`.
  int get gameTime;

  /// `level.getOverworldClockTime()`.
  int get overworldClockTime;

  /// `!dimensionType.hasFixedTime()`.
  bool get naturalDimension;

  /// `RandomSource.nextInt(bound)`.
  int nextInt(int bound);

  /// The block state at [pos] (air when unloaded).
  BState stateAt(Pos pos);

  /// `BlockState.is(TagKey)` for the block at [pos].
  bool blockHasTag(Pos pos, String tag);

  /// `level.getDirectSignalTo(pos)`.
  Future<int> directSignalTo(Pos pos);

  // -- Block entities of this module --------------------------------------------------------

  /// The text a nixie tube shows (`getFullText`), `null` if there is no tube at [pos].
  Txt? nixieText(Pos pos);

  /// The levels of the threshold switch at [pos], `null` if there is none.
  ({int level, int min, int max})? thresholdLevels(Pos pos);

  /// What the smart observer at [pos] sees through its filter, `null` if there is no observer.
  Future<ObserverView?> observerView(Pos pos);

  // -- Scoreboards ----------------------------------------------------------------------------

  /// The scores of objective [name], `null` if there is no such objective.
  Future<List<ScoreLine>?> scoresOf(String name);

  /// `StatTrackingDisplaySource`: updates the auto objective `create_auto_<stat>` (`deaths`) with
  /// the stat of every online player and returns its scores, players seen earlier included.
  Future<List<ScoreLine>> trackedStat(String stat, String displayName);

  // -- Other modules' data (each may be unavailable) -----------------------------------------

  double? kineticSpeedAt(Pos pos);
  ({double stress, double capacity})? networkStressAt(Pos pos);
  double? cuckooClockSpeedAt(Pos pos);
  ({Txt heatLevel, Txt size, Txt water, Txt heat})? boilerTexts(Pos pos, {required bool forFlapDisplay});
  String? elevatorFloorAt(Pos pos);
  String? centeredItemNameAt(Pos pos);
  String? seatPassengerNameAt(Pos pos);
  Txt? observedTrainNameAt(Pos pos);
  Txt? trainStatusAt(Pos pos);
  String? stationNameAt(Pos pos);
  List<TrainPredictionView> trainPredictions(String filter, int maxRows);
  List<GaugeEntryView> factoryGaugeEntries(List<(Pos pos, String slot)> panels);

  // -- Targets ------------------------------------------------------------------------------------

  /// `SignDisplayTarget`: sets the lines of the sign at [pos] (both sides); false if there is no sign.
  Future<bool> writeSignLines(Pos pos, Map<int, String> lines);

  /// `LecternDisplayTarget`: the book on the lectern at [pos] as pages (JSON text components),
  /// `null` when there is no lectern or no book.
  Future<LecternBookView?> lecternBook(Pos pos);

  /// Replaces the pages of the written book on the lectern at [pos].
  Future<void> setLecternPages(Pos pos, List<Object?> pagesJson);

  /// `NixieTubeBlock.walkNixies(level, pos, false, ...)`: the row of tubes with their index.
  List<(Pos, int)> nixieRow(Pos pos);

  /// `NixieTubeBlockEntity.displayCustomText(tag, rowPosition)`.
  void setNixieText(Pos pos, String jsonText, int rowPosition);

  /// The controller of the display board at [pos], `null` if there is none.
  FlapControllerView? flapController(Pos pos);

  /// `DisplayTarget.reserve` / `isReserved` storage: the display link (as a position) that
  /// reserved [line] of [target], or null.
  Pos? reservedBy(Pos target, int line);
  void setReservation(Pos target, int line, Pos? link);
}

/// A book on a lectern.
final class LecternBookView {
  /// `true` for a writable book (it is signed by the first write), `false` for a written one.
  final bool writable;

  /// The pages as JSON text components (a writable book's plain text pages as strings).
  final List<Object?> pages;

  const LecternBookView({required this.writable, required this.pages});
}

/// The controller of a (multi block) display board (`FlapDisplayBlockEntity.getController`),
/// implemented by the decoration module.
abstract interface class FlapControllerView {
  Pos get pos;
  int get xSize;
  int get ySize;

  /// `getMaxCharCount()`.
  int get maxCharCount;

  /// `getMaxCharCount(gaps)`.
  int maxCharCountFor(int gaps);

  /// `isSpeedRequirementFulfilled()`.
  bool get speedRequirementFulfilled;

  /// The number of text lines (`getLines().size()`).
  int get lineCount;

  /// `manualLines[line]`.
  bool isManualLine(int line);

  /// Sets the sections of line [line] to [texts] (`layout.getSections().get(i).setText(...)`);
  /// [layout] is the layout the source configured (`loadFlapDisplayLayout`).
  void setLine(int line, List<String> texts, {required FlapLayoutSpec layout});

  /// `applyTextManually(line, null)`: clears the line.
  void clearLine(int line);

  /// `sendData()`.
  void sendData();
}

/// A `FlapDisplaySection` as a source configures it (`createSectionForValue`).
final class FlapSectionSpec {
  /// `FlapDisplaySection.MONOSPACE`.
  static const double monospace = 7;

  /// Width in pixels (`FlapDisplaySection.size`).
  final double width;
  final String cycle;
  final bool singleFlap;
  final bool hasGap;
  final bool rightAligned;
  final bool wideFlaps;

  const FlapSectionSpec(
    this.width,
    this.cycle, {
    this.singleFlap = false,
    this.hasGap = false,
    this.rightAligned = false,
    this.wideFlaps = false,
  });
}

/// What a source wants on one line of a flap display (`loadFlapDisplayLayout`).
final class FlapLayoutSpec {
  /// `FlapDisplayLayout.layoutKey`.
  final String key;

  /// The sections, `null` to keep/load the default layout (`loadDefault`).
  final List<FlapSectionSpec>? sections;

  const FlapLayoutSpec(this.key, this.sections);

  /// `layout.loadDefault(flapDisplay.getMaxCharCount())`.
  const FlapLayoutSpec.defaultLayout() : key = 'Default', sections = null;
}

/// A smart observer's view of its target (`SmartObserverBlockEntity` + filter).
final class ObserverView {
  /// Items in the observed inventory that the filter accepts: `(item key, display name, count)`.
  final List<ObservedItem> items;

  /// Fluids in the observed tanks that the filter accepts.
  final List<ObservedFluid> fluids;

  /// The address of the first package in the target (inventory or chain conveyor) that passes the filter.
  final String? packageAddress;

  /// Whether the observer has an item inventory / a tank.
  final bool hasInventory;
  final bool hasTank;

  const ObserverView({
    this.items = const [],
    this.fluids = const [],
    this.packageAddress,
    this.hasInventory = false,
    this.hasTank = false,
  });
}

final class ObservedItem {
  final String key;
  final String name;
  final int count;

  const ObservedItem(this.key, this.name, this.count);
}

final class ObservedFluid {
  final String key;
  final String name;
  final int amount;

  const ObservedFluid(this.key, this.name, this.amount);
}

/// One arrival prediction of a train station summary (`GlobalTrainDisplayData.TrainDeparturePrediction`).
final class TrainPredictionView {
  final int ticks;
  final Txt trainName;
  final Txt scheduleTitle;
  final String destination;

  const TrainPredictionView(this.ticks, this.trainName, this.scheduleTitle, this.destination);
}

/// A factory gauge line of `FactoryGaugeDisplaySource`.
final class GaugeEntryView {
  final int levelInStorage;
  final String filterName;
  final int demand;
  final int promised;
  final bool satisfied;
  final int statusColor;

  const GaugeEntryView({
    required this.levelInStorage,
    required this.filterName,
    required this.demand,
    required this.promised,
    required this.satisfied,
    required this.statusColor,
  });
}

/// `DisplayLinkContext`.
final class DisplayLinkContext {
  final DisplayEnv env;

  /// The display link block.
  final Pos linkPos;

  /// `getSourcePos()` / `getTargetPos()`.
  final Pos sourcePos;
  final Pos targetPos;

  /// `sourceConfig()`; the sources read and change it.
  final ConfigTag sourceConfig;

  /// `blockEntity().activeTarget`.
  final DisplayTarget? activeTarget;

  /// The block the display link is attached to and its `getDirection()`.
  final Direction direction;

  /// The panels connected to the link (`factoryPanelSupport.getLinkedPanels()`).
  final List<(Pos pos, String slot)> linkedPanels;

  /// `flapDisplayContext`.
  Object? flapDisplayContext;

  /// `context.blockEntity().award(advancement)`: awards [id] to the player that placed this
  /// display link. The station summary gives the display board advancement through it, like
  /// `StationSummaryDisplaySource.java:105-108`.
  final void Function(String advancement)? award;

  DisplayLinkContext({
    required this.env,
    required this.linkPos,
    required this.sourcePos,
    required this.targetPos,
    required this.sourceConfig,
    required this.direction,
    this.activeTarget,
    this.linkedPanels = const [],
    this.award,
  });

  /// The block at the source / target position.
  BState get sourceState => env.stateAt(sourcePos);
  BState get targetState => env.stateAt(targetPos);
}

/// `DisplaySource`.
abstract class DisplaySource {
  static final List<Txt> emptyList = [Txt.empty()];
  static Txt get emptyLine => _emptyLine;
  static final Txt _emptyLine = Txt.empty();
  static Txt get whitespace => Txt.space();

  /// `create:<path>`.
  String get id;

  /// `getTranslationKey()`, the lang key of the source's name (`create.display_source.<key>`).
  String get translationKey => id.substring(id.indexOf(':') + 1);

  /// `provideText`.
  Future<List<Txt>> provideText(DisplayLinkContext context, DisplayTargetStats stats);

  /// `provideFlapDisplayText`: one list of section texts per row.
  Future<List<List<Txt>>> provideFlapDisplayText(DisplayLinkContext context, DisplayTargetStats stats) async =>
      [for (final t in await provideText(context, stats)) [t]];

  /// `getFlapDisplayLayoutName(context)`.
  String getFlapDisplayLayoutName(DisplayLinkContext context) => 'Default';

  /// `createSectionForValue(context, size)`: the section the value of a single line source gets.
  FlapSectionSpec createSectionForValue(DisplayLinkContext context, int size) =>
      FlapSectionSpec(size * FlapSectionSpec.monospace, 'alphabet');

  /// `loadFlapDisplayLayout(context, flapDisplay, layout, lineIndex)`: the layout of one line.
  /// [lineIndex] is the index of the row within the source's text (`0` for the first row).
  FlapLayoutSpec loadFlapDisplayLayout(DisplayLinkContext context, FlapControllerView flap, int lineIndex) =>
      FlapLayoutSpec(getFlapDisplayLayoutName(context), [createSectionForValue(context, flap.maxCharCount)]);

  /// `transferData`: pushes the text into [activeTarget] starting at [line].
  Future<void> transferData(DisplayLinkContext context, DisplayTarget activeTarget, int line) async {
    final stats = await activeTarget.provideStats(context);

    if (activeTarget is FlapTarget) {
      final flapText = await provideFlapDisplayText(context, stats);
      await (activeTarget as FlapTarget).acceptFlapText(line, flapText, context, this);
    }

    var text = await provideText(context, stats);
    if (text.isEmpty) text = emptyList;

    if (activeTarget.requiresComponentSanitization) {
      for (final component in text) {
        if (hasClickEvent(component)) return; // Naughty
      }
    }
    await activeTarget.acceptText(line, text, context);
  }

  /// `onSignalReset`.
  void onSignalReset(DisplayLinkContext context) {}

  /// `populateData`.
  void populateData(DisplayLinkContext context) {}

  /// `getPassiveRefreshTicks`.
  int get passiveRefreshTicks => 100;

  /// `shouldPassiveReset`.
  bool get shouldPassiveReset => true;

  /// Components made here carry no click events.
  static bool hasClickEvent(Txt t) => false;
}

/// A display board target (`DisplayBoardTarget`) takes row texts instead of lines.
abstract interface class FlapTarget {
  Future<void> acceptFlapText(int line, List<List<Txt>> text, DisplayLinkContext context, DisplaySource source);
}

/// `DisplayTarget`.
abstract class DisplayTarget {
  /// `create:<path>`.
  String get id;

  /// `acceptText`.
  Future<void> acceptText(int line, List<Txt> text, DisplayLinkContext context);

  /// `provideStats`.
  Future<DisplayTargetStats> provideStats(DisplayLinkContext context);

  /// `requiresComponentSanitization`.
  bool get requiresComponentSanitization => false;

  /// `reserve(line, target, context)`: line 0 is never reserved.
  void reserve(int line, Pos target, DisplayLinkContext context) {
    if (line == 0) return;
    context.env.setReservation(target, line, context.linkPos);
  }

  /// `isReserved(line, target, context)`: another display link holds the line. A reservation
  /// by a block that is no longer a display link is dropped.
  bool isReserved(int line, Pos target, DisplayLinkContext context) {
    final reserved = context.env.reservedBy(target, line);
    if (reserved == null) return false;
    if (reserved != context.linkPos && context.env.stateAt(reserved).isBlock('create:display_link')) return true;
    context.env.setReservation(target, line, null);
    return false;
  }
}

/// The associations of sources and targets with blocks (`DisplaySource.BY_BLOCK`,
/// `DisplayTarget.BY_BLOCK`) and the registries by id.
final class DisplayRegistry {
  final Map<String, DisplaySource> sourcesById = {};
  final Map<String, DisplayTarget> targetsById = {};
  final Map<String, List<DisplaySource>> _sourcesByBlock = {};
  final Map<String, DisplayTarget> _targetsByBlock = {};

  /// Legacy names (`AllDisplaySources.LEGACY_NAMES`): old ids to the new path.
  final Map<String, String> legacySourceNames = {};
  final Map<String, String> legacyTargetNames = {};

  /// Blocks matched by a predicate rather than a key (modded signs).
  final List<(bool Function(String key), DisplayTarget)> targetPredicates = [];

  void addSource(DisplaySource source) => sourcesById[source.id] = source;

  void addTarget(DisplayTarget target) => targetsById[target.id] = target;

  /// `DisplaySource.BY_BLOCK.add(block, source)`.
  void associateSource(Iterable<String> blockKeys, DisplaySource source) {
    for (final k in blockKeys) {
      final list = _sourcesByBlock.putIfAbsent(k, () => []);
      if (!list.contains(source)) list.add(source);
    }
  }

  /// `DisplayTarget.BY_BLOCK.register(block, target)`.
  void associateTarget(Iterable<String> blockKeys, DisplayTarget target) {
    for (final k in blockKeys) {
      _targetsByBlock[k] = target;
    }
  }

  /// `DisplaySource.get(id)`.
  DisplaySource? source(String? id) {
    if (id == null) return null;
    if (id.startsWith('create:')) {
      final legacy = legacySourceNames[id.substring(7)];
      if (legacy != null) return sourcesById['create:$legacy'];
    }
    return sourcesById[id];
  }

  /// `DisplayTarget.get(id)`.
  DisplayTarget? target(String? id) {
    if (id == null) return null;
    if (id.startsWith('create:')) {
      final legacy = legacyTargetNames[id.substring(7)];
      if (legacy != null) return targetsById['create:$legacy'];
    }
    return targetsById[id];
  }

  /// `DisplaySource.getAll(level, pos)`.
  List<DisplaySource> sourcesAt(String blockKey) => _sourcesByBlock[blockKey] ?? const [];

  /// `DisplayTarget.get(level, pos)`.
  DisplayTarget? targetAt(String blockKey) {
    final byBlock = _targetsByBlock[blockKey];
    if (byBlock != null) return byBlock;
    for (final (test, target) in targetPredicates) {
      if (test(blockKey)) return target;
    }
    return null;
  }
}
