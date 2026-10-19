// The host implementation of [TrainEffects]: the server services the train logic reaches
// statically in Java (players, chat, the HUD / honk / train list packets, advancements, sounds,
// bogey data and the station's last disassembled train).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/advancements.dart' show CreateAdvancements;
import '../../api/payloads.dart';
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
import '../station/station_block_entity.dart';
import '../util/ctag.dart';
import 'carriage.dart';
import 'carriage_bogey.dart';
import 'train.dart';
import 'train_level.dart';

/// Installs the host effects (`TrainFx.effects`).
void installTrainEffects(CreateContext ctx) =>
    TrainFx.effects = HostTrainEffects(ctx);

/// Restores the do-nothing effects.
void uninstallTrainEffects() => TrainFx.effects = const NullTrainEffects();

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

  TextComponent _text(Txt text) =>
      TextComponent.fromLegacyString(input: text.plain);

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

/// `AllAdvancements.TRAIN_WHISTLE` for the honk handler.
const String trainWhistleAdvancement = AllAdvancements.trainWhistle;
