// The plugin's implementation of the tracking system's send seams: a
// [SablePayloadSink] over the host's payload channel and a [SableChunkViewSender]
// over `chunk-streaming`, so a tracking player is actually told about a
// sub-level instead of the model talking to nobody.
//
// **Transport.** Movement goes over **TCP** on the payload channel: Java sends
// `snapshot_info_packet` + `snapshot_packet` over UDP when the player completed
// the UDP handshake and falls back to exactly these TCP payloads when it has not
// (`SubLevelTrackingSystem.java:383-404`). The host has no UDP surface at all —
// the host gap `udp-channel` (`sublevel/vanilla/host_gap.dart`) names the missing
// calls (`bind-udp`, `send-datagram`, `on-datagram`) — so the UDP transport is
// **deferred** and TCP is the supported path. `sable:udp_activation` is
// deliberately **not** sent: activating a UDP channel whose server socket does
// not exist would make the client `AUTH` into the void. Nothing else changes:
// the payloads and their order are identical on both transports, which is why
// the fallback is a supported path rather than a degraded one.
//
// **Order.** The model calls the sink synchronously, in the Java order
// (`start_tracking_sublevel`, the plot's chunk sends, `finalize_sub_level`), and
// each call becomes an async host call. Two independent host calls would race and
// the client could finalize the plot before the chunks that fill it arrive, so
// every send for one player is appended to a per-player chain: the order of the
// calls is the order on the wire, and the chunk packets land between the two
// payloads exactly as Java's one bundle puts them.
//
// Host: this file uses `pumpkin_api`.
import 'dart:async';
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../sublevel/system/tracking_system.dart';
import 'pumpkin_level.dart';
import 'pumpkin_sub_level_host.dart' show PumpkinSubLevelHost;

/// Sends Sable's tracking payloads and the plot's chunks to tracking players.
///
/// [SableUdpSender] is deliberately **not** implemented: there is no host socket
/// to send a datagram on, so the tracking system takes its TCP fallback (see the
/// file comment). Implementing it without the host's `bind-udp`/`send-datagram`
/// would only make `isConnected` answer `true` for a channel that cannot exist.
final class PumpkinTrackingSender implements SablePayloadSink, SableChunkViewSender {
  PumpkinTrackingSender({required this.host, required this.chunks, this.logger});

  /// The chunk host whose plot chunks the sender ships.
  final PumpkinPlotChunkHost chunks;

  /// The level's host bridge (player lookup).
  final PumpkinSubLevelHost host;

  /// Where a failure is reported.
  final void Function(String message)? logger;

  /// One in-flight send per player: the sends of one tick are chained, so the
  /// payloads and the chunk packets keep the order the model made them in.
  final Map<String, Future<void>> _queues = {};

  /// How many payloads and chunk packets have been handed to the host. A sync
  /// that sends nothing is then visible instead of silent.
  int payloadCount = 0;
  int chunkCount = 0;

  /// How many chunk packets actually reached the client.
  int sentChunks = 0;

  /// How many sends were dropped because the host would not hand back a player
  /// handle for the id (the client left, or the handle lookup failed).
  int droppedSends = 0;

  /// The plot chunk sends waiting for the host to load the chunk, by player.
  final Map<String, Set<(int, int)>> _queuedChunks = {};

  /// When the first chunk send was queued, for the wait reported in the log.
  int? _queuedSince;

  /// The wall clock, injectable for tests.
  int Function() nowMillis = () => DateTime.now().millisecondsSinceEpoch;

  /// The sends that failed, by what was being sent.
  final Map<String, int> failures = {};

  /// Whether a payload the client needs failed at least once.
  bool get hadFailure => failures.isNotEmpty;

  @override
  void sendPayload(String playerId, String payloadId, Uint8List body) {
    payloadCount++;
    _enqueue(playerId, (player) async {
      final java = player.asJava();
      if (java == null) return; // Bedrock players have no custom payloads.
      try {
        await java.sendCustomPayload(channel: payloadId, data: body);
        PumpkinPlotChunkHost.diagMirror('sent $payloadId (${body.length} bytes) to $playerId');
      } on Object catch (error) {
        _fail('payload:$payloadId', 'sending $payloadId failed: $error');
        rethrow;
      } finally {
        java.dispose();
      }
    });
  }

  @override
  void sendChunkAt(String playerId, int blockX, int blockZ) {
    chunkCount++;
    _enqueue(playerId, (player) => _sendChunk(playerId, player, blockX, blockZ));
  }

  /// Sends one chunk if the world has it, and queues it otherwise.
  Future<void> _sendChunk(String playerId, Player player, int blockX, int blockZ) async {
    final chunkX = blockX >> 4;
    final chunkZ = blockZ >> 4;
    // The host generates the chunk (there is no plugin-owned empty chunk yet,
    // see `host_gap.dart`'s `chunk-source`), and at the plot yard that takes
    // longer than a client's keep-alive: the load is requested but never
    // awaited, and the chunk goes out on the tick the world has it.
    if (!chunks.ensurePlotChunkWanted(chunkX, chunkZ)) {
      _queuedChunks.putIfAbsent(playerId, () => {}).add((chunkX, chunkZ));
      final waiting = (nowMillis() - (_queuedSince ??= nowMillis())) ~/ 1000;
      if (_queuedChunks[playerId]!.length == 1 || waiting % 30 == 0) {
        PumpkinPlotChunkHost.diagMirror(
          'chunk $chunkX, $chunkZ is not in the world yet (waited ${waiting}s); '
          'queued for $playerId',
        );
      }
      return;
    }
    if (!await chunks.mirrorPlotChunk(chunkX, chunkZ)) return;
    final result = await chunkStreaming.sendChunkAt(
      player: player,
      pos: BlockPos(x: blockX, y: 0, z: blockZ),
    );
    switch (result) {
      case OkResult():
        sentChunks++;
        PumpkinPlotChunkHost.diagMirror('sent chunk $chunkX, $chunkZ to $playerId');
      case ErrorResult(value: final error):
        _fail('chunk($chunkX,$chunkZ)', 'the host refused send-chunk-at: $error');
    }
  }

  /// Retries the chunk sends that were waiting for the host to load the chunk.
  ///
  /// The plugin calls this once a tick: a queued chunk that has arrived in the
  /// world is mirrored and sent, so a sub-level follows the plot chunk that the
  /// host generated for it even when that is later than the sync that announced
  /// it (the client's plot takes a chunk packet whenever one arrives, before or
  /// after `finalize_sub_level`).
  int flushQueuedChunks() {
    if (_queuedChunks.isEmpty) return 0;
    var sent = 0;
    for (final entry in _queuedChunks.entries.toList()) {
      final playerId = entry.key;
      for (final (chunkX, chunkZ) in entry.value.toList()) {
        if (!chunks.isPlotChunkLoaded(chunkX, chunkZ)) continue;
        entry.value.remove((chunkX, chunkZ));
        _enqueue(playerId, (player) => _sendChunk(playerId, player, chunkX << 4, chunkZ << 4));
        sent++;
      }
      if (entry.value.isEmpty) _queuedChunks.remove(playerId);
    }
    if (sent > 0) {
      PumpkinPlotChunkHost.diagMirror('the host loaded $sent queued plot chunk(s); sending them');
    }
    return sent;
  }

  @override
  void unloadChunkAt(String playerId, int blockX, int blockZ) {
    _enqueue(playerId, (player) async {
      try {
        chunkStreaming.unloadChunkAt(player: player, pos: BlockPos(x: blockX, y: 0, z: blockZ));
      } on Object catch (error) {
        _fail('unchunk($blockX,$blockZ)', 'unload-chunk-at failed: $error');
      }
    });
  }

  /// Drops the send queue of a player that left.
  void forgetPlayer(String playerId) => _queues.remove(playerId);

  /// Completes when every send queued for [playerId] so far has gone out.
  Future<void> settled(String playerId) => _queues[playerId] ?? Future<void>.value();

  /// Appends one send to the player's chain. The player handle is resolved
  /// inside the chain, so a player who left between two sends is skipped and a
  /// handle is never kept past its own send.
  void _enqueue(String playerId, Future<void> Function(Player player) body) {
    final previous = _queues[playerId] ?? Future<void>.value();
    _queues[playerId] = previous.then((_) async {
      final player = host.playerHandle(playerId);
      if (player == null) {
        // A player the host will not hand back a handle for: the send is
        // dropped, and *that* must be visible — a sync that reaches nobody
        // looks exactly like a client that renders nothing.
        droppedSends++;
        PumpkinPlotChunkHost.diagMirror('no live player handle for $playerId; send dropped');
        return;
      }
      try {
        await body(player);
      } on Object catch (error, stack) {
        // A send that throws must not break the chain for the next sync.
        _fail('send', 'sending to $playerId failed: $error\n$stack');
      } finally {
        player.dispose();
      }
    });
  }

  void _fail(String key, String message) {
    failures[key] = (failures[key] ?? 0) + 1;
    logger?.call('Sable: $message');
  }

  @override
  String toString() =>
      'PumpkinTrackingSender[payloads=$payloadCount, chunks=$chunkCount, '
      'failures=${failures.length}, players=${_queues.length}]';
}