// `dev.ryanhcode.sable.sublevel.system.ticket`: the chunk tickets that keep the
// chunks a sub-level occupies loaded.
//
// `PhysicsChunkTicket` tracks one chunk section that a sub-level's physics body
// touches; `InhabitedChunkTicket` tracks a chunk force-loaded because a player
// inhabits it. Both expire after a timeout (`lastInhabitedTick`).
//
// Pure: no host imports.
import '../model/sub_level.dart';

/// A ticket for a chunk tracked by a `PhysicsChunkTicketManager`.
final class PhysicsChunkTicket {
  final (int, int, int) pos;
  int lastInhabitedTick;
  final List<SubLevel> residentSubLevels;

  PhysicsChunkTicket(this.pos, this.lastInhabitedTick, this.residentSubLevels);

  /// The section position.
  (int, int, int) get position => pos;

  /// The last tick the chunk was inhabited.
  int getLastInhabitedTick() => lastInhabitedTick;

  /// Sets the last inhabited tick.
  void setLastInhabitedTick(int tick) => lastInhabitedTick = tick;

  /// The sub-levels that occupy the section.
  List<SubLevel> getResidentSubLevels() => residentSubLevels;

  @override
  bool operator ==(Object other) => other is PhysicsChunkTicket && other.pos == pos;

  @override
  int get hashCode => Object.hash(pos, lastInhabitedTick);

  @override
  String toString() => 'PhysicsChunkTicket[pos=$pos, lastInhabitedTick=$lastInhabitedTick, '
      'residentSubLevels=${residentSubLevels.length}]';
}

/// A ticket for a chunk force-loaded by a sub-level in the
/// `PhysicsChunkTicketManager`.
final class InhabitedChunkTicket {
  final String uuid;
  int lastInhabitedTick;

  /// The host ticket handle.
  final Object ticket;

  InhabitedChunkTicket(this.uuid, this.lastInhabitedTick, this.ticket);

  /// The last tick the chunk was inhabited.
  int getLastInhabitedTick() => lastInhabitedTick;

  /// Sets the last inhabited tick.
  void setLastInhabitedTick(int tick) => lastInhabitedTick = tick;

  /// The host ticket handle.
  Object getTicket() => ticket;

  @override
  bool operator ==(Object other) => other is InhabitedChunkTicket && other.uuid == uuid;

  @override
  int get hashCode => uuid.hashCode;

  @override
  String toString() => 'InhabitedChunkTicket[$uuid, lastInhabitedTick=$lastInhabitedTick]';
}
