// `RedstoneLinkNetworkHandler` and `IRedstoneLinkable` (pure): the per world
// frequency networks of redstone links, linked controllers and factory gauges.
// A network is the set of linkables sharing one pair of frequencies; a receiver
// gets the maximum strength transmitted by a linkable within range.
import '../../common/common.dart';
import 'frequency.dart';

/// `IRedstoneLinkable`: something that transmits to or listens on a link network.
abstract class RedstoneLinkable {
  /// The strength this linkable puts into its network (0 to 15).
  int get transmittedStrength;

  /// Called with the network strength when this linkable listens.
  void setReceivedStrength(int power);

  /// Whether this linkable receives (a receiver) instead of transmitting.
  bool get isListening;

  /// Whether the owner still exists; dead linkables are dropped from the network.
  bool get isAlive;

  /// The pair of frequencies identifying the network.
  NetworkKey get networkKey;

  /// Where the linkable is (range checks).
  Pos get location;

  /// The `LinkBehaviour` part of `updateNetworkOf`: the actor that triggered the
  /// update gets the network strength itself (the one to one loading order fix).
  /// Called once per update with the actor, whether it listens or not.
  void onActorNetworkUpdate(int power) {}
}

/// `RedstoneLinkNetworkHandler`. [linkRange] is `logistics.linkRange` of the
/// server config (default 256), read on every range check.
class RedstoneLinkNetworkHandler {
  final int Function() linkRange;

  RedstoneLinkNetworkHandler({required this.linkRange});

  final Map<String, Map<NetworkKey, Set<RedstoneLinkable>>> _connections = {};

  /// Increments whenever a network was recomputed (`globalPowerVersion`).
  int globalPowerVersion = 0;

  /// `onLoadWorld`.
  void onLoadWorld(String worldId) => _connections[worldId] = {};

  /// `onUnloadWorld`.
  void onUnloadWorld(String worldId) => _connections.remove(worldId);

  /// `networksIn(world)`: a world that was never prepared gets an empty (throwaway) map.
  Map<NetworkKey, Set<RedstoneLinkable>> networksIn(String worldId) => _connections[worldId] ?? {};

  /// Like [networksIn] but creates the space of a world on first use. The host loads
  /// worlds before block entities, but a missed event must not lose links.
  Map<NetworkKey, Set<RedstoneLinkable>> _space(String worldId) => _connections.putIfAbsent(worldId, () => {});

  /// `getNetworkOf`: the (live) set of [actor]'s network, created when missing.
  Set<RedstoneLinkable> getNetworkOf(String worldId, RedstoneLinkable actor) {
    final networks = _space(worldId);
    final key = actor.networkKey;
    // Linked hash set: iteration is in insertion order like Java's LinkedHashSet.
    return networks.putIfAbsent(Couple<Frequency>(key.first, key.second), () => <RedstoneLinkable>{});
  }

  /// `addToNetwork`.
  void addToNetwork(String worldId, RedstoneLinkable actor) {
    getNetworkOf(worldId, actor).add(actor);
    updateNetworkOf(worldId, actor);
  }

  /// `removeFromNetwork`.
  void removeFromNetwork(String worldId, RedstoneLinkable actor) {
    final network = getNetworkOf(worldId, actor);
    network.remove(actor);
    if (network.isEmpty) {
      _space(worldId).remove(actor.networkKey);
      return;
    }
    updateNetworkOf(worldId, actor);
  }

  /// `updateNetworkOf`: recompute the power of [actor]'s network and hand it to the
  /// receivers within range.
  void updateNetworkOf(String worldId, RedstoneLinkable actor) {
    final network = getNetworkOf(worldId, actor);
    globalPowerVersion++;
    var power = 0;

    final dead = <RedstoneLinkable>[];
    for (final other in network) {
      if (!other.isAlive) {
        dead.add(other);
        continue;
      }
      if (!withinRange(actor, other)) continue;
      if (power < 15) power = power > other.transmittedStrength ? power : other.transmittedStrength;
    }
    network.removeAll(dead);

    actor.onActorNetworkUpdate(power);

    for (final other in network.toList()) {
      if (!identical(other, actor) && other.isListening && withinRange(actor, other)) {
        other.setReceivedStrength(power);
      }
    }
  }

  /// `withinRange`: `from.getLocation().closerThan(to.getLocation(), linkRange)`.
  bool withinRange(RedstoneLinkable from, RedstoneLinkable to) {
    if (identical(from, to)) return true;
    return from.location.closerThan(to.location, linkRange().toDouble());
  }

  /// `hasAnyLoadedPower`: whether any loaded linkable of [key] transmits.
  bool hasAnyLoadedPower(NetworkKey key) {
    for (final map in _connections.values) {
      final set = map[key];
      if (set == null || set.isEmpty) continue;
      for (final link in set) {
        if (link.transmittedStrength > 0) return true;
      }
    }
    return false;
  }
}
