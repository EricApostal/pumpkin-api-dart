// CC: Tweaked's data component types, block entity types and menu types as the
// host registers them: the key, the persistence flag and the shape of the
// network encoding (a `ComponentCodec`, the prefix notation the host needs to
// find where a component value ends in a stack).
//
// Source: `ModRegistry.DataComponents` (shared/ModRegistry.java, mc-26.3), each
// type is `.persistent(<Codec>).networkSynchronized(<StreamCodec>)`, so every
// one of them is persistent here. The StreamCodec of each type:
//
// | component             | Java StreamCodec                                      | shape |
// | --------------------- | ----------------------------------------------------- | ----- |
// | computer_id           | NonNegativeId.Computer: VAR_INT.map(...)              | VarInt |
// | storage_capacity      | StorageCapacity: VAR_LONG.map(...)                    | VarLong |
// | terminal_size         | TerminalSize: composite(VAR_INT, VAR_INT)             | VarInt, VarInt |
// | left/right_turtle_upgrade, top/back_pocket_upgrade | UpgradeManager.dataStreamCodec: composite(holderRegistry (a VarInt id), DataComponentPatch.STREAM_CODEC) | VarInt, patch |
// | fuel                  | ByteBufCodecs.VAR_INT                                 | VarInt |
// | overlay               | Identifier.STREAM_CODEC                               | string |
// | computer              | ServerComputerReference: composite(VAR_INT, UUIDUtil.STREAM_CODEC) | VarInt, UUID |
// | on                    | ByteBufCodecs.BOOL                                    | flag |
// | treasure_disk         | TreasureDisk: composite(STRING_UTF8, STRING_UTF8)     | string, string |
// | disk_id               | NonNegativeId.Disk: VAR_INT.map(...)                  | VarInt |
// | printout              | PrintoutData: composite(STRING_UTF8, Line list)       | string, VarInt n, n x (string, string) |
//
// `UUIDUtil.STREAM_CODEC` is two longs (16 bytes); `holderRegistry` writes the
// registry id as a VarInt with no offset (`IdMap`-style `getIdOrThrow`).
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import 'registries.dart';

/// One data component type of CC: Tweaked.
final class CcComponentType {
  /// The path of the key (`computercraft:<name>`).
  final String name;
  final ComponentCodec codec;

  const CcComponentType(this.name, this.codec);

  String get key => '${CcRegistries.modId}:$name';

  /// Every type of the mod is `persistent(...)` in `ModRegistry`.
  bool get persistent => true;
}

/// The data component types in the order of `CcRegistries.dataComponentTypes`.
abstract final class CcComponents {
  static final ComponentCodec _upgradeData = ComponentCodec.sequence([
    ComponentCodec.varInt,
    ComponentCodec.componentPatch,
  ]);

  static final ComponentCodec _text2 = ComponentCodec.sequence([ComponentCodec.text, ComponentCodec.text]);

  static final List<CcComponentType> all = [
    CcComponentType('computer_id', ComponentCodec.varInt),
    CcComponentType('storage_capacity', ComponentCodec.varLong),
    CcComponentType('terminal_size', ComponentCodec.sequence([ComponentCodec.varInt, ComponentCodec.varInt])),
    CcComponentType('left_turtle_upgrade', _upgradeData),
    CcComponentType('right_turtle_upgrade', _upgradeData),
    CcComponentType('fuel', ComponentCodec.varInt),
    CcComponentType('overlay', ComponentCodec.text),
    CcComponentType('top_pocket_upgrade', _upgradeData),
    CcComponentType('back_pocket_upgrade', _upgradeData),
    CcComponentType('computer', ComponentCodec.sequence([ComponentCodec.varInt, ComponentCodec.uuid])),
    CcComponentType('on', ComponentCodec.flag),
    CcComponentType('treasure_disk', _text2),
    CcComponentType('disk_id', ComponentCodec.varInt),
    CcComponentType(
      'printout',
      ComponentCodec.sequence([ComponentCodec.text, ComponentCodec.repeated(_text2)]),
    ),
  ];

  static String key(String name) => '${CcRegistries.modId}:$name';

  /// `computercraft:computer_id`, `computercraft:storage_capacity`, ...
  static final String computerId = key('computer_id');
  static final String storageCapacity = key('storage_capacity');
  static final String terminalSize = key('terminal_size');
  static final String on = key('on');

  // -- Values: the bytes of the network encoding ---------------------------------

  static Uint8List encodeComputerId(int id) => PacketBuffer.encode((w) => w.writeVarInt(id));

  static int decodeComputerId(List<int> bytes) {
    final reader = PacketReader(bytes);
    final id = reader.readVarInt();
    reader.expectEnd();
    return id;
  }

  static Uint8List encodeStorageCapacity(int capacity) => PacketBuffer.encode((w) => w.writeVarLong(capacity));

  static int decodeStorageCapacity(List<int> bytes) {
    final reader = PacketReader(bytes);
    final value = reader.readVarLong();
    reader.expectEnd();
    return value;
  }

  static Uint8List encodeTerminalSize(int width, int height) =>
      PacketBuffer.encode((w) => w..writeVarInt(width)..writeVarInt(height));

  static (int, int) decodeTerminalSize(List<int> bytes) {
    final reader = PacketReader(bytes);
    final size = (reader.readVarInt(), reader.readVarInt());
    reader.expectEnd();
    return size;
  }

  static Uint8List encodeOn(bool value) => PacketBuffer.encode((w) => w.writeByte(value ? 1 : 0));

  /// `computer` (`ServerComputerReference`): the registry's session id and the
  /// instance UUID of a pocket computer.
  static Uint8List encodeComputerReference(int session, String instanceUuid) =>
      PacketBuffer.encode((w) => w..writeVarInt(session)..writeUuid(instanceUuid));
}

/// The block entity types of CC: Tweaked (`ModRegistry.BlockEntities`), in the
/// order of `CcRegistries.blockEntityTypes`. Each is valid for exactly the one
/// block of the same name (`ofBlock(block, ...)` registers
/// `block.id().getPath()` with `Set.of(block.get())`).
abstract final class CcBlockEntityTypes {
  /// `computercraft:<name>` of every type, which is also its block.
  static List<String> get all => CcRegistries.blockEntityTypes;

  /// The valid blocks of the type [key].
  static List<String> validBlocks(String key) => [key];

  /// The block entity types of the computers, which this plugin implements.
  static const List<String> computers = [
    'computercraft:computer_normal',
    'computercraft:computer_advanced',
    'computercraft:computer_command',
  ];
}

/// The menu types (`ModRegistry.Menus`), in the order of `CcRegistries.menus`.
abstract final class CcMenus {
  /// `computer`: `ComputerMenuWithoutInventory` with `ComputerContainerData`.
  static final String computer = '${CcRegistries.modId}:computer';

  /// `pocket_computer_no_term`: the same menu for a pocket computer held in the
  /// off hand (the terminal is hidden, the player only types).
  static final String pocketComputerNoTerm = '${CcRegistries.modId}:pocket_computer_no_term';

  static List<String> get all => CcRegistries.menus;
}
