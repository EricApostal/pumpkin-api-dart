// `ContraptionPickupLimiting` (pure): whether a contraption's NBT is too large for a wrench pickup.
//
// Create raises the limit when PacketFixer or XL Packets is installed; the host plugin has no way
// to detect NeoForge mods, so the vanilla `FriendlyByteBuf` NBT limit is used. The size is measured
// the way the client accounts it: the length of the network NBT encoding.
import '../../core/nbt.dart';
import '../core/nbt_map.dart';

abstract final class ContraptionPickupLimiting {
  /// The default NBT limit, defined by `FriendlyByteBuf.readNbt()`.
  static const int nbtLimit = 2097152;

  /// Space left for the rest of the packet.
  static const int buffer = 20000;

  /// The limit the pickup check uses.
  static const int limit = nbtLimit - buffer;

  /// `isTooLargeForPickup(Tag)`: true when the client would refuse the NBT.
  static bool isTooLargeForPickup(NbtMap data) => sizeOf(data) > limit;

  /// The size of [data] as network NBT, in bytes.
  static int sizeOf(NbtMap data) => NetworkNbt.encode(data.toValue()).length;
}
