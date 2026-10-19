// `PortalTrackProvider` (pure): the exit location of a track that goes through a portal.
//
// Java's provider is registered by portal block and receives a `ServerLevel`; this port passes the
// world id and the inbound [BlockFace], so the same logic runs in tests. The caller looks up the
// portal state at the inbound track's connected position.
import '../../../common/data.dart';
import '../../block_state.dart';

/// `PortalTrackProvider.Exit`: the world and track face on the other side.
final class PortalExit {
  /// The destination world id (`minecraft:the_nether`).
  final String worldId;

  /// The outbound track face.
  final BlockFace face;

  const PortalExit(this.worldId, this.face);

  @override
  bool operator ==(Object other) =>
      other is PortalExit && other.worldId == worldId && other.face == face;

  @override
  int get hashCode => Object.hash(worldId, face);

  @override
  String toString() => 'PortalExit($worldId, $face)';
}

/// `PortalTrackProvider`.
abstract interface class PortalTrackProvider {
  /// `REGISTRY`: portal block key to provider.
  static final Map<String, PortalTrackProvider> registry = {};

  /// `REGISTRY.register(block, provider)`.
  static void register(String blockKey, PortalTrackProvider provider) =>
      registry[blockKey] = provider;

  /// `REGISTRY.get(state)`.
  static PortalTrackProvider? of(BState state) => registry[state.key];

  /// `isSupportedPortal(state)`.
  static bool isSupportedPortal(BState state) =>
      registry.containsKey(state.key);

  /// `getOtherSide(level, inboundTrack)`: the exit of the portal at [portalState], or `null`.
  static PortalExit? getOtherSide(
    BState portalState,
    String worldId,
    BlockFace inboundTrack,
  ) => registry[portalState.key]?.findExit(worldId, inboundTrack);

  /// Removes every registration (tests and reloads).
  static void clear() => registry.clear();

  /// `findExit(level, face)`: the exit location for a track going through the portal.
  PortalExit? findExit(String worldId, BlockFace inboundTrack);
}
