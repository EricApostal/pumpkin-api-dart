// `PortalTrackProvider` (pure): the exit location of a track that goes through a portal.
//
// Java's provider is registered by portal block and receives a `ServerLevel`; this port passes the
// level's dimension key (`Level.dimension()`, `minecraft:the_nether`) and the inbound [BlockFace],
// so the same logic runs in tests. The caller looks up the portal state at the inbound track's
// connected position. A world id (`World.getId()`, the folder name `world_nether`) is a different
// string and must not be passed here.
import '../../../common/data.dart';
import '../../block_state.dart';

/// `PortalTrackProvider.Exit`: the dimension and track face on the other side.
final class PortalExit {
  /// The destination dimension key (`minecraft:the_nether`), not the destination world id
  /// (`World.getId()`, the folder name `world_nether`).
  final String dimension;

  /// The outbound track face.
  final BlockFace face;

  const PortalExit(this.dimension, this.face);

  @override
  bool operator ==(Object other) =>
      other is PortalExit && other.dimension == dimension && other.face == face;

  @override
  int get hashCode => Object.hash(dimension, face);

  @override
  String toString() => 'PortalExit($dimension, $face)';
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
  /// [dimension] is the dimension key of the level the track enters the portal from.
  static PortalExit? getOtherSide(
    BState portalState,
    String dimension,
    BlockFace inboundTrack,
  ) => registry[portalState.key]?.findExit(dimension, inboundTrack);

  /// Removes every registration (tests and reloads).
  static void clear() => registry.clear();

  /// `findExit(level, face)`: the exit location for a track going through the portal.
  /// [dimension] is the dimension key of the level the track enters the portal from.
  PortalExit? findExit(String dimension, BlockFace inboundTrack);
}
