/// Dart API for writing Pumpkin Minecraft server plugins.
///
/// This is a typed wrapper over the bindings generated from
/// `pumpkin-plugin-wit` (see `tool/generate_bindings.sh`). Everything the host
/// exposes is available, and the parts that are awkward to use directly --
/// commands, events, tasks, errors -- have a nicer API on top:
///
/// * [Plugin] and [runPlugin] to define a plugin,
/// * `Context.listen`/`Context.intercept` with the typed [Events],
/// * [CommandHandler]s as closures, typed [ArgumentTypes] and argument access,
/// * `runLater`/`runRepeating` for scheduling and [logger] for logging.
library;

export 'package:wasm_components/wasm_components.dart'
    show Option, Result, OkResult, ErrorResult;

export 'src/bindings.g.dart'
    hide definePlugin, PluginExports, Metadata, PluginMetadata,
        // Constants named after WIT interfaces (`context`, `server`, `world`,
        // ...) that would clash with everyday variable names.
        context, server, player, world, entity, event, command, text, error,
        types, streams, poll, common,
        // Our binding-free `ConnectionFlavour` (configuration_core.dart).
        ConnectionFlavour,
        // The generated interface class of `text` (the `Text` builder is ours).
        Text,
        // The raw `item-registry` interface; use `ItemRegistries.host`.
        ItemDefinition, ItemEntry, ItemRegistry, itemRegistry,
        // The raw `block-registry` interface; use `BlockRegistries.host`.
        BlockBox, BlockDefinition, BlockDrops, BlockDropsNothing, BlockDropsLootTable, BlockDropsSelfItem, BlockEntry, BlockProperty, BlockRegistry, BlockShape, BlockShapeBoxes, BlockShapeEmpty, BlockShapeFullCube, ConnectDirection, ConnectRule, ConnectTarget, ConnectTargetBlock, ConnectTargetSameBlock, ConnectTargetTag, IntBounds, PropertyKind, PropertyKindBoolean, PropertyKindEnumeration, PropertyKindIntRange, PropertyValue, blockRegistry,
        // The raw `block-placement`, `plugin-block-entity`, `menus` and `custom-components`
        // interfaces; use `BlockPlacements.host`, `BlockEntityRegistries.host` and the
        // `PluginBlockEntities`, `PluginMenus` and `CustomItemComponents` extensions.
        BlockPlacement, blockPlacement, PlacementRule, PlacementSource, PlacementSourceHorizontalFacing, PlacementSourceLookingDirection, PlacementSourceClickedFace, PlacementSourceClickedAxis, PlacementSourceClickedHalf, PlacementSourceVerticalLook, PlacementSourceInWater, PlacementSourceSneaking, PlacementSourceConstant,
        PluginBlockEntity, pluginBlockEntity, PluginBlockEntityData, BlockEntityTypeEntry,
        Menus, menus, MenuTypeEntry, OpenMenuInfo,
        CustomComponents, customComponents, ComponentTypeEntry, CodecOp, CodecOpVarInt, CodecOpVarLong, CodecOpFlag, CodecOpByte, CodecOpShort, CodecOpInt, CodecOpLong, CodecOpFloat32, CodecOpFloat64, CodecOpText, CodecOpByteArray, CodecOpUuid, CodecOpFixedBytes, CodecOpNbt, CodecOpStack, CodecOpComponentPatch, CodecOpOptional, CodecOpRepeated, CodecOpSequence,
        // The raw WASI filesystem types, used through `DataFolder`.
        Advice, Datetime, Descriptor, DescriptorFlagsFlag, DescriptorStat, DescriptorType, DirectoryEntry, DirectoryEntryStream, Error, ErrorCode, ErrorInterface, InputStream, MetadataHashValue, NewTimestamp, NewTimestampNoChange, NewTimestampNow, NewTimestampTimestamp, OpenFlagsFlag, OutputStream, PathFlagsFlag, Poll, Pollable, Preopens, StreamError, StreamErrorClosed, StreamErrorLastOperationFailed, Streams, Types, WallClock, preopens, wallClock;
export 'src/ai.dart' hide aiGoals;
export 'src/blocks.dart';
export 'src/items.dart';
export 'src/item_registry.dart';
export 'src/item_registry_core.dart';
export 'src/block_registry.dart';
export 'src/block_registry_core.dart';
export 'src/block_placement.dart';
export 'src/block_placement_core.dart';
export 'src/component_codec.dart';
export 'src/nbt_compound.dart';
export 'src/plugin_registries.dart';
export 'src/plugin_registry_core.dart';
export 'src/data_component_codec.dart';
export 'src/registry_ids.dart';
export 'src/inventory.dart';
export 'src/datapacks.dart';
export 'src/game_rules.dart';
export 'src/forms.dart';
export 'src/enchantments.dart';
export 'src/recipes.dart';
export 'src/teams.dart';
export 'src/persistent_data.dart';
export 'src/advancements.dart';
export 'src/attributes.dart';
export 'src/display.dart';
export 'src/player_ext.dart';
export 'src/server_list_ping.dart';
export 'src/uuid_ext.dart';
export 'src/commands.dart' hide commandErrorFor, commandHandlers, suggestionHandlers;
export 'src/command_builder.dart' hide commandNamespace;
export 'src/command_context.dart';
export 'src/command_help.dart';
export 'src/events.dart' hide eventHandlers;
export 'src/messages.dart';
export 'src/feedback.dart';
export 'src/bossbars.dart';
export 'src/scoreboards.dart';
export 'src/menus.dart';
export 'src/item_builder.dart';
export 'src/data_keys.dart';
export 'src/data_keys_bindings.dart';

export 'src/lifecycle.dart';
export 'src/ipc.dart';
export 'src/channels.dart';
export 'src/packet_buffer.dart';
export 'src/configuration.dart';
export 'src/configuration_core.dart'
    show
        ConfigurationConnection,
        ConfigurationStage,
        ConnectionFlavour,
        ConfigurationException,
        ConfigurationHandler,
        ConnectionClosedException,
        LoginConnection,
        LoginHandler,
        PhaseConnection;
export 'src/permission_nodes.dart';

export 'src/geometry.dart';
export 'src/location.dart';
export 'src/spatial.dart';
export 'src/player_helpers.dart';

export 'src/files.dart';
export 'src/events.g.dart';
export 'src/logger.dart';
export 'src/permissions.dart';
export 'src/plugin.dart' show Plugin, PluginInfo, runPlugin;
export 'src/scheduler.dart';
export 'src/worldgen.dart' hide chunkGenerators;
