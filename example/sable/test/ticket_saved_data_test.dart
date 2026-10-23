// The force-load ticket saved data: the file that makes a sub-level come back
// after a restart.
//
// This is its own test file because the bug it pins is about *initialization
// order*: `SubLevelLoadingTicketType.byName` used to search a registry that was
// empty until something else touched `commandForced`, so the first load of a
// world dropped every saved ticket as an "unknown type". A test in a file that
// had already used the ticket type could never see that, so the first thing this
// file does is load a saved tag — no other `sable` API is touched before it.

import 'package:sable/sable.dart';
import 'package:test/test.dart';

const String uuid = '00b5f377-58e2-4dd8-b63b-393ef497868d';

/// The tag the plugin wrote for a force-loaded sub-level, byte for byte what
/// `TicketsSavedData.save` produces (`pointer` present because the sub-level had
/// been saved when the ticket was flushed).
Map<String, Object?> savedTag() => {
  'tickets': [
    {
      'uuid': uuidToInts(uuid),
      'pointer': {'chunk_x': 0, 'chunk_z': 0, 'storage_index': 0, 'sub_level_index': 0},
      'entries': [
        {'type': 'sable:command_forced'},
      ],
    },
  ],
};

void main() {
  test('a saved ticket loads before anything else registered a ticket type', () {
    final loaded = TicketsSavedData.load(savedTag());

    expect(loaded.keys, [uuid], reason: 'the built-in type must be in the registry already');
    final info = loaded[uuid]!;
    expect(info.tickets, hasLength(1));
    expect(info.tickets.single.type, SubLevelLoadingTicketType.commandForced);
    expect(info.pointer, const GlobalSavedSubLevelPointer(0, 0, 0, 0));
  });

  test('a ticket without a pointer still loads (and is reported by the container)', () {
    final tag = savedTag();
    ((tag['tickets']! as List).single as Map).remove('pointer');

    final info = TicketsSavedData.load(tag)[uuid]!;
    expect(info.tickets, hasLength(1));
    expect(info.pointer, isNull, reason: 'Java logs that such a ticket cannot be loaded');
  });

  test('a real gzip NBT file round trips the ticket', () {
    final codec = NbtSubLevelCodec();
    final tag = TicketsSavedData.save({
      uuid: SubLevelTicketInfo(
        const GlobalSavedSubLevelPointer(3, -4, 0, 1),
        {
          SubLevelLoadingTicket<Object?>(
            SubLevelLoadingTicketType.commandForced,
            uuid,
            const Object(),
          ),
        },
      ),
    });

    final decoded = codec.decode(codec.encode(tag));
    final loaded = TicketsSavedData.load(decoded)[uuid]!;
    expect(loaded.pointer, const GlobalSavedSubLevelPointer(3, -4, 0, 1));
    expect(loaded.tickets.single.type, SubLevelLoadingTicketType.commandForced);
  });

  test('an unknown ticket type is skipped, not invented', () {
    final tag = savedTag();
    (((tag['tickets']! as List).single as Map)['entries']! as List).add({'type': 'other:mod'});

    final info = TicketsSavedData.load(tag)[uuid]!;
    expect(info.tickets, hasLength(1), reason: 'only the known type survives');
  });
}
