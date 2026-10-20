// The saved-data models of the sub-level system, as plain maps.
//
// Java stores these in `SavedData` files through `SavedDataType`:
//  * `sable_sub_level_occupancy`: the plot grid occupancy as a `long[]`;
//  * `sable_sub_level_force_load_tickets`: the tickets and their save pointers;
//  * `sable_tracking_points`: the per-player tracking points.
//
// The map shapes are the NBT shapes the Java codecs produce, so the port can
// read and write the same files once an NBT host bridge exists.
//
// Pure: no host imports.
import '../api/sub_level_ticket.dart';
import '../util/bit_grid.dart';
import '../util/uuid.dart';
import 'holding/saved_pointer.dart';

/// The saved data key of the occupancy.
const String occupancySavedDataName = 'sable_sub_level_occupancy';

/// The saved data key of the force-load tickets.
const String ticketsSavedDataName = 'sable_sub_level_force_load_tickets';

/// The saved data key of the tracking points.
const String trackingPointsSavedDataName = 'sable_tracking_points';

/// `SubLevelOccupancySavedData`: loads the occupancy into [occupancy] and
/// produces the tag to save.
abstract final class OccupancySavedData {
  /// The NBT key of the long array.
  static const String key = 'sub_level_occupancy';

  /// `load`: fills [occupancy] from [tag].
  static void load(Map<String, Object?> tag, BitGrid occupancy) {
    final raw = tag[key];
    if (raw is! List || raw.isEmpty) return;
    final longs = [for (final value in raw) (value as num).toInt()];
    occupancy.copyFrom(BitGrid.fromLongArray(longs, occupancy.length));
  }

  /// `saveTo`: the tag of [occupancy].
  static Map<String, Object?> save(BitGrid occupancy) => {key: occupancy.toLongArray()};
}

/// `SubLevelTicketsSavedData`: loads and saves the force-load tickets.
abstract final class TicketsSavedData {
  /// The NBT key of the ticket list.
  static const String key = 'tickets';

  /// `load`: reads the ticket infos from [tag].
  ///
  /// Unknown ticket types and undecodable keys are skipped (Java logs them).
  static Map<String, SubLevelTicketInfo> load(Map<String, Object?> tag) {
    final result = <String, SubLevelTicketInfo>{};
    final raw = tag[key];
    if (raw is! List) return result;

    for (final entry in raw) {
      if (entry is! Map) continue;
      final infoTag = Map<String, Object?>.from(entry);

      final uuidTag = infoTag['uuid'];
      if (uuidTag == null) continue;
      final subLevelId = uuidFromInts([for (final i in uuidTag as List) (i as num).toInt()]);

      final tickets = <SubLevelLoadingTicket<Object?>>[];
      final entries = infoTag['entries'];
      if (entries is List) {
        for (final ticketTag in entries) {
          if (ticketTag is! Map) continue;
          final ticket = _deserializeTicket(subLevelId, Map<String, Object?>.from(ticketTag));
          if (ticket != null) tickets.add(ticket);
        }
      }

      GlobalSavedSubLevelPointer? pointer;
      final pointerTag = infoTag['pointer'];
      if (pointerTag is Map) {
        pointer = GlobalSavedSubLevelPointer.fromMap(Map<String, Object?>.from(pointerTag));
      }

      if (tickets.isNotEmpty) {
        result[subLevelId] = SubLevelTicketInfo(pointer, tickets.toSet());
      }
    }
    return result;
  }

  static SubLevelLoadingTicket<Object?>? _deserializeTicket(
    String subLevelId,
    Map<String, Object?> tag,
  ) {
    final typeName = tag['type'];
    if (typeName is! String) return null;
    final type = SubLevelLoadingTicketType.byName(typeName);
    if (type == null) return null;

    final key = type.codec.decode(tag['key']);
    if (key == null && type != SubLevelLoadingTicketType.commandForced) return null;
    return SubLevelLoadingTicket<Object?>(type, subLevelId, key);
  }

  /// `serializeTag`: the tag of [allTickets].
  ///
  /// [pointerOf] resolves the save pointer of a sub-level that is currently
  /// loaded (Java prefers the live sub-level's pointer over the stored one).
  static Map<String, Object?> save(
    Map<String, SubLevelTicketInfo> allTickets, {
    GlobalSavedSubLevelPointer? Function(String uuid)? pointerOf,
  }) {
    final infos = <Object?>[];
    for (final entry in allTickets.entries) {
      final info = entry.value;
      final pointer = pointerOf?.call(entry.key) ?? info.pointer;

      final entries = <Object?>[];
      for (final ticket in info.tickets) {
        final keyTag = ticket.type.codec.encode(ticket.key);
        entries.add({'type': ticket.type.name, 'key': keyTag});
      }

      if (entries.isEmpty) continue;

      final infoTag = <String, Object?>{
        'uuid': uuidToInts(entry.key),
        if (pointer != null) 'pointer': pointer.toMap(),
        'entries': entries,
      };
      infos.add(infoTag);
    }
    return {key: infos};
  }
}
