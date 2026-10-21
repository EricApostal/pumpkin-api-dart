// `ClientboundMultiMiningSync`: the payload that turns the server's
// `BlockBreakingData` into the client's destruction-progress overlay.
//
// The byte layout is the Java `StreamCodec.of(write, read)` of
// `ClientboundMultiMiningSync`:
//
// ```
// int   breakingId                  (MultiMiningServerManager's, negative)
// int   entry count
// repeat:
//   long   block position           (BlockPos.STREAM_CODEC: x 26 bits, z 26, y 12)
//   bool   invalid                  (progress >= 10)
//   byte   progress                 (only when !invalid)
// ```
//
// Pure: no host imports, so the round trip is tested on the VM.
//
// Java: `network/borehead_bearing/ClientboundMultiMiningSync.java:56-86`
// ignore_for_file: implementation_imports
import 'dart:typed_data';

import 'package:create/src/common/common.dart' show Pos;
import 'package:pumpkin_api/pumpkin_api_core.dart'
    show PacketException, PacketReader, PacketWriter, PayloadCodec;

import '../index/offroad_ids.dart';

/// One entry of the payload: the destruction progress of one block, or the mark
/// that it is gone (`ClientBlockBreakingData`).
final class MultiMiningSyncEntry {
  /// `invalid`: the client must drop the overlay (`progress >= 10`, or the `-1`
  /// the server writes when a position stops being mined).
  final bool invalid;

  /// `destroyProgress` as the byte the payload carries (0 to 255).
  final int progressByte;

  const MultiMiningSyncEntry({required this.invalid, required this.progressByte});

  /// `BlockBreakingData.clientAimedSerialization`
  /// (`MultiMiningServerManager.java:235-241`).
  factory MultiMiningSyncEntry.forProgress(double progress) => progress >= 10
      ? const MultiMiningSyncEntry(invalid: true, progressByte: 0)
      : MultiMiningSyncEntry(invalid: false, progressByte: progress.truncate() & 0xFF);

  /// The entry for a progress the client already considers broken.
  static const MultiMiningSyncEntry gone = MultiMiningSyncEntry(invalid: true, progressByte: 0);

  /// The progress as the float the client stores (Java reads the byte into a
  /// float through `ClientBlockBreakingData.destroyProgress`).
  double get progress => invalid ? 10 : progressByte.toDouble();

  @override
  bool operator ==(Object other) =>
      other is MultiMiningSyncEntry && other.invalid == invalid && other.progressByte == progressByte;

  @override
  int get hashCode => Object.hash(invalid, progressByte);

  @override
  String toString() => invalid ? 'entry(gone)' : 'entry($progressByte)';
}

/// `ClientboundMultiMiningSync`.
final class MultiMiningSyncPacket {
  /// `breakingID` (`ClientboundMultiMiningSync.java:28`).
  final int breakingId;

  /// The entries, by block position, in the order the server put them in.
  ///
  /// The Java packet has two maps: the server writes `inData` and the client
  /// fills `clientInData`. A decoded entry carries exactly what the wire
  /// carries, so one map serves both directions.
  final Map<Pos, MultiMiningSyncEntry> entries;

  MultiMiningSyncPacket._(this.breakingId, this.entries);

  /// `serverOutboundData(id)` (`ClientboundMultiMiningSync.java:44`).
  factory MultiMiningSyncPacket.serverOutbound(int breakingId) =>
      MultiMiningSyncPacket._(breakingId, <Pos, MultiMiningSyncEntry>{});

  /// Puts the progress of [pos] into the payload
  /// (`inData.put(breakingPos, data)` plus `clientAimedSerialization`).
  void add(Pos pos, double progress) {
    entries[pos] = MultiMiningSyncEntry.forProgress(progress);
  }

  /// The channel the packet travels on (`Offroad.path("borehead_sync_blocks")`,
  /// `ClientboundMultiMiningSync.java:22`).
  static const String channel = OffroadIds.boreheadSyncBlocksChannel;

  /// `ClientboundMultiMiningSync.CODEC` (`ClientboundMultiMiningSync.java:24-26`).
  static final PayloadCodec<MultiMiningSyncPacket> codec =
      PayloadCodec<MultiMiningSyncPacket>.buffer(write: _write, read: _read);

  static void _write(PacketWriter writer, MultiMiningSyncPacket packet) {
    writer.writeInt(packet.breakingId);

    writer.writeInt(packet.entries.length);
    for (final entry in packet.entries.entries) {
      writer.writeBlockPos(entry.key);
      writer.writeBool(entry.value.invalid);
      if (!entry.value.invalid) writer.writeByte(entry.value.progressByte);
    }
  }

  static MultiMiningSyncPacket _read(PacketReader reader) {
    final breakingId = reader.readInt();
    final packet = MultiMiningSyncPacket.serverOutbound(breakingId);

    final size = reader.readInt();
    if (size < 0) throw PacketException('Negative multi-mining entry count $size');
    for (var i = 0; i < size; i++) {
      final pos = reader.readBlockPos();
      final invalid = reader.readBool();
      final progress = invalid ? 0 : reader.readUnsignedByte();
      packet.entries[pos] = MultiMiningSyncEntry(invalid: invalid, progressByte: progress);
    }

    return packet;
  }

  /// The exact bytes `CODEC.encode` produces, for the byte-layout test.
  static Uint8List encode(MultiMiningSyncPacket packet) => codec.encode(packet);

  @override
  String toString() => 'MultiMiningSyncPacket($breakingId, ${entries.length} entries)';
}