import 'content/content_module.dart';
import 'core/module.dart';
import 'infrastructure/infrastructure_module.dart';
import 'kinetics/kinetics_module.dart';
import 'logistics/logistics_module.dart';
import 'decoration/decoration_module.dart';
import 'equipment/equipment_module.dart';
import 'modules/datapack_module.dart';
import 'processing/processing_module.dart';
import 'schematics/schematics_module.dart';
import 'protocol/protocol_module.dart';
import 'redstone/redstone_module.dart';
import 'smoke/smoke_module.dart';

/// The modules of the mod, in load order. Registration order (and so the default
/// ids) follows this list. One line per module; add yours where the commented
/// slot is.
final List<CreateModule> allModules = [
  ProtocolModule(), // payload bus: all 119 channels, PayloadBus service (must load first)
  InfrastructureModule(), // configs (AllConfigs service), /create commands, catnip config payloads, ores, server speed
  ContentModule(), // damage types, enchantments, sounds, particles, components, tags, advancements; services
  SmokeTestModule(), // framework smoke test, active with core.debug_smoke_test
  KineticsModule(), // kinetic network: shafts, cogwheels, gearboxes, motors, gauges, water wheels, ...
  ProcessingModule(), // processing machines: crusher, press, mixer, basin, saw, fan, crafter, deployer, arm, ...; recipes
  LogisticsModule(), // packages and stock: packager, ports, stock ticker, factory gauge, table cloth, filters
  // FluidsModule(),
  // ContraptionsModule(),
  // TrainsModule(),
  RedstoneModule(), // redstone links, controllers, diodes, display links, nixie tubes, observers, ...
  EquipmentModule(), // wrench, zapper, symmetry wand, potato cannon, armor, toolbox, bells, blueprint, clipboard
  DecorationModule(),
  SchematicsModule(), // schematic table, schematicannon, uploads, schematic API hooks
  // WorldgenModule(),
  // ContentModule(),
  DatapackModule(), // ships the data pack (recipes, loot tables, advancements, tags)
];
