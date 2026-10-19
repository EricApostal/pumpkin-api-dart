/// Create's network payloads for all modules (published by the `protocol` module).
///
/// ```dart
/// final bus = ctx.services.require<PayloadBus>();
/// bus.onServerbound('create:configure_stockswitch', (player, f) {
///   final (x, y, z) = f['pos'] as (int, int, int);
///   final offBelow = f['offBelow'] as int;
/// });
/// bus.sendClientbound('create:remove_te', player, {'pos': (1, 64, 2)});
/// ```
///
/// Field maps use the manifest field names (`lib/src/manifest/REPORT_network.md`).
/// Value mapping: `int` for all integers and enum ordinals, `double` for floats,
/// `String` for strings, resource locations and uuids, `(int, int, int)` for block
/// positions, `(double, double, double)` for vec3, [NbtValue] for NBT and text
/// components, [ItemStackData] / [FluidStackData] for stacks, `Map<String, Object?>`
/// for nested records, [PayloadVariant] for dispatch, [EitherValue] for either.
/// The complete table is at the top of `lib/src/protocol/codec_compiler.dart`.
library;

export '../core/nbt.dart' show NbtKind, NbtValue;
export '../protocol/codec_compiler.dart' show PayloadSchema, PayloadSchemas, SchemaException, WireCodec, compileType;
export '../protocol/host_item_stack.dart' show HostItemStacks;
export '../protocol/item_stack.dart';
export '../protocol/payload_bus.dart' show PayloadBus, PlayerRoster;
export '../protocol/payload_hub.dart' show BadPayload, PayloadHub, RateLimitedLog, registerPayloadChannels;
export '../protocol/protocol_module.dart' show ProtocolModule;
export '../protocol/wire_values.dart';
