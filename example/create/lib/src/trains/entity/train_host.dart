// The host implementation of [TrainEffects]: the server services the train logic reaches
// statically in Java (players, chat, the HUD / honk / train list packets, advancements, sounds,
// bogey data and the station's last disassembled train).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/advancements.dart' show CreateAdvancements;
import '../../api/block_state.dart' show BlockGetter;
import '../../api/blocks.dart' show HostBlockGetter;
import '../../api/payloads.dart';
import '../../api/redstone.dart' show RedstoneLinkNetworkHandler;
import '../../api/sounds.dart' show CreateSounds;
import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../../content/advancement_ids.dart';
import '../../core/module.dart';
import '../../core/nbt.dart';
import '../../core/registry.dart';
import '../../redstone/support/text.dart' show Txt;
import '../bogey/abstract_bogey_block_entity.dart';
import '../manager/global_railway_manager.dart' show RailwayHooks;
import '../schedule/schedule_host.dart' show HostScheduleProbe;
import '../schedule/schedule_level.dart'
    show PlainScheduleFilters, ScheduleFilters, SchedulePortInventories;
import '../station/global_package_port.dart';
import '../station/station_block_entity.dart';
import '../support/runtime.dart' show Tr;
import '../util/ctag.dart';
import 'carriage.dart';
import 'carriage_bogey.dart';
import 'train.dart';
import 'train_level.dart';

/// Installs the host effects (`TrainFx.effects`) and the per-player train packet the railway
/// manager sends on login.
void installTrainEffects(CreateContext ctx) {
  final effects = HostTrainEffects(ctx);
  TrainFx.effects = effects;
  RailwayHooks.sendAddTrainTo = effects.sendAddTrainTo;
}

/// Restores the do-nothing effects.
void uninstallTrainEffects() {
  TrainFx.effects = const NullTrainEffects();
  RailwayHooks.sendAddTrainTo = null;
}

final class HostTrainEffects implements TrainEffects {
  final CreateContext ctx;

  HostTrainEffects(this.ctx);

  PayloadBus? get _bus => ctx.services.find<PayloadBus>();

  Player? _player(String uuid) {
    for (final player in _bus?.roster.players ?? const <Player>[]) {
      if (player.getId().asString == uuid) return player;
    }
    return null;
  }

  @override
  bool isPlayerOnline(String uuid) => _player(uuid) != null;

  @override
  bool sendSystemMessage(String playerUuid, Txt message) {
    final player = _player(playerUuid);
    if (player == null) return false;
    player.sendSystemMessage(text: _text(message), overlay: false);
    return true;
  }

  @override
  void sendOverlayMessage(String playerUuid, Txt message) {
    _player(playerUuid)?.sendSystemMessage(text: _text(message), overlay: true);
  }

  @override
  void sendPrompt(String playerUuid, Object textJson, bool shadow) {
    final player = _player(playerUuid);
    if (player == null) return;
    _bus?.sendClientbound('create:s_train_prompt', player, {
      'text': _componentNbt(textJson),
      'shadow': shadow,
    });
  }

  @override
  void sendTrainHud(String playerUuid, Train train) {
    final player = _player(playerUuid);
    if (player == null) return;
    _bus?.sendClientbound('create:s_train_hud', player, _hudFields(train));
  }

  /// The fields of `TrainHUDUpdatePacket.Clientbound`.
  Map<String, Object?> _hudFields(Train train) => {
    'trainId': train.id,
    'throttle': train.throttle,
    'speed': train.speedBeforeStall ?? train.speed,
    'fuelTicks': train.fuelTicks,
  };

  @override
  void sendRemoveTrain(String trainId) {
    final bus = _bus;
    if (bus == null) return;
    bus.sendClientboundAll('create:remove_train', bus.roster.players, {
      'id': trainId,
    });
  }

  @override
  void sendAddTrain(Train train) {
    final bus = _bus;
    if (bus == null) return;
    bus.sendClientboundAll('create:add_train', bus.roster.players, {
      'train': _trainMap(train),
    });
  }

  /// `new AddTrainPacket(train)` to one player (`GlobalRailwayManager.playerLogin`).
  void sendAddTrainTo(Object player, Train train) {
    if (player is! Player) return;
    _bus?.sendClientbound('create:add_train', player, {
      'train': _trainMap(train),
    });
  }

  @override
  void sendHonk(Train train, bool isHonk) {
    final bus = _bus;
    if (bus == null) return;
    bus.sendClientboundAll('create:s_train_honk', bus.roster.players, {
      'trainId': train.id,
      'isHonk': isHonk,
    });
  }

  @override
  void awardAdvancement(String playerUuid, String advancementId) {
    final player = _player(playerUuid);
    final advancements = ctx.services.find<CreateAdvancements>();
    if (player == null || advancements == null) return;
    unawaited(advancements.award(player, advancementId));
  }

  @override
  void playSound(
    String dimension,
    Vec3 position,
    String soundEventId,
    double volume,
    double pitch,
  ) {
    final world = ctx.worlds.byId(dimension);
    final sounds = ctx.services.find<CreateSounds>();
    if (world == null || sounds == null) return;
    sounds.play(world, position, soundEventId, volume: volume, pitch: pitch);
  }

  /// The host exposes no server-side game event API; the vibration of a honk (Java:
  /// `level.gameEvent(entity, RESONATE_15, position)`) is not emitted.
  @override
  void gameEvent(String dimension, String eventId, Vec3 position) {}

  @override
  void setBogeyData(String dimension, Pos pos, CTag bogeyData) {
    ctx.blockEntities
        .typed<AbstractBogeyBlockEntity>(dimension, pos.toBlockPos())
        ?.setBogeyData(bogeyData);
  }

  @override
  void noteDisassembledTrain(
    String dimension,
    Pos pos,
    Txt trainName,
    int mapColorIndex,
  ) {
    ctx.blockEntities
        .typed<StationBlockEntity>(dimension, pos.toBlockPos())
        ?.noteDisassembledTrain(trainName, mapColorIndex);
  }

  /// A [Txt] as a text component: translations are resolved with the English texts the plugin
  /// carries and the colour is kept (`Component.literal(...).withStyle(...)` in Java).
  TextComponent _text(Txt text) {
    final component = TextComponent.text(plain: text.ownPlain);
    if (text.color != -1) {
      component.colorRgb(
        color: RgbColor(
          r: (text.color >> 16) & 0xFF,
          g: (text.color >> 8) & 0xFF,
          b: text.color & 0xFF,
        ),
      );
    }
    for (final sibling in text.siblings) {
      component.addChild(child: _text(sibling));
    }
    return component;
  }

  /// `AddTrainPacket`: the train with its carriages, bogeys and spacing.
  Map<String, Object?> _trainMap(Train train) => {
    'id': train.id,
    'owner': train.owner,
    'carriages': [for (final c in train.carriages) _carriageMap(c)],
    'carriageSpacing': train.carriageSpacing,
    'doubleEnded': train.doubleEnded,
    'name': _componentNbt(train.name.toJson()),
    'icon': train.icon.id,
    'mapColorIndex': train.mapColorIndex,
  };

  Map<String, Object?> _carriageMap(Carriage carriage) => {
    'first': _bogeyMap(carriage.leadingBogey()),
    'second': carriage.isOnTwoBogeys()
        ? _bogeyMap(carriage.trailingBogey())
        : null,
    'bogeySpacing': carriage.bogeySpacing,
  };

  Map<String, Object?> _bogeyMap(CarriageBogey bogey) => {
    'type': ctx.ids.of(RegistryKind.blocks, bogey.type.key) ?? -1,
    'upsideDown': bogey.upsideDown,
    'bogeyData': bogey.bogeyData.toNbt(),
  };

  /// A text component as the NBT the payload's `component` field carries.
  static NbtValue _componentNbt(Object? json) {
    if (json == null) return NbtValue.string('');
    if (json is NbtValue) return json;
    if (json is String) return NbtValue.string(json);
    if (json is Map) {
      return NbtValue.compound({
        for (final e in json.entries) '${e.key}': _componentNbt(e.value ?? ''),
      });
    }
    if (json is List) {
      return NbtValue.list([for (final v in json) _componentNbt(v ?? '')]);
    }
    if (json is bool) return NbtValue.byte(json ? 1 : 0);
    if (json is int) return NbtValue.int32(json);
    if (json is num) return NbtValue.double64(json.toDouble());
    return NbtValue.string(json.toString());
  }
}

/// The [TrainLevel] and [ScheduleLevel] over a host [World]. The manager glue keeps one per
/// world so that the cached redstone probe of the schedule conditions survives between ticks.
final class HostTrainLevel implements TrainLevel {
  final World world;
  final TrainLevel? Function(String dimension)? levelOfDimension;

  HostTrainLevel(this.world, {this.levelOfDimension});

  late final HostBlockGetter _blocks = HostBlockGetter(world);
  final HostScheduleProbe _probe = HostScheduleProbe();

  @override
  String get dimension => world.getId();

  @override
  int get gameTime => world.getWorldAge();

  @override
  BlockGetter get blocks => _blocks;

  @override
  TrainLevel? levelOf(String dimension) => levelOfDimension?.call(dimension);

  @override
  bool isActiveChunk(Pos pos) => world.isLoaded(pos: pos.toBlockPos());

  /// `level.explode(null, x, y, z, radius, ExplosionInteraction.NONE)`.
  @override
  void explode(double x, double y, double z, double radius) {
    unawaited(
      world.createExplosion(
        pos: (x, y, z),
        power: radius,
        createFire: false,
        interaction: ExplosionInteraction.none,
      ),
    );
  }

  // -- ScheduleLevel ---------------------------------------------------------------------------

  @override
  int get overworldClockTime => _probe.overworldClockTime();

  @override
  bool get hasServer => true;

  @override
  bool hasDimension(String dimension) => _probe.hasDimension(dimension);

  @override
  bool isLoaded(String dimension, Pos pos) => _probe.isLoaded(dimension, pos);

  @override
  bool hasNeighborSignal(String dimension, Pos pos) =>
      _probe.hasNeighborSignal(dimension, pos);

  @override
  bool isPositionEntityTicking(String dimension, Pos pos) =>
      _probe.isPositionEntityTicking(dimension, pos);

  @override
  ScheduleFilters get filters => Tr.loaded
      ? (Tr.i.service<ScheduleFilters>() ?? const PlainScheduleFilters())
      : const PlainScheduleFilters();

  @override
  SchedulePortInventories get ports => Tr.loaded
      ? (Tr.i.service<SchedulePortInventories>() ?? const _NoPorts())
      : const _NoPorts();

  @override
  RedstoneLinkNetworkHandler? get redstoneLinks =>
      Tr.loaded ? Tr.i.service<RedstoneLinkNetworkHandler>() : null;
}

/// The station ports without the logistics module: no inventory to look at, but a loaded
/// dimension is still known (the package instructions skip unloaded ones).
final class _NoPorts implements SchedulePortInventories {
  const _NoPorts();

  @override
  List<String>? packageAddresses(
    String dimension,
    Pos pos,
    GlobalPackagePort port,
  ) => Tr.loaded && Tr.i.worldById(dimension) != null ? const [] : null;
}

/// `AllAdvancements.TRAIN_WHISTLE` for the honk handler.
const String trainWhistleAdvancement = AllAdvancements.trainWhistle;
