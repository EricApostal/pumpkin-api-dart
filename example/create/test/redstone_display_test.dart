import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/redstone/display/config_tag.dart';
import 'package:create/src/redstone/display/display_core.dart';
import 'package:create/src/redstone/display/display_sources.dart';
import 'package:create/src/redstone/display/display_targets.dart';
import 'package:create/src/redstone/display/reservations.dart';
import 'package:create/src/redstone/support/text.dart';
import 'package:test/test.dart';

class FakeDisplayEnv implements DisplayEnv {
  FakeDisplayEnv();

  final Map<Pos, BState> blocks = {};
  final Map<Pos, int> directSignals = {};
  final Map<Pos, Txt> nixies = {};
  final Map<Pos, ({int level, int min, int max})> thresholds = {};
  final Map<Pos, ObserverView> observers = {};
  final Map<String, List<ScoreLine>> scores = {};
  final Map<Pos, double> speeds = {};
  final Map<Pos, ({double stress, double capacity})> stresses = {};
  final Map<Pos, double> clocks = {};
  final Map<Pos, String> floors = {};
  final Map<Pos, String> itemNames = {};
  final Map<Pos, String> seats = {};
  final Set<String> tags = {};
  List<TrainPredictionView> predictions = [];
  List<GaugeEntryView> gauges = [];
  ({Txt heatLevel, Txt size, Txt water, Txt heat})? boiler;
  int time = 0;
  int clock = 0;
  bool natural = true;
  final Map<(Pos, int), Pos> reservations = {};
  final Map<Pos, Map<int, String>> signs = {};
  final Map<Pos, List<(Pos, int)>> rows = {};
  final List<(Pos, String, int)> nixieWrites = [];
  LecternBookView? book;
  List<Object?>? writtenPages;
  FlapControllerView? flap;

  @override
  String get worldId => 'w';
  @override
  int get gameTime => time;
  @override
  int get overworldClockTime => clock;
  @override
  bool get naturalDimension => natural;
  @override
  int nextInt(int bound) => 0;
  @override
  BState stateAt(Pos pos) => blocks[pos] ?? BState.air;
  @override
  bool blockHasTag(Pos pos, String tag) => tags.contains('${stateAt(pos).key}#$tag');
  @override
  Future<int> directSignalTo(Pos pos) async => directSignals[pos] ?? 0;
  @override
  Txt? nixieText(Pos pos) => nixies[pos];
  @override
  ({int level, int min, int max})? thresholdLevels(Pos pos) => thresholds[pos];
  @override
  Future<ObserverView?> observerView(Pos pos) async => observers[pos];
  @override
  Future<List<ScoreLine>?> scoresOf(String name) async => scores[name];
  @override
  Future<List<ScoreLine>> trackedStat(String stat, String displayName) async => scores['create_auto_$stat'] ?? [];
  @override
  double? kineticSpeedAt(Pos pos) => speeds[pos];
  @override
  ({double stress, double capacity})? networkStressAt(Pos pos) => stresses[pos];
  @override
  double? cuckooClockSpeedAt(Pos pos) => clocks[pos];
  @override
  ({Txt heatLevel, Txt size, Txt water, Txt heat})? boilerTexts(Pos pos, {required bool forFlapDisplay}) => boiler;
  @override
  String? elevatorFloorAt(Pos pos) => floors[pos];
  @override
  String? centeredItemNameAt(Pos pos) => itemNames[pos];
  @override
  String? seatPassengerNameAt(Pos pos) => seats[pos];
  @override
  Txt? observedTrainNameAt(Pos pos) => null;
  @override
  Txt? trainStatusAt(Pos pos) => null;
  @override
  String? stationNameAt(Pos pos) => 'Central';
  @override
  List<TrainPredictionView> trainPredictions(String filter, int maxRows) => predictions;
  @override
  List<GaugeEntryView> factoryGaugeEntries(List<(Pos pos, String slot)> panels) => gauges;
  @override
  Future<bool> writeSignLines(Pos pos, Map<int, String> lines) async {
    signs.putIfAbsent(pos, () => {}).addAll(lines);
    return true;
  }

  @override
  Future<LecternBookView?> lecternBook(Pos pos) async => book;
  @override
  Future<void> setLecternPages(Pos pos, List<Object?> pagesJson) async => writtenPages = pagesJson;
  @override
  List<(Pos, int)> nixieRow(Pos pos) => rows[pos] ?? [];
  @override
  void setNixieText(Pos pos, String jsonText, int rowPosition) => nixieWrites.add((pos, jsonText, rowPosition));
  @override
  FlapControllerView? flapController(Pos pos) => flap;
  @override
  Pos? reservedBy(Pos target, int line) => reservations[(target, line)];
  @override
  void setReservation(Pos target, int line, Pos? link) {
    if (link == null) {
      reservations.remove((target, line));
    } else {
      reservations[(target, line)] = link;
    }
  }
}

class FakeLink implements GatheredDataLink {
  FakeLink(this.sourceConfig, {this.isPowered = false, this.gameTime = 0});

  @override
  final ConfigTag sourceConfig;
  @override
  bool isPowered;
  @override
  int gameTime;
  int updates = 0;

  @override
  Future<void> updateGatheredData() async => updates++;
}

class FakeFlap implements FlapControllerView {
  final Map<int, FlapLayoutSpec> layouts = {};

  @override
  Pos get pos => (0, 64, 0);
  @override
  int get xSize => 3;
  @override
  int get ySize => 1;
  @override
  int get maxCharCount => ((xSize * 16 - 2) / 3.5).toInt();
  @override
  int maxCharCountFor(int gaps) => ((xSize * 16 - 2 - 4 * gaps) / 3.5).toInt();
  @override
  bool get speedRequirementFulfilled => true;
  @override
  int get lineCount => 2;
  @override
  bool isManualLine(int line) => false;
  @override
  void setLine(int line, List<String> texts, {required FlapLayoutSpec layout}) => layouts[line] = layout;
  @override
  void clearLine(int line) {}
  @override
  void sendData() {}
}

const link = (10, 64, 10);
const source = (10, 64, 11);
const target = (20, 70, 20);

DisplayLinkContext ctx(FakeDisplayEnv env, {ConfigTag? config, DisplayTarget? activeTarget, List<(Pos, String)> panels = const []}) =>
    DisplayLinkContext(
      env: env,
      linkPos: link,
      sourcePos: source,
      targetPos: target,
      sourceConfig: config ?? ConfigTag(),
      direction: Direction.south,
      activeTarget: activeTarget,
      linkedPanels: panels,
    );

Future<List<String>> text(DisplaySource s, DisplayLinkContext c, {int rows = 4, int columns = 15}) async {
  final stats = DisplayTargetStats(rows, columns, SignDisplayTarget());
  return [for (final t in await s.provideText(c, stats)) t.plain];
}

void main() {
  late FakeDisplayEnv env;

  setUp(() => env = FakeDisplayEnv());

  group('Txt and number formatting', () {
    test('plain text of siblings and translations', () {
      final t = Txt.literal('a').append(Txt.translate('create.generic.unit.rpm')).appendText('!');
      expect(t.plain, 'aRPM!');
      expect(Txt.translate('create.boiler.status_short', [Txt.literal('Idle')]).plain, 'Boiler:  Idle');
      expect(Txt.translate('no.such.key').plain, 'no.such.key');
    });

    test('json forms', () {
      expect(Txt.literal('x').toJson(), 'x');
      expect(Txt.literal('x').withColor(0xff0000).toJson(), {'text': 'x', 'color': '#ff0000'});
      expect(plainTextOfJson(['a', {'text': 'b', 'extra': ['c']}]), 'abc');
      expect(plainTextOfJson({'translate': 'create.boiler.size'}), 'Size');
      expect(tryParseJson('{'), isNull);
    });

    test('formatNumber groups and keeps two decimals', () {
      expect(formatNumber(1234.5), '1,234.5');
      expect(formatNumber(256), '256');
      expect(formatNumber(0.126), '0.13');
      expect(formatNumber(-1234567.891), '-1,234,567.89');
      expect(formatNumber(0), '0');
    });
  });

  group('single line sources', () {
    test('redstone power: number and progress bar', () async {
      env.blocks[source] = const BState('minecraft:target', {'power': '9'});
      env.directSignals[source] = 6;
      final s = RedstonePowerDisplaySource();
      expect(await text(s, ctx(env)), ['9']);
      expect(await text(s, ctx(env, config: ConfigTag()..putInt('Mode', 1)), columns: 10), ['██████▒▒▒▒']);

      env.blocks[source] = const BState('minecraft:target', {'power': '3'});
      env.directSignals[source] = 15;
      expect(await text(s, ctx(env)), ['15']);
    });

    test('the label is prepended', () async {
      env.blocks[source] = const BState('minecraft:target', {'power': '9'});
      final c = ctx(env, config: ConfigTag()..putString('Label', 'Power:'));
      expect(await text(RedstonePowerDisplaySource(), c), ['Power: 9']);
    });

    test('an empty line gives the empty list', () async {
      final s = CurrentFloorDisplaySource();
      final stats = DisplayTargetStats(4, 15, SignDisplayTarget());
      final out = await s.provideText(ctx(env), stats);
      expect(out.length, 1);
      expect(out.first.plain, '');
      env.floors[source] = '2';
      expect(await text(s, ctx(env)), ['2']);
    });

    test('kinetic speed: absolute or directional, with the unit', () async {
      env.speeds[source] = -64;
      final s = KineticSpeedDisplaySource();
      expect(await text(s, ctx(env)), ['64 RPM']);
      expect(await text(s, ctx(env, config: ConfigTag()..putInt('Directional', 1))), ['-64 RPM']);
      env.speeds.clear();
      expect(await text(s, ctx(env)), ['0']);
    });

    test('kinetic stress modes', () async {
      env.stresses[source] = (stress: 512, capacity: 2048);
      final s = KineticStressDisplaySource();
      Future<List<String>> mode(int m) => text(s, ctx(env, config: ConfigTag()..putInt('Mode', m)), columns: 8);
      expect(await mode(0), ['██▒▒▒▒▒▒']);
      expect(await mode(1), ['25%']);
      expect(await mode(2), ['512su']);
      expect(await mode(3), ['2,048su']);
      expect(await mode(4), ['1,536su']);
    });

    test('fill level reads the threshold switch', () async {
      env.thresholds[source] = (level: 32, min: 0, max: 64);
      final s = FillLevelDisplaySource();
      expect(await text(s, ctx(env)), ['50%']);
      env.thresholds[source] = (level: -1, min: -1, max: -1);
      expect(await text(s, ctx(env)), ['0%']);
    });

    test('time of day formats 12 and 24 hour clocks', () async {
      env.clocks[source] = 16;
      env.clock = 6000; // noon: (6000/1000 + 6) % 24 = 12
      final s = TimeOfDayDisplaySource();
      expect(await text(s, ctx(env)), ['12:00 pm']);
      expect(await text(s, ctx(env, config: ConfigTag()..putInt('Cycle', 1))), ['12:00']);
      env.clock = 0; // 6 am
      expect(await text(s, ctx(env)), [' 6:00 am']);
      env.clock = 18000; // midnight
      expect(await text(s, ctx(env)), ['12:00 am']);
      env.clock = 1500; // 7:30, minutes in steps of five
      expect(await text(s, ctx(env)), [' 7:30 am']);
      env.clocks[source] = 0;
      expect(await text(s, ctx(env)), ['--:--']);
    });

    test('stopwatch counts from the first read', () async {
      env.clocks[source] = 8;
      final s = StopWatchDisplaySource();
      env.time = 1000;
      final c = ctx(env);
      expect(await text(s, c), [' 0:00']);
      env.time = 1000 + 20 * 75 + 5;
      expect(await text(s, c), [' 1:15']);
      env.time = 1000 + 20 * 3600 * 2 + 20 * 60 * 5 + 20 * 7;
      expect(await text(s, c), [' 2:05:07']);
      s.onSignalReset(c);
      expect(c.sourceConfig.getLongOr('StartTime', 0), env.time);
    });

    test('enchant power counts bookshelves with a transmitting block between', () async {
      env.blocks[source] = const BState('minecraft:enchanting_table');
      for (final off in EnchantPowerDisplaySource.bookshelfOffsets.take(5)) {
        final shelf = source + off;
        env.blocks[shelf] = const BState('minecraft:bookshelf');
        env.tags.add('minecraft:bookshelf#minecraft:enchantment_power_provider');
        env.blocks[source.offset(off.x ~/ 2, off.y, off.z ~/ 2)] = BState.air;
        env.tags.add('minecraft:air#minecraft:enchantment_power_transmitter');
      }
      final out = int.parse((await text(EnchantPowerDisplaySource(), ctx(env))).single);
      // 5 shelves: cost = max(i, 10) with i >= 1 + 2 + 0
      expect(out, greaterThanOrEqualTo(10));
      env.blocks[source] = BState.air;
      expect(await text(EnchantPowerDisplaySource(), ctx(env)), ['0']);
    });

    test('item names combine along the direction until a block without belt behaviour', () async {
      env.itemNames[source] = 'Iron Ingot';
      env.itemNames[source.relative(Direction.south)] = '';
      env.itemNames[source.relative(Direction.south, 2)] = 'Gold Ingot';
      final s = ItemNameDisplaySource();
      expect(await text(s, ctx(env)), ['Iron IngotGold Ingot']);
    });

    test('entity name of a seat', () async {
      env.seats[source] = 'Steve';
      expect(await text(EntityNameDisplaySource(), ctx(env)), ['Steve']);
      env.seats[source] = '';
      expect(await text(EntityNameDisplaySource(), ctx(env)), ['']);
    });

    test('nixie tube text, numeric detection', () async {
      env.nixies[source] = Txt.literal('12');
      final c = ctx(env);
      expect(await text(NixieTubeDisplaySource(), c), ['12']);
      expect(c.flapDisplayContext, true);
      // no label when the target is a nixie row
      final c2 = ctx(env, config: ConfigTag()..putString('Label', 'N:'), activeTarget: NixieTubeDisplayTarget());
      expect(await text(NixieTubeDisplaySource(), c2), ['12']);
      expect(await text(NixieTubeDisplaySource(), ctx(env, config: ConfigTag()..putString('Label', 'N:'))), ['N: 12']);
    });

    test('package address from the observer', () async {
      env.observers[source] = const ObserverView(packageAddress: 'Home', hasInventory: true);
      expect(await text(PackageAddressDisplaySource(), ctx(env)), ['Home']);
    });
  });

  group('observer sources', () {
    setUp(() {
      env.observers[source] = const ObserverView(
        hasInventory: true,
        hasTank: true,
        items: [
          ObservedItem('minecraft:iron_ingot', 'Iron Ingot', 40),
          ObservedItem('minecraft:gold_ingot', 'Gold Ingot', 80),
          ObservedItem('minecraft:iron_ingot', 'Iron Ingot', 30),
        ],
        fluids: [ObservedFluid('minecraft:water', 'Water', 2500), ObservedFluid('minecraft:lava', 'Lava', 300)],
      );
    });

    test('count items', () async {
      expect(await text(ItemCountDisplaySource(), ctx(env)), ['150']);
      env.observers.clear();
      expect(await text(ItemCountDisplaySource(), ctx(env)), ['0']);
    });

    test('list items: summed per item, the biggest first, value first', () async {
      final out = await text(ItemListDisplaySource(), ctx(env, config: ConfigTag()..putInt('Format', 1)));
      expect(out, ['80 Gold Ingot ', '70 Iron Ingot ']);
      final shortened = await text(ItemListDisplaySource(), ctx(env));
      expect(shortened, ['80 Gold Ingot ', '70 Iron Ingot ']);
    });

    test('list items shortens thousands and millions', () async {
      env.observers[source] = const ObserverView(
        hasInventory: true,
        items: [ObservedItem('a:b', 'Big', 12500), ObservedItem('a:c', 'Huge', 3000000)],
      );
      expect(await text(ItemListDisplaySource(), ctx(env)), ['3m Huge ', '12k Big ']);
    });

    test('fluid amount and list', () async {
      expect(await text(FluidAmountDisplaySource(), ctx(env)), ['2800 mB']);
      expect(await text(FluidListDisplaySource(), ctx(env, config: ConfigTag()..putInt('Format', 1))), ['2500mBWater ', '300mBLava ']);
      expect(await text(FluidListDisplaySource(), ctx(env)), ['2.5BWater ', '300mBLava ']);
    });

    test('a lectern target packs entries into pages of eight lines', () async {
      env.observers[source] = ObserverView(
        hasInventory: true,
        items: [for (var i = 0; i < 20; i++) ObservedItem('a:i$i', 'I$i', 100 - i)],
      );
      env.blocks[target] = const BState('minecraft:lectern');
      final out = await text(ItemListDisplaySource(), ctx(env), rows: 2);
      expect(out.length, 2); // 2 rows x 8 entries per page
      expect(out.first.split('\n').length, 8);
    });
  });

  group('item counting sources', () {
    test('accumulate items adds to Collected unless powered', () async {
      final s = AccumulatedItemCountDisplaySource();
      final l = FakeLink(ConfigTag());
      await s.itemReceived(l, 3);
      await s.itemReceived(l, 4);
      expect(l.sourceConfig.getIntOr('Collected', 0), 7);
      expect(l.updates, 2);
      l.isPowered = true;
      await s.itemReceived(l, 100);
      expect(l.sourceConfig.getIntOr('Collected', 0), 7);

      expect(await text(s, ctx(env, config: l.sourceConfig)), ['7']);
      s.onSignalReset(ctx(env, config: l.sourceConfig));
      expect(l.sourceConfig.contains('Collected'), isFalse);
    });

    test('item throughput averages the last intervals', () async {
      final s = ItemThroughputDisplaySource();
      final l = FakeLink(ConfigTag(), gameTime: 100);
      await s.itemReceived(l, 4); // first item only records the time
      expect(l.sourceConfig.contains('Rate'), isFalse);
      l.gameTime = 120;
      await s.itemReceived(l, 4); // 4 items in 20 ticks = 0.2/tick
      expect(l.sourceConfig.getFloatOr('Rate', 0), closeTo(0.2, 1e-6));
      l.gameTime = 140;
      await s.itemReceived(l, 8); // 0.4/tick, average 0.3
      expect(l.sourceConfig.getFloatOr('Rate', 0), closeTo(0.3, 1e-6));

      env.time = 141;
      // per second: 0.3 * 20
      expect(await text(s, ctx(env, config: l.sourceConfig)), ['6']);
      // per minute: 0.3 * 1200
      l.sourceConfig.putInt('Interval', 1);
      expect(await text(s, ctx(env, config: l.sourceConfig)), ['360']);
      // too long since the last item: inactive and zero
      env.time = 140 + 1000;
      expect(await text(s, ctx(env, config: l.sourceConfig)), ['0']);
      expect(l.sourceConfig.contains('Inactive'), isTrue);
      // a new item reactivates
      l.gameTime = 1200;
      await s.itemReceived(l, 4);
      expect(l.sourceConfig.contains('Inactive'), isFalse);
      expect(s.passiveRefreshTicks, 200);
    });
  });

  group('list sources', () {
    test('scoreboard: sorted by score, the missing objective is a 404 line', () async {
      env.scores['kills'] = [const ScoreLine('b', 3), const ScoreLine('a', 9), const ScoreLine('c', 3)];
      final s = ScoreboardDisplaySource();
      final c = ctx(env, config: ConfigTag()..putString('Objective', 'kills')..putInt('Format', 1));
      expect(await text(s, c), ['a 9 ', 'b 3 ', 'c 3 ']);
      expect(await text(s, ctx(env, config: ConfigTag()..putString('Objective', 'none')..putInt('Format', 1))),
          ["'none' not found 404 "]);
      expect(await text(s, c, rows: 2), ['a 9 ', 'b 3 ']);
    });

    test('death counter lists the tracked scores without shortening', () async {
      env.scores['create_auto_deaths'] = [const ScoreLine('x', 1500)];
      expect(await text(DeathCounterDisplaySource(), ctx(env)), ['x 1500 ']);
    });

    test('factory gauge status marks', () async {
      env.gauges = [
        const GaugeEntryView(levelInStorage: 12, filterName: 'Gear', demand: 64, promised: 0, satisfied: true, statusColor: 0x00ff00),
        const GaugeEntryView(levelInStorage: 3, filterName: 'Shaft', demand: 64, promised: 10, satisfied: false, statusColor: 0xffff00),
        const GaugeEntryView(levelInStorage: 0, filterName: 'Plate', demand: 64, promised: 0, satisfied: false, statusColor: 0xff0000),
        const GaugeEntryView(levelInStorage: 0, filterName: 'None', demand: 0, promised: 0, satisfied: false, statusColor: 0),
      ];
      final out = await text(FactoryGaugeDisplaySource(), ctx(env, panels: [(source, 'top_left')], config: ConfigTag()..putInt('Format', 1)), rows: 3);
      expect(out, ['12 ✔ Gear ', '3 ↑ Shaft ', '0 ▪ Plate ']);
      expect(await text(FactoryGaugeDisplaySource(), ctx(env)), isEmpty); // no panels -> no rows
    });
  });

  group('boiler and trains', () {
    test('the boiler needs room', () async {
      final s = BoilerDisplaySource();
      expect(await text(s, ctx(env), rows: 1), ['Not enough space for Boiler Status']);
      expect(await text(s, ctx(env), rows: 3), ['Not enough space ', 'for Boiler Status']);
      env.boiler = (heatLevel: Txt.literal('Idle'), size: Txt.literal('3'), water: Txt.literal('2'), heat: Txt.literal('1'));
      expect(await text(s, ctx(env), rows: 4), ['Boiler:  Idle', '3', '2', '1']);
    });

    test('flap layouts come from the source and its configuration', () {
      final flap = FakeFlap();

      final summary = ctx(
        env,
        config: ConfigTag()
          ..putString('Filter', 'Central *')
          ..putInt('NameColumn', 50)
          ..putInt('PlatformColumn', 3),
      );
      final summaryLayout = StationSummaryDisplaySource().loadFlapDisplayLayout(summary, flap, 0);
      expect(summaryLayout.key, 'StationSummary50true3');
      expect(summaryLayout.sections, hasLength(5));

      final boiler = ctx(env);
      boiler.flapDisplayContext = false;
      expect(BoilerDisplaySource().loadFlapDisplayLayout(boiler, flap, 1).sections, isNull);
      boiler.flapDisplayContext = true;
      expect(BoilerDisplaySource().loadFlapDisplayLayout(boiler, flap, 0).sections, isNull);
      final boilerLayout = BoilerDisplaySource().loadFlapDisplayLayout(boiler, flap, 1);
      expect(boilerLayout.key, 'Boiler');
      expect(boilerLayout.sections, hasLength(2));
      expect(boilerLayout.sections![1].cycle, 'pixel');
      expect(boilerLayout.sections![1].wideFlaps, isTrue);

      final list = ctx(env);
      list.flapDisplayContext = MutableInt(1234);
      final listLayout = ItemListDisplaySource().loadFlapDisplayLayout(list, flap, 0);
      expect(listLayout.key, 'ValueList_true_0');
      expect(listLayout.sections, hasLength(3)); // value, suffix, name

      final fluids = ctx(env);
      fluids.flapDisplayContext = MutableInt(1234);
      final fluidLayout = FluidListDisplaySource().loadFlapDisplayLayout(fluids, flap, 0);
      expect(fluidLayout.key, 'FluidList_5');
      expect([for (final s in fluidLayout.sections!) s.cycle], ['number', 'fluid_units', 'alphabet']);

      final progress = ctx(env, config: ConfigTag()..putInt('Mode', 1));
      final progressLayout = RedstonePowerDisplaySource().loadFlapDisplayLayout(progress, flap, 0);
      expect(progressLayout.key, 'Progress');
      expect(progressLayout.sections!.single.cycle, 'pixel');
      expect(progressLayout.sections!.single.wideFlaps, isTrue);
    });

    test('station summary rows, padding and platform column', () async {
      final s = StationSummaryDisplaySource();
      env.predictions = [
        TrainPredictionView(100, Txt.literal('Express'), Txt.literal('Line 1'), 'Central 2'),
        TrainPredictionView(3000, Txt.literal('Slow'), Txt.literal('Line 2'), 'Central 3'),
        TrainPredictionView(-1, Txt.literal('Lost'), Txt.literal('Line 3'), 'Central 1'),
      ];
      final c = ctx(env, config: ConfigTag()..putString('Filter', 'Central *'));
      final rows = await s.provideFlapDisplayText(c, DisplayTargetStats(4, 20, DisplayBoardTarget()));
      expect(rows.length, 4);
      expect([for (final t in rows[0]) t.plain], [' ', 'now', 'Express', 'Line 1', '2']);
      expect([for (final t in rows[1]) t.plain], ['2', ' min', 'Slow', 'Line 2', '3']);
      expect([for (final t in rows[2]) t.plain], [' ', ' ~ ', 'Lost', 'Line 3', '1']);
      expect(rows[3].length, 5);

      final noPlatform = await s.provideFlapDisplayText(ctx(env), DisplayTargetStats(4, 20, DisplayBoardTarget()));
      expect(noPlatform.last.length, 4);

      final empty = ConfigTag();
      s.populateData(ctx(env, config: empty));
      expect(empty.getStringOr('Filter', ''), 'Central');
      expect(empty.getIntOr('NameColumn', 0), 50);
      expect(empty.getIntOr('PlatformColumn', 0), 3);
    });
  });

  group('targets', () {
    test('sign: writes up to four lines, truncates and reserves lines', () async {
      env.blocks[target] = const BState('minecraft:oak_sign');
      final t = SignDisplayTarget();
      await t.acceptText(1, [Txt.literal('a'), Txt.literal('b'), Txt.literal('c')], ctx(env));
      expect(env.signs[target], {1: 'a', 2: 'b', 3: 'c'});
      // line 0 is never reserved; line 1 was
      expect(env.reservations.containsKey((target, 1)), isTrue);
      expect(env.reservations.containsKey((target, 0)), isFalse);
      expect(t.requiresComponentSanitization, isTrue);
      expect((await t.provideStats(ctx(env))).maxRows, 4);
    });

    test('sign: another display link holding a line stops the write', () async {
      env.blocks[target] = const BState('minecraft:oak_sign');
      env.blocks[(1, 1, 1)] = const BState('create:display_link');
      env.reservations[(target, 1)] = (1, 1, 1);
      await SignDisplayTarget().acceptText(0, [Txt.literal('a'), Txt.literal('b')], ctx(env));
      expect(env.signs[target], {0: 'a'});
    });

    test('sign: a stale reservation is dropped', () async {
      env.blocks[target] = const BState('minecraft:oak_sign');
      env.reservations[(target, 1)] = (1, 1, 1); // not a display link any more
      await SignDisplayTarget().acceptText(0, [Txt.literal('a'), Txt.literal('b')], ctx(env));
      expect(env.signs[target], {0: 'a', 1: 'b'});
    });

    test('lectern: writes the text as pages starting at the line', () async {
      env.blocks[target] = const BState('minecraft:lectern');
      env.book = const LecternBookView(writable: false, pages: ['p0', 'p1']);
      await LecternDisplayTarget().acceptText(1, [Txt.literal('x'), Txt.literal('y')], ctx(env));
      expect(env.writtenPages, ['p0', 'x', 'y']);
    });

    test('lectern: no book, no write', () async {
      env.blocks[target] = const BState('minecraft:lectern');
      await LecternDisplayTarget().acceptText(0, [Txt.literal('x')], ctx(env));
      expect(env.writtenPages, isNull);
    });

    test('nixie row: width is two characters per tube', () async {
      env.rows[target] = [(target, 0), (target.relative(Direction.east), 1)];
      final t = NixieTubeDisplayTarget();
      expect((await t.provideStats(ctx(env))).maxColumns, 4);
      await t.acceptText(0, [Txt.literal('42')], ctx(env));
      expect(env.nixieWrites.map((e) => e.$3), [0, 1]);
      expect(env.nixieWrites.first.$2, '"42"');
    });
  });

  group('registry', () {
    test('sources and targets by block and legacy id', () {
      final r = DisplayRegistry();
      for (final s in createDisplaySources()) {
        r.addSource(s);
      }
      expect(r.sourcesById.length, 26);
      r.legacySourceNames.addAll(legacyDisplaySourceNames);
      r.associateSource(['minecraft:target'], r.sourcesById['create:redstone_power']!);
      expect(r.sourcesAt('minecraft:target').single.id, 'create:redstone_power');
      expect(r.sourcesAt('minecraft:stone'), isEmpty);
      expect(r.source('create:speedometer_source_kinetic_speed')?.id, 'create:kinetic_speed');
      expect(r.source('create:nope'), isNull);

      for (final t in createDisplayTargets()) {
        r.addTarget(t);
      }
      expect(r.targetsById.length, 4);
      r.targetPredicates.add((isSignBlock, r.targetsById['create:sign']!));
      expect(r.targetAt('minecraft:birch_wall_hanging_sign')?.id, 'create:sign');
      expect(r.targetAt('minecraft:stone'), isNull);
    });

    test('the block table covers every source but the computer one', () {
      final blocks = displaySourceBlocks();
      final ids = {for (final s in createDisplaySources()) s.id.substring(7)};
      expect(blocks.keys.toSet(), ids);
    });
  });

  group('ConfigTag', () {
    test('typed reads accept any numeric tag', () {
      final t = ConfigTag(<String, NbtValue>{'a': const NbtValue.byte(1), 'b': const NbtValue.float(1.5), 's': const NbtValue.string('x')});
      expect(t.getIntOr('a', 0), 1);
      expect(t.getIntOr('b', 0), 1);
      expect(t.getFloatOr('a', 0), 1.0);
      expect(t.getStringOr('s', ''), 'x');
      expect(t.getStringOr('a', 'd'), 'd');
      expect(t.getBooleanOr('a', false), isTrue);
      expect(t.getIntOr('none', 7), 7);
    });

    test('merge replaces, copy is independent', () {
      final t = ConfigTag()..putInt('a', 1);
      final c = t.copy();
      c.putInt('a', 2);
      expect(t.getIntOr('a', 0), 1);
      t.merge(ConfigTag()..putString('b', 'x'));
      expect(t.keys.toSet(), {'a', 'b'});
    });
  });

  group('ReservationStore', () {
    test('reserves, clears and round trips as JSON', () {
      final s = ReservationStore();
      expect(s.set((1, 2, 3), 2, (4, 5, 6)), isTrue);
      expect(s.set((1, 2, 3), 2, (4, 5, 6)), isFalse);
      expect(s.reservedBy((1, 2, 3), 2), (4, 5, 6));
      final back = ReservationStore.fromJson(s.toJson());
      expect(back.reservedBy((1, 2, 3), 2), (4, 5, 6));
      expect(s.set((1, 2, 3), 2, null), isTrue);
      expect(s.isEmpty, isTrue);
      expect(ReservationStore.fromJson('garbage').isEmpty, isTrue);
    });
  });
}
