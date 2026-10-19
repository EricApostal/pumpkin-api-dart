// The host implementation of [DisplayEnv] and the conversions of the source configuration
// between [ConfigTag] and the host's `NbtCompound`.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/redstone.dart';
import '../../api/util.dart' hide pos;
import '../../core/nbt.dart';
import '../nixie/nixie_blocks.dart';
import '../nixie/nixie_logic.dart';
import '../observer/observer_blocks.dart';
import '../support/level.dart';
import '../support/rs_runtime.dart';
import 'config_tag.dart';
import 'display_core.dart';
import 'lectern_book.dart';
import 'reservations.dart';

/// The host's compound for a [ConfigTag].
NbtCompound configToNbt(ConfigTag tag) {
  final out = NbtCompound();
  for (final e in tag.entries.entries) {
    _put(out, e.key, e.value);
  }
  return out;
}

void _put(NbtCompound out, String key, NbtValue v) {
  switch (v.kind) {
    case NbtKind.byte:
      out.putByte(key, v.value as int);
    case NbtKind.short:
      out.putShort(key, v.value as int);
    case NbtKind.int:
      out.putInt(key, v.value as int);
    case NbtKind.long:
      out.putLong(key, v.value as int);
    case NbtKind.float:
      out.putFloat(key, v.value as double);
    case NbtKind.double:
      out.putDouble(key, v.value as double);
    case NbtKind.string:
      out.putString(key, v.value as String);
    case NbtKind.byteArray:
      out.putByteArray(key, v.value as List<int>);
    case NbtKind.intArray:
      out.putIntArray(key, v.value as List<int>);
    case NbtKind.longArray:
      out.putLongArray(key, v.value as List<int>);
    case NbtKind.list:
      out.putList(key, [for (final item in v.value as List<NbtValue>) _listElement(item)]);
    case NbtKind.compound:
      final c = NbtCompound();
      for (final e in (v.value as Map<String, NbtValue>).entries) {
        _put(c, e.key, e.value);
      }
      out.putCompound(key, c);
    case NbtKind.end:
      break;
  }
}

Object _listElement(NbtValue v) => switch (v.kind) {
  NbtKind.byte => NbtTagByte(v.value as int),
  NbtKind.short => NbtTagShort(v.value as int),
  NbtKind.int => NbtTagInt(v.value as int),
  NbtKind.long => NbtTagLong(v.value as int),
  NbtKind.float => NbtTagFloat(v.value as double),
  NbtKind.double => NbtTagDouble(v.value as double),
  NbtKind.string => NbtTagStringTag(v.value as String),
  NbtKind.compound => () {
    final c = NbtCompound();
    for (final e in (v.value as Map<String, NbtValue>).entries) {
      _put(c, e.key, e.value);
    }
    return c;
  }(),
  _ => NbtTagStringTag(''),
};

/// A [ConfigTag] from the host's compound (the keys it holds; `Id` included).
ConfigTag configFromNbt(NbtCompound c) {
  final tag = ConfigTag();
  for (final key in c.keys) {
    final s = c.getString(key);
    if (s != null) {
      tag.putString(key, s);
      continue;
    }
    final i = c.getInt(key);
    if (i != null) {
      tag.putInt(key, i);
      continue;
    }
    final d = c.getDouble(key);
    if (d != null) {
      tag.putFloat(key, d);
      continue;
    }
    final list = c.getList(key);
    if (list != null) {
      tag.putList(key, [for (final e in list) _fromListElement(e)]);
    }
  }
  return tag;
}

NbtValue _fromListElement(Object e) => switch (e) {
  NbtTagByte(:final value) => NbtValue.byte(value),
  NbtTagShort(:final value) => NbtValue.short(value),
  NbtTagInt(:final value) => NbtValue.int32(value),
  NbtTagLong(:final value) => NbtValue.long(value),
  NbtTagFloat(:final value) => NbtValue.float(value),
  NbtTagDouble(:final value) => NbtValue.double64(value),
  NbtTagStringTag(:final value) => NbtValue.string(value),
  _ => NbtValue.string(''),
};

/// The `deaths` of players seen so far, per auto objective.
final Map<String, Map<String, int>> _trackedScores = {};

/// [DisplayEnv] over a host world.
final class HostDisplayEnv implements DisplayEnv {
  final Lvl lvl;
  final RsRuntime rs;

  HostDisplayEnv(this.lvl, this.rs);

  static final math.Random _random = math.Random();

  T? _service<T extends Object>() => rs.ctx.services.find<T>();

  BlockPos _bp(Pos p) => p.toBlockPos();

  @override
  String get worldId => lvl.id;

  @override
  int get gameTime => lvl.gameTime;

  @override
  int get overworldClockTime => lvl.world.getTimeOfDay();

  @override
  bool get naturalDimension {
    final d = lvl.world.getDimension();
    return d != 'minecraft:the_nether' && d != 'minecraft:the_end';
  }

  @override
  int nextInt(int bound) => _random.nextInt(bound);

  @override
  BState stateAt(Pos pos) {
    final info = lvl.info(pos);
    return info == null ? BState.air : BState(info.key, info.properties);
  }

  @override
  bool blockHasTag(Pos pos, String tag) => BlockStates.isTag(lvl.stateId(pos), tag);

  @override
  Future<int> directSignalTo(Pos pos) => lvl.directSignalTo(pos);

  // -- This module ---------------------------------------------------------------------------------------

  @override
  Txt? nixieText(Pos pos) => rs.be<NixieTubeBlockEntity>(lvl.world, _bp(pos))?.fullText;

  @override
  ({int level, int min, int max})? thresholdLevels(Pos pos) {
    final be = rs.be<ThresholdSwitchBlockEntity>(lvl.world, _bp(pos));
    if (be == null) return null;
    return (level: be.currentLevel, min: be.currentMinLevel, max: be.currentMaxLevel);
  }

  @override
  Future<ObserverView?> observerView(Pos pos) async => rs.be<SmartObserverBlockEntity>(lvl.world, _bp(pos))?.view();

  // -- Scoreboards ----------------------------------------------------------------------------------------

  @override
  Future<List<ScoreLine>?> scoresOf(String name) async {
    // The host's scoreboard has no way to read scores: only the objectives Create tracks itself.
    final tracked = _trackedScores[name];
    if (tracked == null) return null;
    return [for (final e in tracked.entries) ScoreLine(e.key, e.value)];
  }

  @override
  Future<List<ScoreLine>> trackedStat(String stat, String displayName) async {
    final objective = 'create_auto_$stat';
    final scores = _trackedScores.putIfAbsent(objective, () => {});
    final scoreboard = lvl.world.getScoreboard();
    if (scores.isEmpty) {
      try {
        scoreboard.addObjective(
          name: objective,
          displayName: TextComponent.text(plain: displayName),
          renderType: RenderType.integer,
          numberFormat: null,
        );
      } on Object {
        // the objective exists already
      }
    }
    for (final player in rs.bus?.roster.players ?? const <Player>[]) {
      try {
        final name = player.getName();
        final score = switch (stat) {
          'deaths' => player.getCustomStatistic(stat: CustomStatistic.deaths),
          _ => 0,
        };
        scores[name] = score;
        scoreboard.updateScore(entityName: name, objectiveName: objective, value: score, numberFormat: null);
      } on Object {
        // a player that went away
      }
    }
    return [for (final e in scores.entries) ScoreLine(e.key, e.value)];
  }

  // -- Other modules --------------------------------------------------------------------------------------

  @override
  double? kineticSpeedAt(Pos pos) => _service<KineticDisplayData>()?.speedGaugeSpeed(worldId, pos);

  @override
  ({double stress, double capacity})? networkStressAt(Pos pos) =>
      _service<KineticDisplayData>()?.stressGaugeNetwork(worldId, pos);

  @override
  double? cuckooClockSpeedAt(Pos pos) => _service<KineticDisplayData>()?.cuckooClockSpeed(worldId, pos);

  @override
  ({Txt heatLevel, Txt size, Txt water, Txt heat})? boilerTexts(Pos pos, {required bool forFlapDisplay}) =>
      _service<BoilerDisplayData>()?.boilerTexts(worldId, pos, forFlapDisplay: forFlapDisplay);

  @override
  String? elevatorFloorAt(Pos pos) => _service<ElevatorDisplayData>()?.lastReportedFloor(worldId, pos);

  @override
  String? centeredItemNameAt(Pos pos) => _service<ItemFlowDisplayData>()?.centeredItemName(worldId, pos);

  @override
  String? seatPassengerNameAt(Pos pos) => _service<SeatDisplayData>()?.passengerName(worldId, pos);

  @override
  Txt? observedTrainNameAt(Pos pos) => _service<TrainDisplayData>()?.observedTrainName(worldId, pos);

  @override
  Txt? trainStatusAt(Pos pos) => _service<TrainDisplayData>()?.trainStatus(worldId, pos);

  @override
  String? stationNameAt(Pos pos) => _service<TrainDisplayData>()?.stationName(worldId, pos);

  @override
  List<TrainPredictionView> trainPredictions(String filter, int maxRows) =>
      _service<TrainDisplayData>()?.predictions(filter, maxRows) ?? const [];

  @override
  List<GaugeEntryView> factoryGaugeEntries(List<(Pos pos, String slot)> panels) {
    final access = _service<FactoryPanelAccess>();
    if (access == null) return const [];
    final result = <GaugeEntryView>[];
    for (final (pos, slot) in panels) {
      final s = PanelSlotId.byName(slot);
      if (s == null) continue;
      final panel = access.panelAt(worldId, FactoryPanelPos(pos, s));
      if (panel == null) continue;
      result.add(
        GaugeEntryView(
          levelInStorage: panel.levelInStorage,
          filterName: panel.filterName,
          demand: panel.demand,
          promised: panel.promised,
          satisfied: panel.satisfied,
          statusColor: panel.ingredientStatusColor,
        ),
      );
    }
    return result;
  }

  // -- Targets --------------------------------------------------------------------------------------------

  @override
  Future<bool> writeSignLines(Pos pos, Map<int, String> lines) async {
    final be = lvl.world.getBlockEntity(pos: _bp(pos));
    SignText Function() front;
    SignText Function() back;
    void Function(SignText) setFront;
    void Function(SignText) setBack;
    switch (be) {
      case BlockEntityTypeSignBlockEntity(:final value):
        front = value.getFrontText;
        back = value.getBackText;
        setFront = (t) => value.setFrontText(text: t);
        setBack = (t) => value.setBackText(text: t);
      case BlockEntityTypeHangingSignBlockEntity(:final value):
        front = value.getFrontText;
        back = value.getBackText;
        setFront = (t) => value.setFrontText(text: t);
        setBack = (t) => value.setBackText(text: t);
      default:
        return false;
    }
    SignText apply(SignText t) {
      final messages = List<String>.of(t.messages);
      while (messages.length < 4) {
        messages.add('');
      }
      for (final e in lines.entries) {
        if (e.key >= 0 && e.key < 4) messages[e.key] = e.value;
      }
      return t.copyWith(messages: messages);
    }

    setFront(apply(front()));
    setBack(apply(back()));
    return true;
  }

  @override
  Future<LecternBookView?> lecternBook(Pos pos) => readLecternBook(lvl.world, _bp(pos));

  @override
  Future<void> setLecternPages(Pos pos, List<Object?> pagesJson) => writeLecternPages(lvl.world, _bp(pos), pagesJson);

  @override
  List<(Pos, int)> nixieRow(Pos pos) => walkNixies(pos, (p) => lvl.info(p));

  @override
  void setNixieText(Pos pos, String jsonText, int rowPosition) =>
      rs.be<NixieTubeBlockEntity>(lvl.world, _bp(pos))?.displayCustomText(jsonText, rowPosition);

  @override
  FlapControllerView? flapController(Pos pos) => _service<FlapDisplayAccess>()?.controllerAt(worldId, pos);

  // -- Reservations ---------------------------------------------------------------------------------------

  @override
  Pos? reservedBy(Pos target, int line) => ReservationHolder.of(lvl.world).reservedBy(target, line);

  @override
  void setReservation(Pos target, int line, Pos? link) {
    if (ReservationHolder.of(lvl.world).set(target, line, link)) ReservationHolder.save(lvl.world);
  }
}

/// The reservation stores of the loaded worlds, kept in the world's persistent data.
abstract final class ReservationHolder {
  static const String _key = 'display_reservations';
  static final Map<String, ReservationStore> _stores = {};

  static ReservationStore of(World world) {
    final id = world.getId();
    return _stores.putIfAbsent(id, () => ReservationStore.fromJson(world.persistentData('create').getString(_key)));
  }

  static void save(World world) {
    final store = _stores[world.getId()];
    if (store == null) return;
    world.persistentData('create').setString(_key, store.toJson());
  }

  static void forget(String worldId) => _stores.remove(worldId);
}
