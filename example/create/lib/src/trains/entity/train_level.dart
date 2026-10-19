// What the train logic needs from the world, from the server and from other modules (pure
// interfaces). Java passes a `Level` around and reaches the server, the players and the network
// through statics; the Dart port hands the train code a [TrainLevel] (the level of one
// dimension, also a `ScheduleLevel` for the schedule runtime) and reaches the rest through
// [TrainFx]. The host implementations are in `train_host.dart`; tests install fakes.
import '../../api/block_state.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../../redstone/support/text.dart' show Txt;
import '../schedule/schedule_level.dart';
import '../util/ctag.dart';
import 'train.dart';

/// The level (dimension) a train, carriage or navigation is ticked in (`Level` /
/// `ServerLevel`).
abstract interface class TrainLevel implements ScheduleLevel {
  /// `level.dimension()`: the world id (`minecraft:overworld`).
  String get dimension;

  /// `level.getGameTime()`.
  int get gameTime;

  /// The blocks of this level (`level.getBlockState(pos)`).
  BlockGetter get blocks;

  /// `server.getLevel(dimension)`: the loaded level of another dimension, `null` when it is not
  /// loaded.
  TrainLevel? levelOf(String dimension);

  /// `CarriageEntityHandler.isActiveChunk(level, pos)`: `serverLevel.isPositionEntityTicking(pos)`.
  bool isActiveChunk(Pos pos);

  /// `level.explode(null, x, y, z, radius, ExplosionInteraction.NONE)`.
  void explode(double x, double y, double z, double radius);
}

/// The services of the server the trains reach statically in Java: players (by uuid), chat,
/// the HUD packets, advancements, sounds, bogey block entities. A default implementation that does
/// nothing is installed ([NullTrainEffects]).
abstract interface class TrainEffects {
  /// Whether the player [uuid] is online (`server.getPlayerList().getPlayer(uuid) != null`).
  bool isPlayerOnline(String uuid);

  /// `player.sendSystemMessage(message)`; false when the player is not online.
  bool sendSystemMessage(String playerUuid, Txt message);

  /// `player.sendOverlayMessage(message)`.
  void sendOverlayMessage(String playerUuid, Txt message);

  /// `new TrainPromptPacket(text, shadow)` to the player; [textJson] is the JSON value of the
  /// component (`Txt.toJson()` or a map with a `keybind`).
  void sendPrompt(String playerUuid, Object textJson, bool shadow);

  /// `new TrainHUDUpdatePacket.Clientbound(train)` to the player.
  void sendTrainHud(String playerUuid, Train train);

  /// `new RemoveTrainPacket(train)` to all clients.
  void sendRemoveTrain(String trainId);

  /// `new AddTrainPacket(train)` to all clients.
  void sendAddTrain(Train train);

  /// `new HonkPacket.Clientbound(train, isHonk)` to all clients.
  void sendHonk(Train train, bool isHonk);

  /// `CreateAdvancement.awardTo(player)`: [advancementId] is an `AllAdvancements` id.
  void awardAdvancement(String playerUuid, String advancementId);

  /// `level.playSound(null, x, y, z, event, SoundSource.NEUTRAL, volume, pitch)`.
  void playSound(String dimension, Vec3 position, String soundEventId, double volume, double pitch);

  /// `level.gameEvent(entity, event, position)` (vibration for sculk sensors).
  void gameEvent(String dimension, String eventId, Vec3 position);

  /// `AbstractBogeyBlockEntity.setBogeyData(data)` of the block entity at [pos], if there is one.
  void setBogeyData(String dimension, Pos pos, CTag bogeyData);

  /// `StationBlockEntity.lastDisassembledTrainName / lastDisassembledMapColorIndex` of the
  /// station block entity at [pos], if there is one.
  void noteDisassembledTrain(String dimension, Pos pos, Txt trainName, int mapColorIndex);
}

/// A [TrainEffects] that does nothing (tests, the module before the host is wired).
final class NullTrainEffects implements TrainEffects {
  const NullTrainEffects();

  @override
  bool isPlayerOnline(String uuid) => false;

  @override
  bool sendSystemMessage(String playerUuid, Txt message) => false;

  @override
  void sendOverlayMessage(String playerUuid, Txt message) {}

  @override
  void sendPrompt(String playerUuid, Object textJson, bool shadow) {}

  @override
  void sendTrainHud(String playerUuid, Train train) {}

  @override
  void sendRemoveTrain(String trainId) {}

  @override
  void sendAddTrain(Train train) {}

  @override
  void sendHonk(Train train, bool isHonk) {}

  @override
  void awardAdvancement(String playerUuid, String advancementId) {}

  @override
  void playSound(String dimension, Vec3 position, String soundEventId, double volume, double pitch) {}

  @override
  void gameEvent(String dimension, String eventId, Vec3 position) {}

  @override
  void setBogeyData(String dimension, Pos pos, CTag bogeyData) {}

  @override
  void noteDisassembledTrain(String dimension, Pos pos, Txt trainName, int mapColorIndex) {}
}

/// The installed [TrainEffects] and the train settings.
abstract final class TrainFx {
  static TrainEffects effects = const NullTrainEffects();
}

/// `AllConfigs.server().trains` as the train logic reads it (the values of the config service are
/// copied here by the registration; tests set them directly).
final class TrainSettings {
  /// `trains.trainsCauseDamage`.
  bool trainsCauseDamage = true;

  /// `trains.maxTrackPlacementLength`.
  int maxTrackPlacementLength = 32;

  /// `trains.maxAssemblyLength`.
  int maxAssemblyLength = 128;

  /// `trains.maxBogeyCount`.
  int maxBogeyCount = 20;

  /// `trains.manualTrainSpeedModifier`.
  double manualTrainSpeedModifier = 0.75;

  /// `trains.trainStats.*` (blocks per second, blocks per second squared).
  double trainTopSpeed = 28;
  double trainTurningTopSpeed = 14;
  double trainAcceleration = 3;

  /// `trains.poweredTrainStats.*`.
  double poweredTrainTopSpeed = 40;
  double poweredTrainTurningTopSpeed = 20;
  double poweredTrainAcceleration = 3;

  /// The settings in use.
  static TrainSettings current = TrainSettings();
}
