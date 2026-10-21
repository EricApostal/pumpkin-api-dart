// `dev.ryanhcode.sable.sublevel.system.SubLevelTrackingSystem`: loads and
// unloads sub-levels for the players that can see them.
//
// Per tick it
//
// * sends the full sync for every sub-level added since the last tick
//   (`start_tracking_sublevel`, an optional `recently_split_sub_level`, the
//   plot's chunks, `finalize_sub_level`),
// * drops tracking players that left or walked out of range
//   (`stop_tracking_sublevel`), and adds the players that walked into range,
// * sends `change_bounds_sublevel` when a plot's bounds changed,
// * batches the movement of every moving sub-level into `snapshot_packet`
//   entries (at most 16 per packet) preceded by `snapshot_info_packet`, or
//   sends `stop_moving_sublevel` when a sub-level came to rest.
//
// **Chunks and the bundle.** Java wraps the whole sync in one
// `ClientboundBundlePacket`, chunks included. A plugin cannot put a vanilla
// chunk packet inside a bundle: the host sends chunks itself, through
// `chunk-streaming.send-chunk-at`. So the sync is a sequence — the two payloads,
// the chunk sends, then `finalize_sub_level`. The client handles that: it
// finalizes the plot when it sees the payload, and the chunk packets that
// arrive before it fill the plot in place. The ordering within the sequence is
// preserved because payloads and chunk sends go out on the same connection.
//
// **UDP.** Movement goes over TCP. Java prefers UDP when the player completed
// the UDP handshake and falls back to TCP otherwise
// (`SubLevelTrackingSystem.java:370-400`); the bodies are identical, so a
// player with UDP enabled just gets the same packets over the other socket. A
// `SableUdpSender` can be installed to use it.
//
// Pure: no host imports.
import 'dart:typed_data';

import '../api/sub_level_observer.dart';
import '../api/sub_level_tracking_plugin.dart';
import '../config/sable_config.dart';
import '../host/sub_level_host.dart';
import '../math/vector.dart';
import '../model/server_sub_level.dart';
import '../model/server_sub_level_container.dart';
import '../model/sub_level.dart';
import '../model/sub_level_container.dart';
import '../network/packet.dart';
import '../network/packets/snapshot_packets.dart';
import '../network/packets/tracking_packets.dart';
import '../network/sable_packets.dart';
import '../network/udp/udp_packets.dart';
import '../network/wire.dart' show SableBufferUtils;
import '../storage/sub_level_removal_reason.dart';

/// Sends an encoded Sable payload to one player.
///
/// The plugin implements this over the host's payload channel: it registers
/// every payload of `SablePackets.allClientbound` on the channel
/// `sable:1` and writes [body] under [payloadId].
abstract interface class SablePayloadSink {
  /// Sends one payload body to [playerId].
  void sendPayload(String playerId, String payloadId, Uint8List body);
}

/// Sends and removes single chunks of a player's world
/// (`chunk-streaming.send-chunk-at` / `unload-chunk-at`).
abstract interface class SableChunkViewSender {
  /// Sends the chunk that contains [blockX], [blockZ] to [playerId].
  void sendChunkAt(String playerId, int blockX, int blockZ);

  /// Tells [playerId] to drop the chunk at [blockX], [blockZ].
  void unloadChunkAt(String playerId, int blockX, int blockZ);
}

/// Sends an encoded UDP datagram to one player.
abstract interface class SableUdpSender {
  /// Whether [playerId] completed the UDP handshake.
  bool isConnected(String playerId);

  /// Sends [datagram] to [playerId].
  void sendDatagram(String playerId, Uint8List datagram);
}

/// A tracking update queued for one player.
enum _UpdateTicketType { stop, move }

final class _SubLevelUpdateTicket {
  final ServerSubLevel subLevel;
  final _UpdateTicketType type;

  _SubLevelUpdateTicket(this.subLevel, this.type);
}

/// Handles the loading and unloading of sub-levels for players.
final class SubLevelTrackingSystem with SubLevelObserver {
  final ServerSubLevelContainer container;
  final SableConfig config;

  /// Where payloads go.
  final SablePayloadSink? sink;

  /// Where chunks go; `null` when the host cannot send chunks
  /// (`chunk-streaming` missing), in which case the client sees no blocks.
  final SableChunkViewSender? chunkView;

  /// The UDP transport, when one is running.
  final SableUdpSender? udp;

  /// The tracking plugins other projects register.
  final List<SubLevelTrackingPlugin> plugins = [];

  final List<SubLevel> _additionQueue = [];
  final Set<String> _currentlyUpdatingPlayers = {};
  final Set<String> _pluginNeededPlayers = {};

  int _interpolationTick = 0;
  int? _lastSendMs;

  /// The wall clock, injectable for tests.
  int Function() nowMillis = () => DateTime.now().millisecondsSinceEpoch;

  /// The server tick rate, used for the first `msSinceLast`.
  double Function() tickRate = () => 20.0;

  SubLevelTrackingSystem({
    required this.container,
    required this.config,
    this.sink,
    this.chunkView,
    this.udp,
  }) {
    container.takeTrackingSystem(this);
    container.addObserver(this);
  }

  /// The current interpolation tick.
  int get interpolationTick => _interpolationTick;

  /// `getSubLevelLong(subLevel, container)`: the plot coordinate packed
  /// relative to the plot yard origin.
  int plotCoordinateOf(ServerSubLevel subLevel) {
    final plotPos = subLevel.getPlot().plotPos;
    return SableBufferUtils.packChunk(plotPos.$1 - container.originX, plotPos.$2 - container.originZ);
  }

  /// Whether [player] is close enough to see a sub-level at [entityPosition].
  bool shouldLoad(SablePlayer player, Vector3d entityPosition) {
    final range = config.subLevelTrackingRange;
    final (x, y, z) = player.position;
    final dx = entityPosition.x - x;
    final dy = entityPosition.y - y;
    final dz = entityPosition.z - z;
    return dx * dx + dy * dy + dz * dz < range * range;
  }

  @override
  void onSubLevelAdded(SubLevel subLevel) => _additionQueue.add(subLevel);

  @override
  void onSubLevelRemoved(SubLevel subLevel, SubLevelRemovalReason reason) {
    _additionQueue.remove(subLevel);
    if (subLevel is ServerSubLevel) _sendRemoval(subLevel);
  }

  // ------------------------------------------------------------------ tick

  @override
  void tick(SubLevelContainer subLevels) {
    _flushAdditions();

    for (final subLevel in container.serverSubLevels()) {
      if (subLevel.isRemoved()) continue;
      _updateTrackingPlayers(subLevel);
    }

    _sendBoundsUpdates();
    _sendMovementUpdates();
  }

  void _flushAdditions() {
    for (final subLevel in _additionQueue) {
      if (subLevel.isRemoved()) continue;
      final serverSubLevel = subLevel as ServerSubLevel;

      final tracking = serverSubLevel.trackingPlayers;
      final position = subLevel.logicalPose.position();
      _collectPlayers(position, tracking);

      final splitFromId = serverSubLevel.getSplitFromSubLevel();
      final splitFrom = splitFromId == null ? null : container.getSubLevelById(splitFromId);
      final splitFromPose = serverSubLevel.getSplitFromPose();

      for (final playerId in tracking) {
        final player = _playerById(playerId);
        if (player == null) {
          throw StateError('Player not found immediately after tracking initializes');
        }

        ClientboundRecentlySplitSubLevelPacket? extra;
        if (splitFromId != null && splitFrom != null && splitFromPose != null) {
          extra = ClientboundRecentlySplitSubLevelPacket(
            splitSubLevelId: serverSubLevel.uniqueId,
            splitFromId: splitFrom.uniqueId,
            pose: splitFromPose,
          );
        }

        _sendFullSync(player, serverSubLevel, extra);
      }

      serverSubLevel.clearSplitFrom();
    }
    _additionQueue.clear();
  }

  void _updateTrackingPlayers(ServerSubLevel subLevel) {
    final tracking = subLevel.trackingPlayers;
    final entityPos = subLevel.logicalPose.position();

    for (final playerId in tracking.toList(growable: false)) {
      final player = _playerById(playerId);

      if (player == null) {
        // The player is gone; if they are still online elsewhere, tell them.
        final online = _onlinePlayer(playerId);
        if (online != null) _sendRemovalTo(online, subLevel);
        tracking.remove(playerId);
        continue;
      }

      if (!shouldLoad(player, entityPos)) {
        _sendRemovalTo(player, subLevel);
        tracking.remove(playerId);
      }
    }

    // Add players who should be tracking but are not.
    for (final player in _players()) {
      if (shouldLoad(player, entityPos) && !tracking.contains(player.uuid)) {
        tracking.add(player.uuid);
        _sendFullSync(player, subLevel, null);
      }
    }
  }

  /// The full sync of one sub-level to one player.
  void _sendFullSync(
    SablePlayer player,
    ServerSubLevel subLevel,
    ClientboundRecentlySplitSubLevelPacket? extraPacket,
  ) {
    final plotCoordinate = plotCoordinateOf(subLevel);
    final plot = subLevel.getPlot();

    _sendPayload(
      player.uuid,
      ClientboundStartTrackingSubLevelPacket(
        plotCoordinate: plotCoordinate,
        subLevelId: subLevel.uniqueId,
        lastPose: subLevel.lastPose,
        pose: subLevel.logicalPose,
        bounds: plot.getBoundingBox(),
        name: subLevel.name,
        gameTick: _interpolationTick,
      ),
    );

    if (extraPacket != null) _sendPayload(player.uuid, extraPacket);

    // The plot's chunks. Java bundles them with the payloads; a plugin cannot,
    // so the host sends them here, before the finalize payload.
    //
    // HOST GAP: Java also sends each chunk's POI data after the bundle
    // (`SubLevelTrackingSystem.java:150-152`,
    // `SubLevelPlayerChunkSender.sendChunkPoiData`). `chunk-streaming.send-chunk-at`
    // already carries the block entities the client needs for this plot, and the
    // Pumpkin API exposes no separate POI packet, so nothing is sent here.
    final chunkView = this.chunkView;
    if (chunkView != null) {
      for (final holder in plot.getLoadedChunks()) {
        chunkView.sendChunkAt(player.uuid, holder.pos.$1 << 4, holder.pos.$2 << 4);
      }
    }

    _sendPayload(player.uuid, ClientboundFinalizeSubLevelPacket(plotCoordinate));
  }

  void _sendRemoval(ServerSubLevel subLevel) {
    // Java's `sendRemoval` only sends; it leaves the tracking set alone
    // (`SubLevelTrackingSystem.java:117-125`). The sub-level is already out of
    // the container, so nothing ticks it again.
    final plotCoordinate = plotCoordinateOf(subLevel);
    final packet = ClientboundStopTrackingSubLevelPacket(plotCoordinate);
    for (final playerId in subLevel.trackingPlayers) {
      _sendPayload(playerId, packet);
    }
  }

  void _sendRemovalTo(SablePlayer player, ServerSubLevel subLevel) {
    _sendPayload(player.uuid, ClientboundStopTrackingSubLevelPacket(plotCoordinateOf(subLevel)));
  }

  /// Sends `change_bounds_sublevel` to the tracking players of every sub-level
  /// whose plot bounds changed.
  void _sendBoundsUpdates() {
    for (final subLevel in container.serverSubLevels()) {
      if (subLevel.isRemoved()) continue;

      final plotBounds = subLevel.getPlot().getBoundingBox();
      final lastNetworked = subLevel.lastNetworkedBoundingBox;
      if (plotBounds == lastNetworked) continue;

      // Java's `BoundingBox3i.set` is a raw copy; `setFrom` normalises, which
      // would turn the inverted empty box into a full-range one and resend the
      // bounds every tick.
      lastNetworked.setUncheckedFrom(plotBounds);
      final packet = ClientboundChangeBoundsSubLevelPacket(plotCoordinateOf(subLevel), plotBounds);
      for (final playerId in subLevel.trackingPlayers) {
        _sendPayload(playerId, packet);
      }
    }
  }

  /// Sends the movement of every moving sub-level, batched per player.
  void _sendMovementUpdates() {
    final movementUpdates = <String, List<_SubLevelUpdateTicket>>{};

    for (final subLevel in container.serverSubLevels()) {
      if (subLevel.isRemoved()) continue;

      var type = _UpdateTicketType.move;

      if (!subLevel.logicalPose.withinTolerance(
        subLevel.lastNetworkedPose,
        0.015 / 16.0,
        0.015 * (3.141592653589793 / 180.0),
      )) {
        subLevel.lastNetworkedPose.set(subLevel.logicalPose);
        subLevel.setLastNetworkedStopped(false);
      } else {
        if (!subLevel.getLastNetworkedStopped()) {
          type = _UpdateTicketType.stop;
          subLevel.setLastNetworkedStopped(true);
        } else {
          continue;
        }
      }

      for (final playerId in subLevel.trackingPlayers) {
        if (_playerById(playerId) == null) continue;
        movementUpdates.putIfAbsent(playerId, () => []).add(_SubLevelUpdateTicket(subLevel, type));
      }
    }

    final ms = nowMillis();
    final int msSinceLastSend;
    if (_lastSendMs == null) {
      msSinceLastSend = (1000.0 / tickRate()).round();
    } else {
      msSinceLastSend = ms - _lastSendMs!;
    }
    _lastSendMs = ms;

    _pluginNeededPlayers.clear();
    for (final plugin in plugins) {
      _pluginNeededPlayers.addAll(plugin.neededPlayers());
    }

    _currentlyUpdatingPlayers
      ..addAll(movementUpdates.keys)
      ..addAll(_pluginNeededPlayers);

    for (final playerId in _currentlyUpdatingPlayers.toList(growable: false)) {
      if (_playerById(playerId) == null) {
        _currentlyUpdatingPlayers.remove(playerId);
        continue;
      }

      if (movementUpdates.containsKey(playerId)) continue;

      final stopped = !_pluginNeededPlayers.contains(playerId);
      _sendPayload(
        playerId,
        ClientboundSableSnapshotInfoDualPacket(
          msSinceLast: msSinceLastSend,
          gameTick: _interpolationTick,
          stopped: stopped,
        ),
      );
      if (stopped) _currentlyUpdatingPlayers.remove(playerId);
    }

    for (final plugin in plugins) {
      plugin.sendTrackingData(_interpolationTick);
    }

    for (final entry in movementUpdates.entries) {
      final playerId = entry.key;
      final entries = <SnapshotEntry>[];

      for (final ticket in entry.value) {
        final subLevel = ticket.subLevel;
        final plotCoordinate = plotCoordinateOf(subLevel);

        switch (ticket.type) {
          case _UpdateTicketType.stop:
            _sendPayload(playerId, ClientboundStopMovingSubLevelPacket(plotCoordinate));
          case _UpdateTicketType.move:
            entries.add(
              SnapshotEntry(
                plotCoordinate: plotCoordinate,
                pose: subLevel.logicalPose,
                linearVelocity: Vector3d(
                  subLevel.latestLinearVelocity.x,
                  subLevel.latestLinearVelocity.y,
                  subLevel.latestLinearVelocity.z,
                ),
                angularVelocity: Vector3d(
                  subLevel.latestAngularVelocity.x,
                  subLevel.latestAngularVelocity.y,
                  subLevel.latestAngularVelocity.z,
                ),
              ),
            );
        }
      }

      _sendSnapshots(playerId, msSinceLastSend, entries);
    }

    _interpolationTick++;
  }

  /// Sends [entries] as `snapshot_info_packet` + `snapshot_packet` batches of
  /// at most [maxBatchSize] entries, over UDP when the player is connected.
  void _sendSnapshots(String playerId, int msSinceLastSend, List<SnapshotEntry> entries) {
    const maxBatchSize = 16;

    // `SubLevelTrackingSystem.java:383-404`: a player whose updates were all
    // `stop_moving` has no snapshot entries and gets no snapshot info at all.
    if (entries.isEmpty) return;

    final info = ClientboundSableSnapshotInfoDualPacket(
      msSinceLast: msSinceLastSend,
      gameTick: _interpolationTick,
      stopped: false,
    );

    final udpSender = udp;
    if (udpSender != null && udpSender.isConnected(playerId)) {
      // UDP: one info datagram, then the batches (`…:370-382`).
      SablePackets.registerUdpCodecs();
      udpSender.sendDatagram(playerId, SableUdpPackets.encode(info));
      for (var i = 0; i < entries.length; i += maxBatchSize) {
        final batch = entries.sublist(i, (i + maxBatchSize).clamp(0, entries.length));
        udpSender.sendDatagram(
          playerId,
          SableUdpPackets.encode(ClientboundSableSnapshotDualPacket(_interpolationTick, batch)),
        );
      }
      return;
    }

    // TCP fallback: Java wraps *each* batch with its own info payload in one
    // bundle (`…:383-404`).
    for (var i = 0; i < entries.length; i += maxBatchSize) {
      final batch = entries.sublist(i, (i + maxBatchSize).clamp(0, entries.length));
      _sendPayload(playerId, info);
      _sendPayload(playerId, ClientboundSableSnapshotDualPacket(_interpolationTick, batch));
    }
  }

  /// `addTrackingPlugin(plugin)`.
  void addTrackingPlugin(SubLevelTrackingPlugin plugin) {
    if (plugins.contains(plugin)) return;
    plugins.add(plugin);
  }

  // --------------------------------------------------------------- plumbing

  void _sendPayload(String playerId, SablePacket packet) {
    final sink = this.sink;
    if (sink == null) return;
    sink.sendPayload(playerId, packet.id, SablePackets.encode(packet));
  }

  void _collectPlayers(Vector3d position, Set<String> tracking) {
    for (final player in _players()) {
      if (shouldLoad(player, position)) tracking.add(player.uuid);
    }
  }

  Iterable<SablePlayer> _players() {
    final host = container.hostOrNull;
    if (host == null) return const [];
    return host.players;
  }

  SablePlayer? _playerById(String playerId) => container.hostOrNull?.playerById(playerId);

  /// The player if they are still online in this level; the host's player list
  /// is the only view of "online" the model has.
  SablePlayer? _onlinePlayer(String playerId) => container.hostOrNull?.playerById(playerId);

  /// Forgets all per-player state (a player left the server).
  void forgetPlayer(String playerId) {
    _currentlyUpdatingPlayers.remove(playerId);
    _pluginNeededPlayers.remove(playerId);
  }

  /// Clears the tracking state (shutdown).
  void close() {
    _additionQueue.clear();
    _currentlyUpdatingPlayers.clear();
    _pluginNeededPlayers.clear();
    plugins.clear();
    container.observers.remove(this);
  }

  @override
  String toString() =>
      'SubLevelTrackingSystem[${container.level.dimensionId}, '
      'tick=$_interpolationTick, updating=${_currentlyUpdatingPlayers.length}]';
}
