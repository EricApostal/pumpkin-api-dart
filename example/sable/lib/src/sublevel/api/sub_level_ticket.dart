// `dev.ryanhcode.sable.api.sublevel.ticket`: force-load tickets for sub-levels.
//
// A ticket type is registered by name and carries a codec for its key. Sable's
// own `command_forced` type is registered here; other modules register theirs
// with [SubLevelLoadingTicketType.create]. The key codec is a pair of
// functions rather than a Mojang `Codec`, since the port's NBT model is the
// `NbtValue` tree of `core/nbt.dart`.
//
// Pure: no host imports.
import '../storage/holding/saved_pointer.dart';

/// The key codec of a ticket type: `encode(key) -> NbtValue`,
/// `decode(NbtValue) -> key?`.
final class TicketKeyCodec<T> {
  final Object? Function(T key) encode;
  final T? Function(Object? tag) decode;

  const TicketKeyCodec(this.encode, this.decode);
}

/// `SubLevelLoadingTicketType<T>`: a named ticket type with a key codec.
final class SubLevelLoadingTicketType<T> {
  /// Every registered type, by name (Java's static `REGISTRY`).
  static final Map<String, SubLevelLoadingTicketType<Object?>> registry = {};

  final String name;
  final TicketKeyCodec<T> codec;

  SubLevelLoadingTicketType._(this.name, this.codec);

  /// `SubLevelLoadingTicketType.create(Identifier, Codec)`.
  static SubLevelLoadingTicketType<T> create<T>(String name, TicketKeyCodec<T> codec) {
    final type = SubLevelLoadingTicketType<T>._(name, codec);
    registry[name] = type;
    return type;
  }

  /// `SubLevelLoadingTicketType.byName(Identifier)`.
  static SubLevelLoadingTicketType<Object?>? byName(String name) => registry[name];

  /// The built-in `sable:command_forced` type, whose key is `Unit` (`null`).
  static final SubLevelLoadingTicketType<Object?> commandForced =
      create<Object?>('sable:command_forced', TicketKeyCodec<Object?>((_) => null, (_) => const Object()));

  @override
  String toString() => 'SubLevelTicketType{name=$name}';
}

/// `SubLevelLoadingTicket<T>`: one ticket on one sub-level.
final class SubLevelLoadingTicket<T> {
  final SubLevelLoadingTicketType<T> type;
  final String subLevelId;
  final T key;

  const SubLevelLoadingTicket(this.type, this.subLevelId, this.key);

  /// `toCompactString`.
  String toCompactString() => 'Ticket[${type.name} ($key)]';

  @override
  bool operator ==(Object other) =>
      other is SubLevelLoadingTicket<T> &&
      other.type == type &&
      other.subLevelId == subLevelId &&
      other.key == key;

  @override
  int get hashCode => Object.hash(type, subLevelId, key);

  @override
  String toString() => 'SubLevelLoadingTicket[${type.name} $subLevelId ($key)]';
}

/// `SubLevelTicketInfo`: all tickets of one sub-level, plus the pointer to
/// where the sub-level was last saved (needed to load it back).
final class SubLevelTicketInfo {
  final Set<SubLevelLoadingTicket<Object?>> tickets = {};
  GlobalSavedSubLevelPointer? _pointer;

  SubLevelTicketInfo([this._pointer, Set<SubLevelLoadingTicket<Object?>>? tickets]) {
    if (tickets != null) this.tickets.addAll(tickets);
  }

  GlobalSavedSubLevelPointer? get pointer => _pointer;

  set pointer(GlobalSavedSubLevelPointer? value) => _pointer = value;
}
