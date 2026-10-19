// Packed block positions (pure). The same layout as Minecraft's `BlockPos.asLong`
// and `PacketWriter.writeBlockPos`: x 26 bits, z 26 bits, y 12 bits.

/// Packs a block position into one 64-bit number, usable as a map key.
int packPos(int x, int y, int z) =>
    ((x & 0x3FFFFFF) << 38) | ((z & 0x3FFFFFF) << 12) | (y & 0xFFF);

/// The inverse of [packPos].
(int, int, int) unpackPos(int packed) =>
    (packed >> 38, (packed << 52) >> 52, (packed << 26) >> 38);
