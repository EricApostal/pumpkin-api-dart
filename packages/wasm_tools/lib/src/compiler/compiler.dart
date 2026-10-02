import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'component_assembler.dart';
import 'components/component.dart';
import 'components/index_space.dart';
import 'components/linker.dart';
import 'dart_linker.dart';
import 'hooks/builder.dart';
import 'transform.dart';

final class CompilerOptions {
  final File input;
  final File output;
  final bool hooksIncludeDevDependencies;

  CompilerOptions(
    this.input,
    this.output, {
    this.hooksIncludeDevDependencies = false,
  });
}

final class ComponentCompiler {
  final CompilerOptions options;
  final Logger logger;

  ComponentCompiler(this.options, this.logger);

  Future<void> run() async {
    final workspace = await Directory.systemTemp.createTemp('dart-wasm-cm');
    final dart2wasmOut = p.join(workspace.path, 'app.dart2.wasm');

    try {
      logger.fine('Invoking build hooks to infer ABI');
      final resolved = await PackageConfigWithAbi.resolveProgramAbi(
        mainFile: options.input,
        logger: logger,
        includeDevDependencies: options.hooksIncludeDevDependencies,
      );
      if (resolved == null) {
        throw CompilerFailure('Could not resolve components');
      }
      final abi = resolved.abi;

      logger.fine('Building main application');
      final binDir = p.dirname(Platform.resolvedExecutable);
      final sdkDir = p.dirname(binDir);
      final dartAotRuntime = p.join(
        binDir,
        Platform.isWindows ? 'dartaotruntime.exe' : 'dartaotruntime',
      );
      final snapshot = p.join(
        binDir,
        'snapshots',
        'dart2wasm_product.snapshot',
      );
      final librariesSpec = p.join(sdkDir, 'lib', 'libraries.json');

      var result = await (await Process.start(dartAotRuntime, [
        snapshot,
        '--libraries-spec',
        librariesSpec,
        '--packages',
        resolved.packageConfigFile,
        '--standalone',
        '--enable-experimental-wasm-interop',
        '--no-minify',
        '--no-strip-wasm',
        '-O0',
        options.input.path,
        dart2wasmOut,
      ], mode: .inheritStdio)).exitCode;
      if (result != 0) {
        throw CompilerFailure('dart2wasm failed: $result');
      }

      final transformer = ModuleTransformer.fromBytes(
        await File(dart2wasmOut).readAsBytes(),
        logger,
      );
      transformer.transform(abi);

      final builder = ComponentBuilder();
      final libcDef = builder.defineModuleFromBytes(
        await (await resolved.resolveRuntimeHelpersFile()).readAsBytes(),
      );
      final libc = builder.linker.coreInstantiate(.moduleAndArgs(libcDef, {}));

      final appDef = builder.defineModule(transformer.module);
      final linker = DartLinker(builder, abi, libc);

      // Encode and import all interfaces the plugin references, in dependency
      // order, then resolve export signatures against them.
      final assembler = ComponentAssembler(builder, abi);
      assembler.buildImports();
      assembler.resolveExportTypes();

      final app = builder.linker.coreInstantiate(
        .moduleAndArgs(appDef, {
          'libc': libc,
          'component': linker.createCoreImportInstance(assembler.instances),
        }),
      );

      final callback = abi.hasAsyncExport
          ? builder.linker.alias(
              .coreFunction,
              .coreInstanceExport(app, 'callback'),
            )
          : null;

      // IMPORTANT: create every canonical lift (and exported instance) first,
      // and only then emit the component exports. Exporting a function pushes
      // it onto the component function index space, so interleaving an export
      // between two lifts would shift the indices that later exports resolve
      // against -- causing each export to pick up the *previous* function's
      // type. Deferring all exports keeps `function_at(export.index)` stable.
      final pendingExports = <Export>[];

      for (final export in abi.interfaces) {
        if (export.exports.isEmpty) continue;

        final inlineExports = <(String, Sort, Index)>[];

        // Export the interface's own named types so its functions' anonymous
        // record/variant/etc. results become named within the instance (the
        // component model requires that for exported interfaces).
        for (final (name, typeIndex) in assembler.namedTypeExportsFor(export)) {
          inlineExports.add((name, .componentType, typeIndex));
        }

        for (final function in export.exports) {
          final resolved = builder.linker.alias(
            .coreFunction,
            .coreInstanceExport(app, function.exportCoreFunctionName),
          );
          CoreFunctionIndex? corePostReturnFunction;
          if (function.options.postReturn case final postReturn?) {
            corePostReturnFunction = builder.linker.alias(
              .coreFunction,
              .coreInstanceExport(app, postReturn),
            );
          }

          final originalType = function.type!;
          final lifted = builder.linker.canonLift(
            resolved,
            builder.types.addFunctionType(originalType),
          );
          linker.applyOptions(function.options, lifted);
          lifted.postReturn = corePostReturnFunction;
          if (function.options.usesCallback) {
            lifted.callback = callback!;
            lifted.async = true;
          }

          inlineExports.add((
            function.name,
            .componentFunction,
            lifted.createdFunction,
          ));
        }

        final instance = builder.linker.instance(inlineExports: inlineExports);
        pendingExports.add(
          Export(export.fullName, .componentInstance, instance),
        );
      }

      // Functions exported directly from the world (`export foo: func(...)`)
      // become standalone component function exports, unlike the interface
      // case above which groups functions into an exported instance.
      for (final function in abi.bareExports) {
        final resolved = builder.linker.alias(
          .coreFunction,
          .coreInstanceExport(app, function.exportCoreFunctionName),
        );
        CoreFunctionIndex? corePostReturnFunction;
        if (function.options.postReturn case final postReturn?) {
          corePostReturnFunction = builder.linker.alias(
            .coreFunction,
            .coreInstanceExport(app, postReturn),
          );
        }

        final lifted = builder.linker.canonLift(
          resolved,
          assembler.bareExportFunctionType(function.rawJson),
        );
        linker.applyOptions(function.options, lifted);
        lifted.postReturn = corePostReturnFunction;
        if (function.options.usesCallback) {
          lifted.callback = callback!;
          lifted.async = true;
        }

        pendingExports.add(
          Export(function.name, .componentFunction, lifted.createdFunction),
        );
      }

      // Export any world-owned named types (e.g. the `event` variant) the
      // hooks referenced, so they are named at the component root.
      for (final (name, typeIndex) in assembler.rootTypeExports) {
        pendingExports.add(Export(name, .componentType, typeIndex));
      }

      for (final export in pendingExports) {
        builder.linker.export(export);
      }

      logger.info('Writing component to ${options.output.path}');
      await options.output.writeAsBytes(builder.serializeToBytes());
    } finally {
      await workspace.delete(recursive: true);
    }
  }
}

final class CompilerFailure implements Exception {
  final String message;

  CompilerFailure(this.message);

  @override
  String toString() {
    return 'Compiler failure: $message';
  }
}
