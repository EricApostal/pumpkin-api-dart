// `AllPortalTracks` and `PortalTrackProvider` (pure): tracks that run through portals. A portal
// must be entered from the side and leads to another dimension, where the exit track is placed
// next to the portal found there.
//
// Java -> Dart: `PortalTrackProvider.REGISTRY` is keyed by block key; `Portal.getPortalDestination`
// (the `NetherPortalBlock` search) is [Portal] with [NetherPortal] as the vanilla implementation.
// Unlike vanilla, a missing destination portal is not created: the track then fails with `missing`.
// The portal blocks of mods that are not installed are skipped (`Mods.isLoaded`).
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;

import '../../api/block_state.dart';
import '../../common/common.dart';
import 'track_level.dart';

/// `PortalTrackProvider.Exit`.
final class PortalExit {
  final TrackLevel level;
  final BlockFace face;

  const PortalExit(this.level, this.face);
}

/// `PortalTrackProvider.findExit(level, face)`.
typedef PortalTrackFinder = PortalExit? Function(TrackLevel level, BlockFace face);

/// `PortalTrackProvider`.
abstract final class PortalTrackProvider {
  /// `REGISTRY`: the portal blocks by key.
  static final Map<String, PortalTrackFinder> REGISTRY = <String, PortalTrackFinder>{};

  static PortalTrackFinder? get(BState state) => REGISTRY[state.key];

  /// `isSupportedPortal(state)`.
  static bool isSupportedPortal(BState state) => REGISTRY.containsKey(state.key);

  /// `getOtherSide(level, inboundTrack)`.
  static PortalExit? getOtherSide(TrackLevel level, BlockFace inboundTrack) {
    final portalPos = inboundTrack.connectedPos;
    final portalState = level.stateAt(portalPos);
    final provider = REGISTRY[portalState.key];
    return provider == null ? null : provider(level, inboundTrack);
  }

  /// `fromPortal(level, face, firstDimension, secondDimension, portal)`.
  static PortalExit? fromPortal(
    TrackLevel level,
    BlockFace face,
    String firstDimension,
    String secondDimension,
    Portal portal,
  ) => AllPortalTracks.fromPortal(level, face, firstDimension, secondDimension, portal);
}

/// `net.minecraft.world.level.block.Portal`: where an entity at a block of the portal arrives.
abstract interface class Portal {
  /// The position the portal at [portalPos] of [level] leads to in [otherLevel], `null` when
  /// there is no destination.
  Vec3? getPortalDestination(TrackLevel level, TrackLevel otherLevel, Pos portalPos, Direction inboundFace);
}

/// The destination search of `NetherPortalBlock` / `PortalForcer.findClosestPortalPosition`.
final class NetherPortal implements Portal {
  /// The block key of the portal.
  final String blockKey;
  final String netherDimension;

  /// Upper bound of the blocks looked at for one search.
  final int maxChecks;

  const NetherPortal({this.blockKey = 'minecraft:nether_portal', this.netherDimension = 'minecraft:the_nether', this.maxChecks = 3000000});

  @override
  Vec3? getPortalDestination(TrackLevel level, TrackLevel otherLevel, Pos portalPos, Direction inboundFace) {
    final toNether = otherLevel.dimension == netherDimension;
    final scale = level.dimension == netherDimension ? 8.0 : (toNether ? 1 / 8.0 : 1.0);
    final target = ((portalPos.x + 0.5) * scale, portalPos.y.toDouble(), (portalPos.z + 0.5) * scale);
    final center = posContaining(target);
    final radius = toNether ? 16 : 128;

    final found = _findClosestPortal(otherLevel, center, radius);
    if (found == null) return null;

    // Map the position in the source portal frame onto the destination frame.
    final srcAxis = level.stateAt(portalPos).axisOf('axis') ?? Axis.x;
    final src = _frame(level, portalPos, srcAxis);
    final dstAxis = otherLevel.stateAt(found).axisOf('axis') ?? Axis.x;
    final dst = _frame(otherLevel, found, dstAxis);
    final relH = ((portalPos.get(srcAxis) - src.minH + 0.5) / (src.sizeH));
    final relV = ((portalPos.y - src.minY + 0.0) / src.sizeV);
    final int h = dst.minH + math.min<int>(dst.sizeH - 1, (relH * dst.sizeH).floor());
    final int v = dst.minY + math.min<int>(dst.sizeV - 1, (relV * dst.sizeV).floor());
    final Pos pos = dstAxis == Axis.x ? (h, v, found.z) : (found.x, v, h);
    final p = otherLevel.stateAt(pos).key == blockKey ? pos : found;
    return (p.x + 0.5, p.y.toDouble(), p.z + 0.5);
  }

  /// The closest portal block (ties: the lowest).
  Pos? _findClosestPortal(TrackLevel level, Pos center, int radius) {
    Pos? best;
    var bestDist = double.maxFinite;
    var checks = 0;
    for (var r = 0; r <= radius; r++) {
      // Once a hit is known, rings farther than its distance cannot improve it.
      if (best != null && r > math.sqrt(bestDist).ceil()) break;
      for (var dx = -r; dx <= r; dx++) {
        for (var dz = -r; dz <= r; dz++) {
          if (math.max(dx.abs(), dz.abs()) != r) continue;
          final x = center.x + dx, z = center.z + dz;
          if (!level.isLoaded((x, center.y, z))) continue;
          for (var y = level.maxBuildY; y >= level.minBuildY; y--) {
            if (++checks > maxChecks) return best;
            if (level.stateAt((x, y, z)).key != blockKey) continue;
            final d = ((x - center.x) * (x - center.x) + (y - center.y) * (y - center.y) + (z - center.z) * (z - center.z)).toDouble();
            if (d < bestDist || (d == bestDist && best != null && y < best.y)) {
              bestDist = d;
              best = (x, y, z);
            }
          }
        }
      }
    }
    return best;
  }

  _Frame _frame(TrackLevel level, Pos at, Axis axis) {
    // Flood the plane of portal blocks around [at].
    final seen = <Pos>{at};
    final queue = [at];
    var minH = at.get(axis), maxH = minH, minY = at.y, maxY = at.y;
    while (queue.isNotEmpty) {
      final p = queue.removeLast();
      for (final n in [p.relativeAxis(axis, 1), p.relativeAxis(axis, -1), p.above, p.below]) {
        if (seen.contains(n) || level.stateAt(n).key != blockKey) continue;
        seen.add(n);
        queue.add(n);
        minH = math.min(minH, n.get(axis));
        maxH = math.max(maxH, n.get(axis));
        minY = math.min(minY, n.y);
        maxY = math.max(maxY, n.y);
      }
    }
    return _Frame(minH, maxH - minH + 1, minY, maxY - minY + 1);
  }
}

final class _Frame {
  final int minH;
  final int sizeH;
  final int minY;
  final int sizeV;

  const _Frame(this.minH, this.sizeH, this.minY, this.sizeV);
}

/// `AllPortalTracks`.
abstract final class AllPortalTracks {
  /// `tryRegisterIntegration(id, provider)`: registers [provider] for the portal block [blockKey]
  /// when [exists] says the block exists (a warning is the caller's).
  static bool tryRegisterIntegration(String blockKey, PortalTrackFinder provider, {bool Function(String key)? exists}) {
    if (exists != null && !exists(blockKey)) return false;
    PortalTrackProvider.REGISTRY[blockKey] = provider;
    return true;
  }

  /// `tryRegisterSimpleInteraction(portalBlock, levelKey)`: overworld <-> [levelKey] portals.
  static void tryRegisterSimpleInteraction(String portalBlockKey, String levelKey, Portal portal, {String overworld = 'minecraft:overworld'}) {
    PortalTrackProvider.REGISTRY[portalBlockKey] = (level, face) =>
        PortalTrackProvider.fromPortal(level, face, overworld, levelKey, portal);
  }

  /// `registerDefaults()`: the nether portal (the Aether and Better End integrations need their
  /// mods, which are not part of the server).
  static void registerDefaults() {
    tryRegisterSimpleInteraction('minecraft:nether_portal', 'minecraft:the_nether', const NetherPortal());
  }

  /// `fromPortal(level, inboundTrack, firstDimension, secondDimension, portal)`.
  static PortalExit? fromPortal(
    TrackLevel level,
    BlockFace inboundTrack,
    String firstDimension,
    String secondDimension,
    Portal portal,
  ) {
    final resourceKey = level.dimension == secondDimension ? firstDimension : secondDimension;
    final otherLevel = level.getLevel(resourceKey);
    if (otherLevel == null) return null;

    final portalPos = inboundTrack.connectedPos;
    final portalState = level.stateAt(portalPos);

    final destination = portal.getPortalDestination(level, otherLevel, portalPos, inboundTrack.face);
    if (destination == null) return null;

    final otherPortalPos = posContaining(destination);
    final otherPortalState = otherLevel.stateAt(otherPortalPos);
    if (otherPortalState.key != portalState.key) return null;

    var targetDirection = inboundTrack.face;
    final otherAxis = otherPortalState.axisOf('axis');
    if (otherAxis != null && targetDirection.axis == otherAxis) targetDirection = targetDirection.clockWise;
    final otherPos = otherPortalPos.relative(targetDirection);
    return PortalExit(otherLevel, BlockFace(otherPos, targetDirection.opposite));
  }
}
