// The ids of everything Offroad registers, in the order the Java mod registers
// them. NeoForge numbers the entries of a registry by position, so these lists
// are the canonical order the plugin pins with `CreateRegistry.useOrder`.
//
// The lists are the ones `OffroadRegistry` iterates: it refuses to register a
// key that is not at the position the list gives it, which is what keeps a
// client built against the Java mod and a client built against this port in
// agreement about every numeric id.
//
// Pure: no host imports, so the VM tests can check the order.
//
// Java: `index/OffroadBlocks`, `index/OffroadItems`, `index/OffroadBlockEntityTypes`,
//       `index/OffroadEntityTypes`, `index/OffroadDataComponents`,
//       `index/OffroadContraptionTypes`.
library;

/// The mod id.
const String offroadModId = 'offroad';

/// `Offroad.path(path)`.
String offroadPath(String path) => '$offroadModId:$path';

/// The ids of Offroad.
abstract final class OffroadIds {
  // -- Blocks -------------------------------------------------------------------

  /// `OffroadBlocks.BOREHEAD_BEARING_BLOCK` (`OffroadBlocks.java:35`).
  static const String boreheadBearing = 'offroad:borehead_bearing';

  /// `OffroadBlocks.ROCK_CUTTER_BLOCK` (`OffroadBlocks.java:62`). The Java id
  /// has no underscore between "rock" and "cutting"; it is not a typo to fix.
  static const String rockCuttingWheel = 'offroad:rockcutting_wheel';

  /// `OffroadBlocks.WHEEL_MOUNT` (`OffroadBlocks.java:88`).
  static const String wheelMount = 'offroad:wheel_mount';

  /// The blocks, in `OffroadBlocks` field order (`Offroad.java:37`).
  static const List<String> blocks = [boreheadBearing, rockCuttingWheel, wheelMount];

  // -- Items --------------------------------------------------------------------

  /// `OffroadItems.SMALL_TIRE` (`OffroadItems.java:19`).
  static const String smallTire = 'offroad:small_tire';

  /// `OffroadItems.TIRE` (`OffroadItems.java:29`).
  static const String tire = 'offroad:tire';

  /// `OffroadItems.LARGE_TIRE` (`OffroadItems.java:42`).
  static const String largeTire = 'offroad:large_tire';

  /// `OffroadItems.MONSTROUS_TIRE` (`OffroadItems.java:55`).
  static const String monstrousTire = 'offroad:monstrous_tire';

  /// The tire items, in `OffroadItems` field order.
  static const List<String> tires = [smallTire, tire, largeTire, monstrousTire];

  /// The items, in registration order.
  ///
  /// Registrate registers a block's item inside the block's builder
  /// (`OffroadBlocks.java:58-60,82-86,98-99`), and `Offroad.init()` registers
  /// the blocks before the items (`Offroad.java:37-41`), so the three block
  /// items come first and the four tires after them.
  static const List<String> items = [
    boreheadBearing,
    rockCuttingWheel,
    wheelMount,
    ...tires,
  ];

  // -- Block entity types --------------------------------------------------------

  /// `OffroadBlockEntityTypes.WHEEL_MOUNT` (`OffroadBlockEntityTypes.java:22`).
  static const String wheelMountBlockEntity = 'offroad:wheel_mount';

  /// `OffroadBlockEntityTypes.BOREHEAD_BEARING` (`OffroadBlockEntityTypes.java:29`).
  static const String boreheadBearingBlockEntity = 'offroad:borehead_bearing';

  /// `OffroadBlockEntityTypes.ROCKCUTTING_WHEEL_BLOCK_ENTITY`
  /// (`OffroadBlockEntityTypes.java:37`).
  static const String rockCuttingWheelBlockEntity = 'offroad:rockcutting_wheel';

  /// The block entity types, in `OffroadBlockEntityTypes` field order
  /// (`Offroad.java:38`).
  static const List<String> blockEntityTypes = [
    wheelMountBlockEntity,
    boreheadBearingBlockEntity,
    rockCuttingWheelBlockEntity,
  ];

  // -- Entity types --------------------------------------------------------------

  /// `OffroadEntityTypes.BOREHEAD_CONTRAPTION_ENTITY`
  /// (`OffroadEntityTypes.java:20`).
  static const String boreheadContraptionEntity = 'offroad:borehead_contraption_entity';

  /// The entity types, in registration order (`Offroad.java:39`).
  static const List<String> entityTypes = [boreheadContraptionEntity];

  // -- Data components -----------------------------------------------------------

  /// `OffroadDataComponents.TIRE` (`OffroadDataComponents.java:14`).
  static const String tireComponent = 'offroad:tire';

  /// The data components, in registration order (`Offroad.java:40`).
  static const List<String> dataComponents = [tireComponent];

  // -- Contraption types ---------------------------------------------------------

  /// `OffroadContraptionTypes.BOREHEAD_CONTRAPTION_TYPE`
  /// (`OffroadContraptionTypes.java:17`). Appended to Create's
  /// `create:contraption_type` registry, not a registry of its own.
  static const String boreheadContraption = 'offroad:borehead_contraption';

  /// The entry appended to `create:contraption_type`.
  static const List<String> contraptionTypes = [boreheadContraption];

  // -- Channels ------------------------------------------------------------------

  /// `ClientboundMultiMiningSync.TYPE` (`ClientboundMultiMiningSync.java:22`).
  static const String boreheadSyncBlocksChannel = 'offroad:borehead_sync_blocks';

  /// `VeilPacketManager.create(Offroad.MOD_ID, "0.1")`
  /// (`network/OffroadPacketManager.java`).
  static const String channelVersion = '0.1';
}
