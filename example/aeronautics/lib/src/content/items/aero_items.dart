// The standalone items of Aeronautics: the goggles, the music disc and the
// powder. Every other item is a block item and comes with its block.
//
// Java: `index/AeroItems.java`, `content/items/AviatorsGogglesItem.java`.
//
// Order matters: `AeroItems.init()` runs after `AeroBlocks.init()` and
// `AeroBlockEntityTypes.init()` (`Aeronautics.java:41-44`), so these three come
// after the block items in the item registry.
//
// Host: this file uses `pumpkin_api` (item registration).
// ignore_for_file: implementation_imports
import 'package:create/src/core/nbt.dart' show NbtValue, NetworkNbt;
import 'package:pumpkin_api/pumpkin_api.dart';

/// The default components the host can encode, by item key.
EncodedComponents _components(Map<String, Object?> components) => DataComponentCodec.encodeAll(components);

/// `AeroItems.AVIATORS_GOGGLES`.
const String aviatorsGogglesKey = 'aeronautics:aviators_goggles';

/// `AeroItems.MUSIC_DISC_CLOUD_SKIPPER`.
const String musicDiscCloudSkipperKey = 'aeronautics:music_disc_cloud_skipper';

/// `AeroItems.ENDSTONE_POWDER`.
const String endStonePowderKey = 'aeronautics:end_stone_powder';

/// `Registries.JUKEBOX_SONG`: a vanilla datapack registry, not one the host
/// numbers. The client resolves `jukebox_playable` while it binds item
/// components at the end of configuration, so the entry has to arrive with the
/// registry data or the client disconnects with "Missing element".
const String jukeboxSongRegistry = 'minecraft:jukebox_song';

/// `AeroJukeboxSongs.CLOUD_SKIPPER` (`data/AeroJukeboxSongs.java:24-34`).
const String cloudSkipperSongKey = 'aeronautics:cloud_skipper';

/// `AeroJukeboxSongs.bootstrap`: the `aeronautics:cloud_skipper` entry as the
/// network NBT of `JukeboxSong.DIRECT_CODEC` (`JukeboxSong.java:21-29`).
///
/// `sound_event` is `AeroSoundEvents.MUSIC_DISC_CLOUD_SKIPPER`
/// (`aeronautics:music_disc.cloud_skipper`, `index/AeroSoundEvents.java:101`),
/// the description is its translation key, and `225.0`/`12` are the length in
/// seconds and the comparator output. The field order and the double for the
/// length follow the vanilla entries the host already sends.
List<int> cloudSkipperSongNbt() => NetworkNbt.encode(
  NbtValue.compound({
    'sound_event': const NbtValue.string('aeronautics:music_disc.cloud_skipper'),
    'description': NbtValue.compound({
      'translate': const NbtValue.string('jukebox_song.aeronautics.cloud_skipper'),
    }),
    'length_in_seconds': const NbtValue.double64(225.0),
    'comparator_output': const NbtValue.int32(12),
  }),
);

/// `AeroArmorMaterials.AVIATORS_GOGGLES`'s durability, as `BaseArmorItem` gets
/// it: `ArmorType.HELMET.getDurability(15)` = `15 * 11`
/// (`content/items/AviatorsGogglesItem.java:19-23`, `index/AeroArmorMaterials.java:38-47`).
const int aviatorsGogglesDurability = 165;

/// The items `AeroItems` registers, in order.
///
/// TODO(parity): `index/AeroItems.java:45-47` gives `music_disc_cloud_skipper`
/// the `aeronautics:levitating` default component and `end_stone_powder` its
/// `END_STONE` one, and `AeroBlocks.java:405,420` does the same for the two
/// levitite items. The host's `item-registry.register-item` only accepts the
/// vanilla component set (`DataComponentCodec.supported`), so a plugin component
/// cannot be a *default* component yet; the behaviour is kept by
/// `Levitating.byItemKey` in the item-entity tick instead (same values, read from
/// the item key rather than the stack).
List<ItemRegistration> aeroItems() => [
  ItemRegistration(
    key: aviatorsGogglesKey,
    maxStackSize: 1,
    // `properties(p -> p.durability(AviatorsGogglesItem.TYPE.getDurability(
    // AeroArmorMaterials.AVIATORS_GOGGLES.value().durability())))`.
    // TODO(parity): `BaseArmorItem` also sets the helmet attributes and the
    // `minecraft:equippable` component; the host has no encoder for either, so
    // the goggles register as an unbreakable-until-damaged plain item.
    components: _components({'minecraft:max_damage': aviatorsGogglesDurability}).encoded,
  ),
  ItemRegistration(
    key: musicDiscCloudSkipperKey,
    maxStackSize: 1,
    // `.properties(p -> p.stacksTo(1).rarity(Rarity.RARE)...)`; `Rarity.RARE`
    // is ordinal 2. TODO(parity): `jukeboxPlayable(AeroJukeboxSongs.CLOUD_SKIPPER)`
    // (the host's `JukeboxPlayableImpl` only knows the vanilla songs, so it
    // would encode an empty song id) and the `aeronautics:levitating` component
    // (see above). The song itself is served as a datapack entry, see
    // `cloudSkipperSongNbt`.
    components: _components({'minecraft:rarity': 'rare'}).encoded,
  ),
  const ItemRegistration(key: endStonePowderKey),
];
