import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file/local.dart';
import 'package:hooks_runner/hooks_runner.dart';
import 'package:logging/logging.dart';
import 'package:package_config/package_config.dart';

import '../../failure.dart';
import '../program_abi.dart';
import 'extension.dart';
import 'extension.dart' as hooks;

final class PackageConfigWithAbi {
  final String packageConfigFile;
  final PackageConfig packageConfig;
  final DartProgramAbi abi;

  /// Core modules declared by build hooks, linked next to the Dart module.
  final List<CoreModuleInput> coreModules;

  PackageConfigWithAbi({
    required this.packageConfigFile,
    required this.packageConfig,
    required this.abi,
    this.coreModules = const [],
  });

  /// Resolves the file containing pre-compiled WebAssembly helpers used to
  /// implement component interop.
  ///
  /// This file is stored in `assets/runtime_helpers.wasm` of the `wasm_tools`
  /// package, which we locate through the package config.
  Future<File> resolveRuntimeHelpersFile() async {
    final entry = packageConfig.packages.firstWhereOrNull(
      (p) => p.name == 'wasm_tools',
    );
    if (entry == null) {
      throw ToolFailure('No dependency on wasm_tools found.');
    }

    final file = File.fromUri(
      entry.root.resolve('assets/runtime_helpers.wasm'),
    );
    if (!await file.exists()) {
      throw ToolFailure('Internal error, expected ${file.path} to exist');
    }
    return file;
  }

  static Future<PackageConfigWithAbi?> resolveProgramAbi({
    required File mainFile,
    required Logger logger,
    bool includeDevDependencies = false,
  }) async {
    final mainUri = mainFile.absolute.uri;
    final pkgConfig = await findPackageConfigAndUri(mainUri);
    final mainPackage = pkgConfig?.config.packageOf(mainUri);
    if (pkgConfig == null || mainPackage == null) {
      logger.shout('No package config was found for ${mainFile.path}');
      return null;
    }

    const fs = LocalFileSystem();

    final buildRunner = NativeAssetsBuildRunner(
      logger: logger,
      dartExecutable: File(Platform.resolvedExecutable).uri,
      fileSystem: fs,
      packageLayout: PackageLayout.fromPackageConfig(
        fs,
        pkgConfig.config,
        pkgConfig.file,
        mainPackage.name,
        includeDevDependencies: includeDevDependencies,
      ),
    );

    final buildResult = await buildRunner.build(
      extensions: [WasmComponentExtension()],
      linkingEnabled: false,
    );
    if (buildResult.isFailure) {
      final error = buildResult.asFailure.value;
      logger.shout('Invoking build hooks failed: ${error.name}');
      return null;
    }

    final abi = DartProgramAbi();
    final coreModules = <CoreModuleInput>[];
    final assets = buildResult.asSuccess.value.encodedAssets;
    for (final asset in assets) {
      if (asset.type == hooks.name) {
        abi.includeAsset(logger, asset);
      } else if (asset.type == hooks.coreModuleName) {
        coreModules.add(
          CoreModuleInput(
            asset.encoding['name'] as String,
            File(asset.encoding['file'] as String),
          ),
        );
      }
    }

    return PackageConfigWithAbi(
      packageConfig: pkgConfig.config,
      packageConfigFile: pkgConfig.file.toFilePath(),
      abi: abi,
      coreModules: coreModules,
    );
  }
}

final class CoreModuleInput {
  final String name;
  final File file;

  CoreModuleInput(this.name, this.file);
}
