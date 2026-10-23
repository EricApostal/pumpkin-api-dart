// The 26 display sources of Create (`AllDisplaySources`), pure over [DisplayEnv]. They are
// ports of `content/redstone/displayLink/source/*`: the same configuration keys
// (`Label`, `Format`, `Mode`, `Interval`, ...) and the same text. The flap display layouts
// (`loadFlapDisplayLayout`) and the config widgets (`initConfigurationWidgets`) are client or
// decoration business and are not ported.
import 'dart:math' as math;

import '../../content/advancement_ids.dart' show AllAdvancements;
import '../../common/common.dart';
import '../../core/nbt.dart' show NbtKind, NbtValue;
import '../support/text.dart';
import 'config_tag.dart';
import 'display_core.dart';

/// Java `(int) x` for a float: NaN is 0, out of range values saturate.
int javaInt(double x) {
  if (x.isNaN) return 0;
  if (x >= 2147483647) return 2147483647;
  if (x <= -2147483648) return -2147483648;
  return x.toInt();
}

/// `FlapDisplaySection.MONOSPACE` / `WIDE_MONOSPACE`.
const double flapMonospace = 7;
const double flapWideMonospace = 9;

bool _isSign(String key) => key.endsWith('_sign') || key.endsWith('_hanging_sign');

// -- Bases ------------------------------------------------------------------------------------------

/// `SingleLineDisplaySource`.
abstract class SingleLineDisplaySource extends DisplaySource {
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats);

  bool allowsLabeling(DisplayLinkContext context);

  @override
  Future<List<Txt>> provideText(DisplayLinkContext context, DisplayTargetStats stats) async {
    var line = await provideLine(context, stats);
    if (identical(line, DisplaySource.emptyLine)) return DisplaySource.emptyList;

    if (allowsLabeling(context)) {
      final label = context.sourceConfig.getStringOr('Label', '');
      if (label.isNotEmpty) line = Txt.literal('$label ').append(line);
    }
    return [line];
  }

  @override
  Future<List<List<Txt>>> provideFlapDisplayText(DisplayLinkContext context, DisplayTargetStats stats) async {
    if (allowsLabeling(context)) {
      final label = context.sourceConfig.getStringOr('Label', '');
      if (label.isNotEmpty) {
        return [
          [Txt.literal('$label '), await provideLine(context, stats)],
        ];
      }
    }
    return super.provideFlapDisplayText(context, stats);
  }

  @override
  FlapLayoutSpec loadFlapDisplayLayout(DisplayLinkContext context, FlapControllerView flap, int lineIndex) {
    final layoutKey = getFlapDisplayLayoutName(context);
    final label = allowsLabeling(context) ? context.sourceConfig.getStringOr('Label', '') : '';
    final maxCharCount = flap.maxCharCount;

    if (label.isEmpty) {
      return FlapLayoutSpec(layoutKey, [createSectionForValue(context, maxCharCount)]);
    }

    final layoutName = '${label.length}_Labeled_$layoutKey';
    final labelSection = FlapSectionSpec(
      math.min(maxCharCount, label.length + 1) * FlapSectionSpec.monospace,
      'alphabet',
    );
    if (label.length + 1 < maxCharCount) {
      return FlapLayoutSpec(layoutName, [
        labelSection,
        createSectionForValue(context, maxCharCount - label.length - 1),
      ]);
    }
    return FlapLayoutSpec(layoutName, [labelSection]);
  }
}

/// `NumericSingleLineDisplaySource`.
abstract class NumericSingleLineDisplaySource extends SingleLineDisplaySource {
  static Txt zero() => Txt.literal('0');

  @override
  String getFlapDisplayLayoutName(DisplayLinkContext context) => 'Number';

  @override
  FlapSectionSpec createSectionForValue(DisplayLinkContext context, int size) =>
      FlapSectionSpec(size * FlapSectionSpec.monospace, 'numeric');
}

/// A box for `flapDisplayContext` (`MutableInt`).
final class MutableInt {
  int value;

  MutableInt([this.value = 0]);
}

/// `ValueListDisplaySource`.
abstract class ValueListDisplaySource extends DisplaySource {
  static const int entriesPerPage = 8;

  Future<List<IntAttached<Txt>>> provideEntries(DisplayLinkContext context, int maxRows);

  bool get valueFirst;

  bool isBook(DisplayLinkContext c) => c.targetState.key == 'minecraft:lectern';

  @override
  Future<List<Txt>> provideText(DisplayLinkContext context, DisplayTargetStats stats) async {
    final book = isBook(context);
    final entries = await provideEntries(context, stats.maxRows * (book ? entriesPerPage : 1));
    var list = <Txt>[];
    for (final e in entries) {
      final l = createComponentsFromEntry(context, e);
      final combined = l[0].append(l[1]);
      if (l.length > 2) combined.append(l[2]);
      list.add(combined);
    }
    if (book) list = _condensePages(list);
    return list;
  }

  List<Txt> _condensePages(List<Txt> list) {
    final condensed = <Txt>[];
    Txt? current;
    for (var i = 0; i < list.length; i++) {
      final atIndex = list[i];
      if (current == null) {
        current = atIndex;
        continue;
      }
      current.append(Txt.literal('\n')).append(atIndex);
      if ((i + 1) % entriesPerPage == 0) {
        condensed.add(current);
        current = null;
      }
    }
    if (current != null) condensed.add(current);
    return condensed;
  }

  @override
  Future<List<List<Txt>>> provideFlapDisplayText(DisplayLinkContext context, DisplayTargetStats stats) async {
    final highest = MutableInt(0);
    context.flapDisplayContext = highest;
    final result = <List<Txt>>[];
    for (final e in await provideEntries(context, stats.maxRows)) {
      highest.value = math.max(highest.value, e.first);
      result.add(createComponentsFromEntry(context, e));
    }
    return result;
  }

  /// `loadFlapDisplayLayout`: the value format comes from the highest number of the list
  /// (`context.flapDisplayContext`), not from the texts of a single row.
  @override
  FlapLayoutSpec loadFlapDisplayLayout(DisplayLinkContext context, FlapControllerView flap, int lineIndex) {
    final valueFirst = this.valueFirst;
    final shorten = shortenNumbers(context);
    final valueFormat = shorten ? 0 : math.max(4, 1 + _log10Int((context.flapDisplayContext as MutableInt?)?.value ?? 0));

    final layoutKey = 'ValueList_${valueFirst}_$valueFormat';
    final maxCharCount = flap.maxCharCountFor(1);
    final numberLength = math.min(maxCharCount, math.max(3, valueFormat));
    final nameLength = math.max(maxCharCount - numberLength - (shorten ? 1 : 0), 0);

    const mono = FlapSectionSpec.monospace;
    final name = FlapSectionSpec(mono * nameLength, 'alphabet', hasGap: !valueFirst);
    final value = FlapSectionSpec(
      mono * numberLength,
      'number',
      hasGap: !shorten && valueFirst,
      rightAligned: true,
    );

    if (shorten) {
      final suffix = FlapSectionSpec(mono, 'shortened_numbers', hasGap: valueFirst);
      return FlapLayoutSpec(layoutKey, valueFirst ? [value, suffix, name] : [name, value, suffix]);
    }
    return FlapLayoutSpec(layoutKey, valueFirst ? [value, name] : [name, value]);
  }

  /// `(int) Math.log10(value)`; 0 and negatives are `Integer.MIN_VALUE` like the Java cast.
  static int _log10Int(int value) {
    if (value <= 0) return -0x80000000;
    return (math.log(value) / math.ln10).floor();
  }

  List<Txt> createComponentsFromEntry(DisplayLinkContext context, IntAttached<Txt> entry) {
    final number = entry.first;
    final name = entry.second.append(DisplaySource.whitespace);

    if (shortenNumbers(context)) {
      final (a, b) = _shorten(number);
      return valueFirst ? [a, b, name] : [name, a, b];
    }

    final formatted = Txt.literal('$number').append(DisplaySource.whitespace);
    return valueFirst ? [formatted, name] : [name, formatted];
  }

  (Txt, Txt) _shorten(int number) {
    if (number >= 1000000) {
      return (
        Txt.literal('${number ~/ 1000000}'),
        Txt.translate('create.display_source.value_list.million').append(DisplaySource.whitespace),
      );
    }
    if (number >= 1000) {
      return (
        Txt.literal('${number ~/ 1000}'),
        Txt.translate('create.display_source.value_list.thousand').append(DisplaySource.whitespace),
      );
    }
    return (Txt.literal('$number'), DisplaySource.whitespace);
  }

  bool shortenNumbers(DisplayLinkContext context) => context.sourceConfig.getIntOr('Format', 0) == 0;
}

/// `PercentOrProgressBarDisplaySource`.
abstract class PercentOrProgressBarDisplaySource extends NumericSingleLineDisplaySource {
  @override
  String getFlapDisplayLayoutName(DisplayLinkContext context) =>
      !progressBarActive(context) ? super.getFlapDisplayLayoutName(context) : 'Progress';

  @override
  FlapSectionSpec createSectionForValue(DisplayLinkContext context, int size) => !progressBarActive(context)
      ? super.createSectionForValue(context, size)
      : FlapSectionSpec(size * FlapSectionSpec.monospace, 'pixel', wideFlaps: true);

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async {
    final rawProgress = await getProgress(context);
    if (rawProgress == null) return DisplaySource.emptyLine;

    if (!progressBarActive(context)) return formatNumeric(context, rawProgress);

    final label = context.sourceConfig.getStringOr('Label', '');

    final labelSize = label.isEmpty ? 0 : label.length + 1;
    var length = math.min(stats.maxColumns - labelSize, 128);

    final target = context.targetState.key;
    if (_isSign(target)) length = javaInt(length * 6 / 9);
    if (target == 'create:display_board') length = javaInt(length * flapMonospace / flapWideMonospace);

    // clamp just in case - #7371
    final currentLevel = rawProgress.isNaN ? 0.0 : rawProgress.clamp(0.0, 1.0);
    final filledLength = javaInt(currentLevel * length);

    if (length < 1) return DisplaySource.emptyLine;

    final emptySpaces = length - filledLength;
    final s = '█' * math.max(0, filledLength) + '▒' * math.max(0, emptySpaces);
    return Txt.literal(s);
  }

  Txt formatNumeric(DisplayLinkContext context, double currentLevel) {
    final pct = currentLevel.isNaN ? 0 : javaInt(currentLevel * 100);
    return Txt.literal('${pct.clamp(0, 100)}%');
  }

  /// The progress from 0 to 1 (more for stress values), `null` to show nothing.
  Future<double?> getProgress(DisplayLinkContext context);

  bool progressBarActive(DisplayLinkContext context);
}

// -- Redstone and scoreboards ---------------------------------------------------------------------------

/// `RedstonePowerDisplaySource` (`redstone_power`).
final class RedstonePowerDisplaySource extends PercentOrProgressBarDisplaySource {
  @override
  String get id => 'create:redstone_power';

  @override
  Txt formatNumeric(DisplayLinkContext context, double currentLevel) => Txt.literal('${javaInt(currentLevel * 15)}');

  @override
  bool allowsLabeling(DisplayLinkContext context) => true;

  @override
  Future<double?> getProgress(DisplayLinkContext context) async {
    final state = context.sourceState;
    final direct = await context.env.directSignalTo(context.sourcePos);
    final power = int.tryParse(state['power'] ?? '') ?? 0;
    return math.max(direct, power) / 15.0;
  }

  @override
  bool progressBarActive(DisplayLinkContext context) => context.sourceConfig.getIntOr('Mode', 0) != 0;
}

/// `ScoreboardDisplaySource` (`scoreboard`).
class ScoreboardDisplaySource extends ValueListDisplaySource {
  @override
  String get id => 'create:scoreboard';

  @override
  bool get valueFirst => false;

  @override
  Future<List<IntAttached<Txt>>> provideEntries(DisplayLinkContext context, int maxRows) async {
    final name = context.sourceConfig.getStringOr('Objective', '');
    return showScoreboard(await context.env.scoresOf(name), name, maxRows);
  }

  /// `showScoreboard`: the scores highest first; a missing objective is one `404` line.
  List<IntAttached<Txt>> showScoreboard(List<ScoreLine>? scores, String objectiveName, int maxRows) {
    if (scores == null) {
      return [
        IntAttached<Txt>(404, Txt.translate('create.display_source.scoreboard.objective_not_found', [Txt.literal(objectiveName)])),
      ];
    }
    final entries = [for (final s in scores) IntAttached<Txt>(s.value, Txt.literal(s.owner))];
    // List.sort is not stable: sort by (score desc, original index).
    final indexed = [for (var i = 0; i < entries.length; i++) (entries[i], i)];
    indexed.sort((a, b) {
      final c = b.$1.first.compareTo(a.$1.first);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    return [for (final e in indexed.take(maxRows)) e.$1];
  }
}

/// `StatTrackingDisplaySource` + `DeathCounterDisplaySource` (`death_count`).
final class DeathCounterDisplaySource extends ScoreboardDisplaySource {
  @override
  String get id => 'create:death_count';

  @override
  String get translationKey => 'player_deaths';

  @override
  Future<List<IntAttached<Txt>>> provideEntries(DisplayLinkContext context, int maxRows) async {
    final scores = await context.env.trackedStat('deaths', 'Player Deaths');
    return showScoreboard(scores, 'create_auto_deaths', maxRows);
  }

  @override
  bool get valueFirst => false;

  @override
  bool shortenNumbers(DisplayLinkContext context) => false;
}

/// `EnchantPowerDisplaySource` (`enchant_power`).
final class EnchantPowerDisplaySource extends NumericSingleLineDisplaySource {
  static final math.Random _random = math.Random();

  @override
  String get id => 'create:enchant_power';

  @override
  String get translationKey => 'max_enchant_level';

  /// `EnchantingTableBlock.BOOKSHELF_OFFSETS`.
  static final List<Pos> bookshelfOffsets = [
    for (var y = 0; y <= 1; y++)
      for (var z = -2; z <= 2; z++)
        for (var x = -2; x <= 2; x++)
          if (x.abs() == 2 || z.abs() == 2) (x, y, z),
  ];

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async {
    if (context.sourceState.key != 'minecraft:enchanting_table') return NumericSingleLineDisplaySource.zero();

    final pos = context.sourcePos;
    var enchantPower = 0.0;
    for (final offset in bookshelfOffsets) {
      // isValidBookShelf
      final shelf = pos + offset;
      final between = pos.offset(offset.x ~/ 2, offset.y, offset.z ~/ 2);
      if (!context.env.blockHasTag(shelf, 'minecraft:enchantment_power_provider')) continue;
      if (!context.env.blockHasTag(between, 'minecraft:enchantment_power_transmitter')) continue;
      enchantPower += 1; // getEnchantPowerBonus
    }

    final cost = enchantmentCost(_random, 2, enchantPower.toInt(), enchantmentValue: 10);
    return Txt.literal('$cost');
  }

  /// `EnchantmentHelper.getEnchantmentCost` for an item with the given enchantment value
  /// (a diamond pickaxe: 10).
  static int enchantmentCost(math.Random random, int slot, int bookshelfCount, {required int enchantmentValue}) {
    if (enchantmentValue <= 0) return 0;
    if (bookshelfCount > 15) bookshelfCount = 15;
    final i = random.nextInt(8) + 1 + (bookshelfCount >> 1) + random.nextInt(bookshelfCount + 1);
    if (slot == 0) return math.max(i ~/ 3, 1);
    return slot == 1 ? i * 2 ~/ 3 + 1 : math.max(i, bookshelfCount * 2);
  }

  @override
  bool allowsLabeling(DisplayLinkContext context) => true;
}

/// `NixieTubeDisplaySource` (`nixie_tube`).
final class NixieTubeDisplaySource extends SingleLineDisplaySource {
  @override
  String get id => 'create:nixie_tube';

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async {
    final text = context.env.nixieText(context.sourcePos);
    if (text == null) return DisplaySource.emptyLine;
    if (int.tryParse(text.plain) != null) context.flapDisplayContext = true;
    return text;
  }

  @override
  bool allowsLabeling(DisplayLinkContext context) => context.activeTarget?.id != 'create:nixie_tube';

  @override
  String getFlapDisplayLayoutName(DisplayLinkContext context) =>
      context.flapDisplayContext == true ? 'Number' : super.getFlapDisplayLayoutName(context);

  @override
  FlapSectionSpec createSectionForValue(DisplayLinkContext context, int size) =>
      context.flapDisplayContext == true
      ? FlapSectionSpec(size * FlapSectionSpec.monospace, 'numeric')
      : super.createSectionForValue(context, size);
}

// -- Items --------------------------------------------------------------------------------------------------

/// `ItemNameDisplaySource` (`item_names`).
final class ItemNameDisplaySource extends SingleLineDisplaySource {
  @override
  String get id => 'create:item_names';

  @override
  String get translationKey => 'combine_item_names';

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async {
    final direction = context.direction;
    var pos = context.linkedPanels.isNotEmpty ? context.linkedPanels.first.$1 : context.sourcePos;
    final combined = DisplaySource.emptyLine.copy();

    for (var i = 0; i < 32; i++) {
      final name = context.env.centeredItemNameAt(pos);
      pos = pos.relative(direction);
      if (name == null) break;
      if (name.isNotEmpty) combined.append(Txt.literal(name));
    }
    return combined;
  }

  @override
  bool allowsLabeling(DisplayLinkContext context) => true;

  @override
  String getFlapDisplayLayoutName(DisplayLinkContext context) => 'Number';
}

/// `AccumulatedItemCountDisplaySource` (`accumulate_items`).
class AccumulatedItemCountDisplaySource extends NumericSingleLineDisplaySource {
  @override
  String get id => 'create:accumulate_items';

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async =>
      Txt.literal('${context.sourceConfig.getIntOr('Collected', 0)}');

  /// `itemReceived(be, amount)`: called by the tunnels when items pass.
  Future<void> itemReceived(GatheredDataLink link, int amount) async {
    if (link.isPowered) return;
    final collected = link.sourceConfig.getIntOr('Collected', 0);
    link.sourceConfig.putInt('Collected', collected + amount);
    await link.updateGatheredData();
  }

  @override
  String get translationKey => 'accumulate_items';

  @override
  int get passiveRefreshTicks => 200;

  @override
  void onSignalReset(DisplayLinkContext context) => context.sourceConfig.remove('Collected');

  @override
  bool allowsLabeling(DisplayLinkContext context) => true;
}

/// The display link block entity as the item sources see it (`DisplayLinkBlockEntity`).
abstract interface class GatheredDataLink {
  /// `getBlockState().getOptionalValue(POWERED).orElse(true)`.
  bool get isPowered;

  ConfigTag get sourceConfig;

  int get gameTime;

  /// `updateGatheredData()`.
  Future<void> updateGatheredData();
}

/// `ItemThroughputDisplaySource` (`item_throughput`).
final class ItemThroughputDisplaySource extends AccumulatedItemCountDisplaySource {
  static const int poolSize = 10;

  @override
  String get id => 'create:item_throughput';

  @override
  String get translationKey => 'item_throughput';

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async {
    final conf = context.sourceConfig;
    if (conf.contains('Inactive')) return NumericSingleLineDisplaySource.zero();
    final interval = 20 * math.pow(60, conf.getIntOr('Interval', 0));
    final rate = conf.getFloatOr('Rate', 0) * interval;
    if (rate > 0) {
      final previousTime = conf.getLongOr('LastReceived', 0);
      final gameTime = context.env.gameTime;
      final diff = gameTime - previousTime;
      if (diff > 0) {
        // Too long since last item
        final lastAmount = conf.getIntOr('LastReceivedAmount', 0);
        final timeBetweenStacks = lastAmount / rate;
        if (diff > timeBetweenStacks * 2) conf.putBoolean('Inactive', true);
      }
    }
    return Txt.literal(formatNumber(rate.toDouble()));
  }

  @override
  Future<void> itemReceived(GatheredDataLink link, int amount) async {
    if (link.isPowered) return;
    final conf = link.sourceConfig;
    final gameTime = link.gameTime;
    if (!conf.contains('LastReceived')) {
      conf.putLong('LastReceived', gameTime);
      return;
    }
    final previousTime = conf.getLongOr('LastReceived', 0);

    var rates = conf.getListOrEmpty('PrevRates').map((NbtValue v) => v.value is double ? v.value as double : -1.0).toList();
    if (rates.length != poolSize) rates = List<double>.filled(poolSize, -1.0);

    final poolIndex = conf.getIntOr('Index', 0) % poolSize;
    rates[poolIndex] = toFloat(amount / (gameTime - previousTime).toDouble());
    var rate = 0.0;
    var validIntervals = 0;
    for (var i = 0; i < poolSize; i++) {
      final pooled = rates[i];
      if (pooled >= 0) {
        rate = toFloat(rate + pooled);
        validIntervals++;
      }
    }

    conf.remove('Rate');
    if (validIntervals > 0) {
      rate = toFloat(rate / validIntervals);
      conf.putFloat('Rate', rate);
    }
    conf.remove('Inactive');
    conf.putInt('LastReceivedAmount', amount);
    conf.putLong('LastReceived', gameTime);
    conf.putInt('Index', poolIndex + 1);
    conf.putList('PrevRates', [for (final r in rates) NbtValue.float(r)]);
    await link.updateGatheredData();
  }
}

/// `ItemCountDisplaySource` (`count_items`).
final class ItemCountDisplaySource extends NumericSingleLineDisplaySource {
  @override
  String get id => 'create:count_items';

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async {
    final view = await context.env.observerView(context.sourcePos);
    if (view == null || !view.hasInventory) return NumericSingleLineDisplaySource.zero();
    var collected = 0;
    for (final i in view.items) {
      collected += i.count;
    }
    return Txt.literal('$collected');
  }

  @override
  bool allowsLabeling(DisplayLinkContext context) => true;
}

/// `ItemListDisplaySource` (`list_items`).
final class ItemListDisplaySource extends ValueListDisplaySource {
  @override
  String get id => 'create:list_items';

  @override
  bool get valueFirst => true;

  @override
  Future<List<IntAttached<Txt>>> provideEntries(DisplayLinkContext context, int maxRows) async {
    final view = await context.env.observerView(context.sourcePos);
    if (view == null || !view.hasInventory) return const [];
    // CountedItemStackList.getTopNames: summed by item, the biggest first.
    final counts = <String, int>{};
    final names = <String, String>{};
    for (final i in view.items) {
      counts.update(i.key, (v) => v + i.count, ifAbsent: () => i.count);
      names.putIfAbsent(i.key, () => i.name);
    }
    final order = counts.keys.toList();
    final indexed = [for (var i = 0; i < order.length; i++) (order[i], i)];
    indexed.sort((a, b) {
      final c = counts[b.$1]!.compareTo(counts[a.$1]!);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    return [for (final (key, _) in indexed.take(maxRows)) IntAttached<Txt>(counts[key]!, Txt.literal(names[key]!))];
  }
}

/// `FluidFormatter.asComponents`.
(Txt, Txt) fluidComponents(int amount, bool shorten) {
  if (shorten && amount >= 1000) {
    return (Txt.literal((amount / 1000.0).toStringAsFixed(1)), Txt.translate('create.generic.unit.buckets'));
  }
  return (Txt.literal('$amount'), Txt.translate('create.generic.unit.millibuckets'));
}

/// `FluidFormatter.asString`.
String fluidString(int amount, bool shorten) {
  final (a, b) = fluidComponents(amount, shorten);
  return '${a.plain} ${b.plain}';
}

/// `FluidAmountDisplaySource` (`count_fluids`).
final class FluidAmountDisplaySource extends SingleLineDisplaySource {
  @override
  String get id => 'create:count_fluids';

  @override
  String get translationKey => 'fluid_amount';

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async {
    final view = await context.env.observerView(context.sourcePos);
    if (view == null || !view.hasTank) return DisplaySource.emptyLine;
    var collected = 0;
    for (final f in view.fluids) {
      collected += f.amount;
    }
    return Txt.literal(fluidString(collected, false));
  }

  @override
  bool allowsLabeling(DisplayLinkContext context) => true;
}

/// `FluidListDisplaySource` (`list_fluids`).
final class FluidListDisplaySource extends ValueListDisplaySource {
  @override
  String get id => 'create:list_fluids';

  @override
  bool get valueFirst => false;

  @override
  Future<List<IntAttached<Txt>>> provideEntries(DisplayLinkContext context, int maxRows) async {
    final view = await context.env.observerView(context.sourcePos);
    if (view == null || !view.hasTank) return const [];
    final amounts = <String, int>{};
    final names = <String, String>{};
    for (final f in view.fluids) {
      amounts.update(f.key, (v) => v + f.amount, ifAbsent: () => f.amount);
      names.putIfAbsent(f.key, () => f.name);
    }
    final order = amounts.keys.toList();
    final indexed = [for (var i = 0; i < order.length; i++) (order[i], i)];
    indexed.sort((a, b) {
      final c = amounts[b.$1]!.compareTo(amounts[a.$1]!);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    return [for (final (key, _) in indexed.take(maxRows)) IntAttached<Txt>(amounts[key]!, Txt.literal(names[key]!))];
  }

  @override
  List<Txt> createComponentsFromEntry(DisplayLinkContext context, IntAttached<Txt> entry) {
    final amount = entry.first;
    final name = entry.second.append(DisplaySource.whitespace);
    final (a, b) = fluidComponents(amount, shortenNumbers(context));
    return [a, b, name];
  }

  /// `loadFlapDisplayLayout`: the number section is sized from the longest formatted amount.
  @override
  FlapLayoutSpec loadFlapDisplayLayout(DisplayLinkContext context, FlapControllerView flap, int lineIndex) {
    final max = (context.flapDisplayContext as MutableInt?)?.value ?? 0;
    final shorten = shortenNumbers(context);
    final length = fluidString(max, shorten).length;
    final layoutKey = 'FluidList_$length';

    final maxCharCount = flap.maxCharCountFor(1);
    final numberLength = math.min(maxCharCount, math.max(3, length - 2));
    final nameLength = math.max(maxCharCount - numberLength - 2, 0);

    const mono = FlapSectionSpec.monospace;
    return FlapLayoutSpec(layoutKey, [
      FlapSectionSpec(mono * numberLength, 'number', rightAligned: true),
      const FlapSectionSpec(mono * 2, 'fluid_units', singleFlap: true, hasGap: true),
      FlapSectionSpec(mono * nameLength, 'alphabet'),
    ]);
  }
}

/// `PackageAddressDisplaySource` (`read_package_address`).
final class PackageAddressDisplaySource extends SingleLineDisplaySource {
  @override
  String get id => 'create:read_package_address';

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async {
    final view = await context.env.observerView(context.sourcePos);
    final address = view?.packageAddress;
    if (address == null) return DisplaySource.emptyLine;
    return Txt.literal(address);
  }

  @override
  bool allowsLabeling(DisplayLinkContext context) => true;
}

/// `FillLevelDisplaySource` (`fill_level`).
final class FillLevelDisplaySource extends PercentOrProgressBarDisplaySource {
  @override
  String get id => 'create:fill_level';

  @override
  Future<double?> getProgress(DisplayLinkContext context) async {
    final t = context.env.thresholdLevels(context.sourcePos);
    if (t == null) return null;
    final p = (t.level - t.min) / (t.max - t.min);
    // Java: Math.max(0, float): NaN stays NaN and (int) NaN is 0.
    return p.isNaN ? 0.0 : math.max(0.0, p);
  }

  @override
  bool progressBarActive(DisplayLinkContext context) => context.sourceConfig.getIntOr('Mode', 0) != 0;

  @override
  bool allowsLabeling(DisplayLinkContext context) => true;
}

/// `KineticSpeedDisplaySource` (`kinetic_speed`).
final class KineticSpeedDisplaySource extends NumericSingleLineDisplaySource {
  @override
  String get id => 'create:kinetic_speed';

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async {
    final speedValue = context.env.kineticSpeedAt(context.sourcePos);
    if (speedValue == null) return NumericSingleLineDisplaySource.zero();
    final absoluteValue = context.sourceConfig.getIntOr('Directional', 0) == 0;
    final speed = absoluteValue ? speedValue.abs() : speedValue;
    return Txt.literal('${formatNumber(speed)} ').append(Txt.translate('create.generic.unit.rpm'));
  }

  @override
  bool allowsLabeling(DisplayLinkContext context) => true;
}

/// `KineticStressDisplaySource` (`kinetic_stress`).
final class KineticStressDisplaySource extends PercentOrProgressBarDisplaySource {
  @override
  String get id => 'create:kinetic_stress';

  int _mode(DisplayLinkContext c) => c.sourceConfig.getIntOr('Mode', 0);

  @override
  Txt formatNumeric(DisplayLinkContext context, double currentLevel) {
    final mode = _mode(context);
    if (mode == 1) return super.formatNumeric(context, currentLevel);
    final b = Txt.literal(formatNumber(currentLevel));
    if (context.targetState.key == 'create:display_board') b.append(Txt.literal(' '));
    return b.append(Txt.translate('create.generic.unit.stress'));
  }

  @override
  Future<double?> getProgress(DisplayLinkContext context) async {
    final net = context.env.networkStressAt(context.sourcePos);
    if (net == null) return null;
    final capacity = net.capacity;
    final stress = net.stress;
    if (capacity == 0) return 0.0;
    return switch (_mode(context)) {
      0 || 1 => stress / capacity,
      2 => stress,
      3 => capacity,
      4 => capacity - stress,
      _ => 0.0,
    };
  }

  @override
  bool allowsLabeling(DisplayLinkContext context) => true;

  @override
  bool progressBarActive(DisplayLinkContext context) => _mode(context) == 0;
}

// -- Time -------------------------------------------------------------------------------------------------------

Txt _emptyTime() => Txt.literal('--:--');

/// `TimeOfDayDisplaySource` (`time_of_day`).
final class TimeOfDayDisplaySource extends SingleLineDisplaySource {
  @override
  String get id => 'create:time_of_day';

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async {
    final speed = context.env.cuckooClockSpeedAt(context.sourcePos);
    if (speed == null || speed == 0) return _emptyTime();

    final c12 = context.sourceConfig.getIntOr('Cycle', 0) == 0;
    final isNatural = context.env.naturalDimension;
    final dayTime = context.env.overworldClockTime % 24000;
    var hours = (dayTime ~/ 1000 + 6) % 24;
    var minutes = (dayTime % 1000) * 60 ~/ 1000;
    final suffix = Txt.translate('create.generic.daytime.${hours > 11 ? 'pm' : 'am'}');
    minutes = minutes ~/ 5 * 5;
    if (c12) {
      hours %= 12;
      if (hours == 0) hours = 12;
    }
    if (!isNatural) {
      hours = context.env.nextInt(70) + 24;
      minutes = context.env.nextInt(40) + 60;
    }
    final component = Txt.literal('${hours < 10 ? ' ' : ''}$hours:${minutes < 10 ? '0' : ''}$minutes${c12 ? ' ' : ''}');
    return c12 ? component.append(suffix) : component;
  }

  @override
  bool allowsLabeling(DisplayLinkContext context) => true;

  @override
  String getFlapDisplayLayoutName(DisplayLinkContext context) => 'Instant';

  @override
  FlapSectionSpec createSectionForValue(DisplayLinkContext context, int size) =>
      FlapSectionSpec(size * FlapSectionSpec.monospace, 'instant');
}

/// `StopWatchDisplaySource` (`stopwatch`).
final class StopWatchDisplaySource extends SingleLineDisplaySource {
  @override
  String get id => 'create:stopwatch';

  @override
  String get translationKey => 'stop_watch';

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async {
    final speed = context.env.cuckooClockSpeedAt(context.sourcePos);
    if (speed == null || speed == 0) return _emptyTime();

    if (!context.sourceConfig.contains('StartTime')) onSignalReset(context);
    final started = context.sourceConfig.getLongOr('StartTime', 0);
    final current = context.env.gameTime;
    final diff = current - started;
    final hours = diff ~/ 60 ~/ 60 ~/ 20;
    final minutes = (diff ~/ 60 ~/ 20) % 60;
    final seconds = (diff ~/ 20) % 60;
    return Txt.literal(
      '${hours == 0 ? '' : '${hours < 10 ? ' ' : ''}$hours:'}'
      '${minutes < 10 ? (hours == 0 ? ' ' : '0') : ''}$minutes:${seconds < 10 ? '0' : ''}$seconds',
    );
  }

  @override
  void onSignalReset(DisplayLinkContext context) => context.sourceConfig.putLong('StartTime', context.env.gameTime);

  @override
  int get passiveRefreshTicks => 20;

  @override
  bool allowsLabeling(DisplayLinkContext context) => true;

  @override
  String getFlapDisplayLayoutName(DisplayLinkContext context) => 'Instant';

  @override
  FlapSectionSpec createSectionForValue(DisplayLinkContext context, int size) =>
      FlapSectionSpec(size * FlapSectionSpec.monospace, 'instant');
}

// -- Fluids, trains, elevators ----------------------------------------------------------------------------

/// `BoilerDisplaySource` (`boiler`).
final class BoilerDisplaySource extends DisplaySource {
  @override
  String get id => 'create:boiler';

  @override
  String get translationKey => 'boiler_status';

  static Txt _notEnough() => Txt.translate('create.display_source.boiler.not_enough_space');
  static Txt _forStatus() => Txt.translate('create.display_source.boiler.for_boiler_status');

  @override
  Future<List<Txt>> provideText(DisplayLinkContext context, DisplayTargetStats stats) async {
    if (stats.maxRows < 2) return [_notEnough().append(_forStatus())];
    if (stats.maxRows < 4) return [_notEnough(), _forStatus()];

    final book = context.targetState.key == 'minecraft:lectern';
    final rows = _components(context, false).map((components) {
      Txt? reduced;
      for (final c in components) {
        reduced = reduced == null ? c : reduced.append(c);
      }
      return reduced ?? DisplaySource.emptyLine.copy();
    }).toList();

    if (book) {
      Txt? all;
      for (final row in rows) {
        all = all == null ? row : all.append(Txt.literal('\n')).append(row);
      }
      return [all ?? DisplaySource.emptyLine.copy()];
    }
    return rows;
  }

  @override
  Future<List<List<Txt>>> provideFlapDisplayText(DisplayLinkContext context, DisplayTargetStats stats) async {
    List<List<Txt>> notEnoughFlap() => [
      [_notEnough()],
      [_forStatus()],
    ];
    if (stats.maxRows < 4) {
      context.flapDisplayContext = false;
      return notEnoughFlap();
    }
    final components = _components(context, true);
    if (components.length > 1 &&
        components[1].length > 1 &&
        stats.maxColumns * flapMonospace < 6 * flapMonospace + components[1][1].plain.length * flapWideMonospace) {
      context.flapDisplayContext = false;
      return notEnoughFlap();
    }
    return components;
  }

  int _labelWidthOf(String label) => Txt.translate('create.boiler.$label').plain.length;

  int get _labelWidth => math.max(_labelWidthOf('water'), math.max(_labelWidthOf('size'), _labelWidthOf('heat')));

  /// `loadFlapDisplayLayout`: the status line keeps the default layout, the three value lines
  /// get the label and the pixel gauge (`lineIndex == 0` or a board that is too small).
  @override
  FlapLayoutSpec loadFlapDisplayLayout(DisplayLinkContext context, FlapControllerView flap, int lineIndex) {
    final flapContext = context.flapDisplayContext;
    if (lineIndex == 0 || (flapContext is bool && !flapContext)) {
      return const FlapLayoutSpec.defaultLayout();
    }

    final labelLength = (_labelWidth * FlapSectionSpec.monospace).toInt();
    final maxSpace = flap.maxCharCountFor(1) * FlapSectionSpec.monospace;
    final label = FlapSectionSpec(labelLength.toDouble(), 'alphabet', hasGap: true);
    final symbols = FlapSectionSpec(maxSpace - labelLength, 'pixel', wideFlaps: true);
    return FlapLayoutSpec('Boiler', [label, symbols]);
  }

  List<List<Txt>> _components(DisplayLinkContext context, bool forFlapDisplay) {
    final texts = context.env.boilerTexts(context.sourcePos, forFlapDisplay: forFlapDisplay);
    if (texts == null) return [DisplaySource.emptyList];

    final label = forFlapDisplay ? 'create.boiler.status' : 'create.boiler.status_short';
    Txt labelOf(String l) => l.isEmpty ? Txt.empty() : Txt.translate('create.boiler.$l');
    var size = labelOf(forFlapDisplay ? 'size' : '');
    var water = labelOf(forFlapDisplay ? 'water' : '');
    var heat = labelOf(forFlapDisplay ? 'heat' : '');
    final lw = _labelWidth;
    if (forFlapDisplay) {
      size = Txt.literal(' ' * (lw - _labelWidthOf('size'))).append(size);
      water = Txt.literal(' ' * (lw - _labelWidthOf('water'))).append(water);
      heat = Txt.literal(' ' * (lw - _labelWidthOf('heat'))).append(heat);
    }
    return [
      [Txt.translate(label, [texts.heatLevel])],
      [size, texts.size],
      [water, texts.water],
      [heat, texts.heat],
    ];
  }
}

/// `CurrentFloorDisplaySource` (`current_floor`).
final class CurrentFloorDisplaySource extends SingleLineDisplaySource {
  @override
  String get id => 'create:current_floor';

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async {
    final floor = context.env.elevatorFloorAt(context.sourcePos);
    if (floor == null) return DisplaySource.emptyLine;
    return Txt.literal(floor);
  }

  @override
  bool allowsLabeling(DisplayLinkContext context) => false;
}

/// `ObservedTrainNameSource` (`observed_train_name`).
final class ObservedTrainNameSource extends SingleLineDisplaySource {
  @override
  String get id => 'create:observed_train_name';

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async =>
      context.env.observedTrainNameAt(context.sourcePos)?.copy() ?? DisplaySource.emptyLine;

  @override
  int get passiveRefreshTicks => 400;

  @override
  bool allowsLabeling(DisplayLinkContext context) => true;
}

/// `TrainStatusDisplaySource` (`train_status`).
final class TrainStatusDisplaySource extends SingleLineDisplaySource {
  @override
  String get id => 'create:train_status';

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async =>
      context.env.trainStatusAt(context.sourcePos)?.copy() ?? DisplaySource.emptyLine;

  @override
  bool allowsLabeling(DisplayLinkContext context) => false;
}

/// `StationSummaryDisplaySource` (`station_summary`): only the display board shows it.
final class StationSummaryDisplaySource extends DisplaySource {
  @override
  String get id => 'create:station_summary';

  static Txt get _unpredictable => Txt.literal(' ~ ');

  static List<Txt> _emptyEntry4() => [Txt.space(), Txt.literal(' . '), Txt.space(), Txt.space()];

  static List<Txt> _emptyEntry5() => [Txt.space(), Txt.literal(' . '), Txt.space(), Txt.space(), Txt.space()];

  @override
  Future<List<Txt>> provideText(DisplayLinkContext context, DisplayTargetStats stats) async => DisplaySource.emptyList;

  @override
  Future<List<List<Txt>>> provideFlapDisplayText(DisplayLinkContext context, DisplayTargetStats stats) async {
    final filter = context.sourceConfig.getStringOr('Filter', '');
    final hasPlatform = filter.contains('*');
    final list = <List<Txt>>[];

    for (final prediction in context.env.trainPredictions(filter, stats.maxRows)) {
      final lines = <Txt>[];
      if (prediction.ticks == -1 || prediction.ticks >= 12000 - 15 * 20) {
        lines.add(Txt.space());
        lines.add(_unpredictable);
      } else if (prediction.ticks < 200) {
        lines.add(Txt.space());
        lines.add(Txt.translate('create.display_source.station_summary.now'));
      } else {
        var min = prediction.ticks ~/ 1200;
        var sec = (prediction.ticks ~/ 20) % 60;
        sec = (sec / 15.0).ceil() * 15;
        if (sec == 60) {
          min++;
          sec = 0;
        }
        lines.add(min > 0 ? Txt.literal('$min') : Txt.space());
        lines.add(
          min > 0
              ? Txt.translate('create.display_source.station_summary.minutes')
              : Txt.translate('create.display_source.station_summary.seconds', [Txt.literal('$sec')]),
        );
      }
      lines.add(prediction.trainName.copy());
      lines.add(prediction.scheduleTitle);
      if (!hasPlatform) {
        list.add(lines);
        continue;
      }

      var platform = prediction.destination;
      for (final string in filter.split('*')) {
        if (string.isNotEmpty) platform = platform.replaceAll(string, '');
      }
      platform = platform.replaceAll('*', '?');
      lines.add(Txt.literal(platform.trim()));
      list.add(lines);
    }

    // `if (list.size() > 0) context.blockEntity().award(AllAdvancements.DISPLAY_BOARD)`.
    if (list.isNotEmpty) context.award?.call(AllAdvancements.displayBoard);

    final toPad = stats.maxRows - list.length;
    for (var padding = 0; padding < toPad; padding++) {
      list.add(hasPlatform ? _emptyEntry5() : _emptyEntry4());
    }
    return list;
  }

  @override
  FlapLayoutSpec loadFlapDisplayLayout(DisplayLinkContext context, FlapControllerView flap, int lineIndex) {
    final conf = context.sourceConfig;
    final columnWidth = conf.getIntOr('NameColumn', 0);
    final columnWidth2 = conf.getIntOr('PlatformColumn', 0);
    final hasPlatform = conf.getStringOr('Filter', '').contains('*');

    final layoutName = 'StationSummary$columnWidth$hasPlatform$columnWidth2';

    const mono = FlapSectionSpec.monospace;
    const timeWidth = 20.0;
    const gapSize = 8.0;
    var platformWidth = columnWidth2 * mono;

    const minutes = FlapSectionSpec(mono, 'numeric');
    const time = FlapSectionSpec(timeWidth, 'arrival_time', singleFlap: true, hasGap: true);

    var totalSize = flap.xSize * 32.0 - 4.0 - gapSize * 2;
    totalSize = totalSize - timeWidth - mono;
    platformWidth = math.min(platformWidth, totalSize - gapSize);
    platformWidth = (platformWidth / mono).toInt() * mono;

    if (hasPlatform) totalSize = totalSize - gapSize - platformWidth;
    if (platformWidth == 0 && hasPlatform) totalSize += gapSize;

    final trainNameWidth = (columnWidth / 100.0 * totalSize / mono).toInt();
    final destinationWidth = ((1 - columnWidth / 100.0) * totalSize / mono).round();

    final trainName = FlapSectionSpec(mono * trainNameWidth, 'alphabet', hasGap: trainNameWidth > 0);
    final destination = FlapSectionSpec(
      mono * destinationWidth,
      'alphabet',
      hasGap: hasPlatform && destinationWidth > 0 && platformWidth > 0,
    );
    final platform = FlapSectionSpec(platformWidth, 'numeric', rightAligned: true);

    return FlapLayoutSpec(layoutName, [
      minutes,
      time,
      trainName,
      destination,
      if (hasPlatform) platform,
    ]);
  }

  @override
  void populateData(DisplayLinkContext context) {
    final conf = context.sourceConfig;
    if (!conf.contains('PlatformColumn')) conf.putInt('PlatformColumn', 3);
    if (!conf.contains('NameColumn')) conf.putInt('NameColumn', 50);
    if (conf.contains('Filter')) return;
    final name = context.env.stationNameAt(context.sourcePos);
    if (name == null) return;
    conf.putString('Filter', name);
  }
}

// -- Entities, panels, computers --------------------------------------------------------------------------

/// `EntityNameDisplaySource` (`entity_name`): the passenger of the seat.
final class EntityNameDisplaySource extends SingleLineDisplaySource {
  @override
  String get id => 'create:entity_name';

  @override
  Future<Txt> provideLine(DisplayLinkContext context, DisplayTargetStats stats) async {
    final name = context.env.seatPassengerNameAt(context.sourcePos);
    if (name == null || name.isEmpty) return DisplaySource.emptyLine;
    return Txt.literal(name);
  }

  @override
  bool allowsLabeling(DisplayLinkContext context) => true;
}

/// `FactoryGaugeDisplaySource` (`gauge_status`).
final class FactoryGaugeDisplaySource extends ValueListDisplaySource {
  @override
  String get id => 'create:gauge_status';

  @override
  bool get valueFirst => true;

  @override
  Future<List<IntAttached<Txt>>> provideEntries(DisplayLinkContext context, int maxRows) async {
    if (context.linkedPanels.isEmpty) return const [];
    final entries = <IntAttached<Txt>>[];
    for (final e in context.env.factoryGaugeEntries(context.linkedPanels)) {
      var s = ' ';
      if (e.demand != 0) {
        if (e.satisfied) {
          s = '✔';
        } else if (e.promised != 0) {
          s = '↑';
        } else {
          s = '▪';
        }
      }
      entries.add(
        IntAttached<Txt>(
          e.levelInStorage,
          Txt.literal('$s ').withColor(e.statusColor).append(Txt.literal(e.filterName)),
        ),
      );
      if (entries.length >= maxRows) break;
    }
    return entries;
  }
}

/// `ComputerDisplaySource` (`computer`): the lines a ComputerCraft peripheral wrote.
final class ComputerDisplaySource extends DisplaySource {
  @override
  String get id => 'create:computer';

  @override
  Future<List<Txt>> provideText(DisplayLinkContext context, DisplayTargetStats stats) async => [
    for (final v in context.sourceConfig.getListOrEmpty('ComputerSourceList'))
      Txt.literal(v.kind == NbtKind.string ? v.value as String : ''),
  ];

  @override
  bool get shouldPassiveReset => false;
}

/// All 26 sources in the order of `AllDisplaySources`.
List<DisplaySource> createDisplaySources() => [
  DeathCounterDisplaySource(),
  ScoreboardDisplaySource(),
  EnchantPowerDisplaySource(),
  RedstonePowerDisplaySource(),
  NixieTubeDisplaySource(),
  ItemNameDisplaySource(),
  BoilerDisplaySource(),
  CurrentFloorDisplaySource(),
  FillLevelDisplaySource(),
  FactoryGaugeDisplaySource(),
  EntityNameDisplaySource(),
  TimeOfDayDisplaySource(),
  StopWatchDisplaySource(),
  KineticSpeedDisplaySource(),
  KineticStressDisplaySource(),
  StationSummaryDisplaySource(),
  TrainStatusDisplaySource(),
  ObservedTrainNameSource(),
  AccumulatedItemCountDisplaySource(),
  ItemThroughputDisplaySource(),
  ItemCountDisplaySource(),
  ItemListDisplaySource(),
  FluidAmountDisplaySource(),
  FluidListDisplaySource(),
  PackageAddressDisplaySource(),
  ComputerDisplaySource(),
];

/// `AllDisplaySources.LEGACY_NAMES`.
const Map<String, String> legacyDisplaySourceNames = {
  'death_count_display_source': 'death_count',
  'scoreboard_display_source': 'scoreboard',
  'enchant_power_display_source': 'enchant_power',
  'redstone_power_display_source': 'redstone_power',
  'nixie_tube_source': 'nixie_tube',
  'belt_source_combine_item_names': 'item_names',
  'cuckoo_clock_source_time_of_day': 'time_of_day',
  'cuckoo_clock_source_stop_watch': 'stopwatch',
  'speedometer_source_kinetic_speed': 'kinetic_speed',
  'stressometer_source_kinetic_stress': 'kinetic_stress',
  'fluid_tank_source_boiler_status': 'boiler',
  'elevator_contact_source_current_floor': 'current_floor',
  'track_station_source_station_summary': 'station_summary',
  'track_station_source_train_status': 'train_status',
  'track_observer_source_observed_train_name': 'observed_train_name',
  'andesite_tunnel_source_accumulate_items': 'accumulate_items',
  'andesite_tunnel_source_item_throughput': 'item_throughput',
  'brass_tunnel_source_accumulate_items': 'accumulate_items',
  'brass_tunnel_source_item_throughput': 'item_throughput',
  'content_observer_source_count_items': 'count_items',
  'content_observer_source_list_items': 'list_items',
  'content_observer_source_count_fluids': 'count_fluids',
  'content_observer_source_list_fluids': 'list_fluids',
  'stockpile_switch_source_fill_level': 'fill_level',
  'factory_gauge_source_gauge_status': 'gauge_status',
  'depot_source_combine_item_names': 'item_names',
  'weighted_ejector_source_combine_item_names': 'item_names',
  'computer_display_source': 'computer',
  // The seat names (`<colour>_seat_source_entity_name`) are added with the colours.
};

/// The blocks each source reads from (`displaySource(...)` of `AllBlocks`, the `associate`
/// calls of `AllDisplaySources`). Keys are full block keys.
Map<String, List<String>> displaySourceBlocks() {
  const dyes = [
    'white', 'orange', 'magenta', 'light_blue', 'yellow', 'lime', 'pink', 'gray',
    'light_gray', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black', //
  ];
  return {
    'death_count': ['minecraft:respawn_anchor'],
    'scoreboard': ['minecraft:command_block', 'minecraft:chain_command_block', 'minecraft:repeating_command_block'],
    'enchant_power': ['minecraft:enchanting_table'],
    'redstone_power': ['minecraft:target'],
    'nixie_tube': [
      'create:nixie_tube',
      for (final c in dyes)
        if (c != 'orange') 'create:${c}_nixie_tube',
    ],
    'item_names': ['create:belt', 'create:depot', 'create:weighted_ejector'],
    'time_of_day': ['create:cuckoo_clock', 'create:mysterious_cuckoo_clock'],
    'stopwatch': ['create:cuckoo_clock', 'create:mysterious_cuckoo_clock'],
    'kinetic_speed': ['create:speedometer'],
    'kinetic_stress': ['create:stressometer'],
    'boiler': ['create:fluid_tank'],
    'current_floor': ['create:elevator_contact'],
    'station_summary': ['create:track_station'],
    'train_status': ['create:track_station'],
    'observed_train_name': ['create:track_observer'],
    'accumulate_items': ['create:andesite_tunnel', 'create:brass_tunnel'],
    'item_throughput': ['create:andesite_tunnel', 'create:brass_tunnel'],
    'count_items': ['create:content_observer'],
    'list_items': ['create:content_observer'],
    'count_fluids': ['create:content_observer'],
    'list_fluids': ['create:content_observer'],
    'read_package_address': ['create:content_observer'],
    'fill_level': ['create:stockpile_switch'],
    'gauge_status': ['create:factory_gauge'],
    'entity_name': [for (final c in dyes) 'create:${c}_seat'],
    'computer': [
      'computercraft:wired_modem_full',
      'computercraft:computer_normal',
      'computercraft:computer_advanced',
      'computercraft:computer_command',
    ],
  };
}
