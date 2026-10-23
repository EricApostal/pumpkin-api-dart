// The shared state of the processing module: the recipe book, tag lookup, random source and
// the services the machines use. One instance per plugin load; machines (block entities
// are created by the framework and cannot take constructor arguments) reach it through
// [ProcessingRuntime.instance], like the kinetic block entities reach `KineticsRuntime`.
import 'dart:math';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/advancements.dart' show CreateAdvancements;
import '../api/config.dart' as cfg;
import '../core/block_entity.dart';
import '../core/services.dart';
import '../core/worlds.dart';
import 'host/storage_lookup.dart';
import 'host/tags_host.dart';
import 'processing_settings.dart';
import 'recipe/recipe_book.dart';

final class ProcessingRuntime {
  static ProcessingRuntime? _instance;

  /// The runtime; available after the module's `onLoad`.
  static ProcessingRuntime get instance => _instance ?? (throw StateError('The processing module is not loaded'));
  static bool get isLoaded => _instance != null;

  final ProcessingSettings settings;
  final RecipeBook recipes;
  final HostTagLookup tags;
  final BlockEntityStore store;
  final Worlds worlds;
  final Logger log;
  final CreateServices services;
  final StorageLookup storage;

  /// The random source of the machines (`level.getRandom()`).
  final Random random = Random();

  ProcessingRuntime({
    required this.settings,
    required this.recipes,
    required this.tags,
    required this.store,
    required this.worlds,
    required this.log,
    required this.services,
  }) : storage = StorageLookup(store) {
    _instance = this;
  }

  /// The live config of the infrastructure module (`AllConfigs`), when loaded.
  cfg.CreateConfigs? get configs => services.find<cfg.CreateConfigs>();

  /// The content module's advancement service (`SmartBlockEntity.award` -> `AdvancementBehaviour`).
  CreateAdvancements? get advancements => services.find<CreateAdvancements>();

  void dispose() {
    if (identical(_instance, this)) _instance = null;
  }
}
