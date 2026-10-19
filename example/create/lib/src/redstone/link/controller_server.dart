// `LinkedControllerServerHandler` (pure): the buttons pressed on linked controllers.
// A pressed button is a transmitter in the frequency network for 30 ticks, renewed by
// the client's input packets (it sends the pressed set again every 30 ticks).
import '../../common/common.dart';
import 'frequency.dart';
import 'link_network.dart';

/// `ManualFrequencyEntry`: a button of a controller as a link transmitter.
final class ManualFrequencyEntry extends RedstoneLinkable {
  static const int timeout = 30;

  int ticks;
  Pos _pos;
  final NetworkKey key;

  ManualFrequencyEntry(Pos pos, NetworkKey key)
    : ticks = timeout,
      _pos = pos,
      key = Couple<Frequency>(key.first, key.second);

  /// `updatePosition`: the player moved, the press is renewed.
  void updatePosition(Pos pos) {
    _pos = pos;
    ticks = timeout;
  }

  @override
  int get transmittedStrength => isAlive ? 15 : 0;

  @override
  bool get isAlive => ticks > 0;

  @override
  Pos get location => _pos;

  @override
  void setReceivedStrength(int power) {}

  @override
  bool get isListening => false;

  @override
  NetworkKey get networkKey => key;
}

/// The pressed buttons of every world.
final class LinkedControllerServerHandler {
  final RedstoneLinkNetworkHandler network;

  /// Called with the player uuid when a press reached a receiver (the
  /// `linked_controller` advancement).
  final void Function(String playerUuid)? onReceiverActivated;

  LinkedControllerServerHandler(this.network, {this.onReceiverActivated});

  /// `receivedInputs`: world id -> player uuid -> entries.
  final Map<String, Map<String, List<ManualFrequencyEntry>>> receivedInputs = {};

  /// `tick(world)`.
  void tick(String worldId) {
    final map = receivedInputs[worldId];
    if (map == null) return;
    map.removeWhere((uuid, list) {
      list.removeWhere((entry) {
        entry.ticks--;
        if (!entry.isAlive) {
          network.removeFromNetwork(worldId, entry);
          return true;
        }
        return false;
      });
      return list.isEmpty;
    });
    if (map.isEmpty) receivedInputs.remove(worldId);
  }

  /// `receivePressed`.
  void receivePressed(String worldId, Pos pos, String playerUuid, List<NetworkKey> collect, {required bool pressed}) {
    final map = receivedInputs.putIfAbsent(worldId, () => {});
    final list = map.putIfAbsent(playerUuid, () => []);

    outer:
    for (final activated in collect) {
      for (final entry in list) {
        if (entry.key == activated) {
          if (!pressed) {
            entry.ticks = 0;
          } else {
            entry.updatePosition(pos);
          }
          continue outer;
        }
      }

      if (!pressed) continue;

      final entry = ManualFrequencyEntry(pos, activated);
      network.addToNetwork(worldId, entry);
      list.add(entry);

      for (final linkable in network.getNetworkOf(worldId, entry).toList()) {
        if (linkable is! ManualFrequencyEntry && linkable.isListening) {
          onReceiverActivated?.call(playerUuid);
          break;
        }
      }
    }
    if (list.isEmpty) map.remove(playerUuid);
    if (map.isEmpty) receivedInputs.remove(worldId);
  }

  /// A world unloaded: its presses are gone.
  void onUnloadWorld(String worldId) => receivedInputs.remove(worldId);
}
