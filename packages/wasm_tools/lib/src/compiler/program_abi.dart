import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

import 'components/linker.dart';
import 'components/type.dart';
import 'dart_linker.dart';

/// Information about all component imports and exports used in the Dart
/// program being compiled.
///
/// We collect this information through build hooks.
final class DartProgramAbi {
  final Map<String, ResolvedInterface> _interfaces = {};

  final Map<String, ImportedInstanceFunctionOrCanon> functionImports = {};
  final Map<String, ExportedInstanceFunction> functionExports = {};

  /// Functions exported directly from the world (`export foo: func(...)`),
  /// as opposed to grouped into an interface instance. Unlike
  /// [ResolvedInterface.exports], these become standalone component
  /// function exports rather than members of an exported instance.
  final List<ExportedInstanceFunction> bareExports = [];

  /// The raw `type_defs` array from the encoded ABI, shared by all
  /// interfaces. Used by the assembler to encode instance/component types.
  List<Map<String, Object?>> rawTypeDefs = const [];

  /// Interfaces indexed by their position in the ABI's `interfaces` array.
  final List<ResolvedInterface> interfacesByIndex = [];

  Iterable<ResolvedInterface> get interfaces => _interfaces.values;

  Iterable<String> get expectedExportedFunctions sync* {
    for (final export in functionExports.values) {
      yield export.exportCoreFunctionName;
      if (export.options.postReturn case final postReturn?) {
        yield postReturn;
      }
    }
  }

  bool get hasAsyncExport {
    return functionExports.values.any((e) => e.options.usesCallback);
  }

  ResolvedInterface lookupOrAddInterface(
    String name,
    ResolvedInterface Function() create,
  ) {
    return _interfaces.putIfAbsent(name, create);
  }

  /// Drops imported functions whose core `component.*` import isn't actually
  /// present in the compiled module (i.e. the Dart code never called them).
  ///
  /// The ABI, built from the full WIT world, advertises every importable
  /// function of every interface, but `dart2wasm` only emits a core import
  /// for functions actually used. Keeping the unused ones would force the
  /// component to import (and declare instance types for) interfaces the
  /// plugin doesn't touch -- pure bloat, and it drags in cross-interface type
  /// dependencies that would otherwise never be needed.
  void removeUnusedImports(Set<String> unusedCoreImports) {
    if (unusedCoreImports.isEmpty) return;
    for (final coreImport in unusedCoreImports) {
      functionImports.remove(coreImport);
    }
    for (final interface in _interfaces.values) {
      interface.importedFunctions.removeWhere(
        (f) => unusedCoreImports.contains(f.coreImport),
      );
    }
  }

  void includeAsset(Logger logger, EncodedAsset asset) {
    final encoding = asset.encoding;
    rawTypeDefs = (encoding['type_defs'] as List).cast<Map<String, Object?>>();
    final interfaces = <ResolvedInterface>[];

    for (final (index, entry)
        in (encoding['interfaces'] as List)
            .cast<Map<String, Object?>>()
            .indexed) {
      final fullName = entry['full_name'] as String;
      final resolved = lookupOrAddInterface(
        fullName,
        () => ResolvedInterface(
          fullName,
          index,
          entry['exported_functions'] as Map<String, Object?>,
        ),
      );
      interfaces.add(resolved);
    }
    interfacesByIndex
      ..clear()
      ..addAll(interfaces);

    final imports = (encoding['imports'] as List).cast<Map<String, Object?>>();
    for (final rawImport in imports) {
      final interface = interfaces[rawImport['interface_id'] as int];

      final functionName = rawImport['function_name'] as String;
      final coreFunctionName = rawImport['core_name'] as String;
      final options = FunctionOptions.fromJson(
        rawImport['options'] as Map<String, Object?>,
      );
      final instanceFunction = ImportedInstanceFunction(
        functionName,
        coreFunctionName,
        options,
      );
      interface.importedFunctions.add(instanceFunction);
      functionImports[coreFunctionName] = instanceFunction;
    }

    for (final rawDrop
        in (encoding['resource_drops'] as List? ?? const [])
            .cast<Map<String, Object?>>()) {
      final coreName = rawDrop['core_name'] as String;
      functionImports[coreName] = ImportedResourceDrop(
        coreName,
        rawDrop['type_id'] as int,
      );
    }

    final exports = (encoding['exports'] as List).cast<Map<String, Object?>>();
    for (final rawExport in exports) {
      final interface = interfaces[rawExport['interface_id'] as int];
      final functionName = rawExport['function_name'] as String;
      final coreName = rawExport['core_export_name'] as String;
      final options = FunctionOptions.fromJson(
        rawExport['options'] as Map<String, Object?>,
      );

      final export = ExportedInstanceFunction(
        coreName,
        functionName,
        options,
        interface.rawExportedFunctions[functionName] as Map<String, Object?>,
        interface.index,
      );
      functionExports[coreName] = export;
      interface.exports.add(export);

      if (options.returnImport case final returnImport?) {
        functionImports[returnImport] = ImportedCanonPrimitive(returnImport, (
          linker,
        ) {
          final taskReturn = linker.builder.linker.addCanonPrimitive((idx) {
            final originalResultType = export.type!.result;
            ValueTypeReference? result;
            if (originalResultType != null) {
              result = linker.builder.types.addValueType(originalResultType);
            }

            return TaskReturn(idx, result);
          });
          linker.applyOptions(options, taskReturn);

          return taskReturn;
        });
      }
    }

    final bareExports = (encoding['bare_exports'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    for (final rawExport in bareExports) {
      final functionName = rawExport['function_name'] as String;
      final coreName = rawExport['core_export_name'] as String;
      final options = FunctionOptions.fromJson(
        rawExport['options'] as Map<String, Object?>,
      );

      final export = ExportedInstanceFunction(
        coreName,
        functionName,
        options,
        rawExport,
        null,
      );
      functionExports[coreName] = export;
      this.bareExports.add(export);

      if (options.returnImport case final returnImport?) {
        functionImports[returnImport] = ImportedCanonPrimitive(returnImport, (
          linker,
        ) {
          final taskReturn = linker.builder.linker.addCanonPrimitive((idx) {
            final originalResultType = export.type!.result;
            ValueTypeReference? result;
            if (originalResultType != null) {
              result = linker.builder.types.addValueType(originalResultType);
            }

            return TaskReturn(idx, result);
          });
          linker.applyOptions(options, taskReturn);

          return taskReturn;
        });
      }
    }
  }
}

final class FunctionOptions {
  final bool usesMemory;
  final bool usesStrings;
  final bool needsRealloc;
  final bool usesCallback;
  final String? postReturn;
  final String? returnImport;

  FunctionOptions({
    required this.usesMemory,
    required this.usesStrings,
    this.needsRealloc = false,
    this.usesCallback = false,
    this.postReturn,
    this.returnImport,
  });

  factory FunctionOptions.fromJson(Map<String, Object?> json) {
    return FunctionOptions(
      usesMemory: json['use_memory'] as bool,
      usesStrings: json['uses_strings'] as bool,
      needsRealloc: json['needs_realloc'] as bool? ?? false,
      usesCallback: json['uses_callback'] as bool? ?? false,
      postReturn: json['post_return'] as String?,
      returnImport: json['task_return_import'] as String?,
    );
  }
}

final class ImportedInstanceFunctionOrCanon {
  final String coreImport;

  new(this.coreImport);
}

final class ImportedInstanceFunction extends ImportedInstanceFunctionOrCanon {
  final String interfaceMethod;
  final FunctionOptions options;

  new(this.interfaceMethod, super.coreImport, this.options);
}

final class ImportedCanonPrimitive extends ImportedInstanceFunctionOrCanon {
  CanonPrimitive Function(DartLinker) resolve;

  new(super.coreImport, this.resolve);
}

/// A `resource.drop` for the resource at `type_defs[typeId]`.
final class ImportedResourceDrop extends ImportedInstanceFunctionOrCanon {
  final int typeId;

  new(super.coreImport, this.typeId);
}

final class ExportedInstanceFunction {
  final String exportCoreFunctionName;
  final String name;
  final FunctionOptions options;

  /// Raw ABI JSON describing the function's signature (`params`/`result`/
  /// `kind`). The component-level [FunctionType] is resolved lazily by the
  /// assembler (so its referenced types can be aliased from imports).
  final Map<String, Object?> rawJson;

  /// The owning interface index for an interface export, or `null` for a
  /// world-level (bare) export.
  final int? interfaceIndex;

  /// Set by the assembler once instance types have been built.
  FunctionType? type;

  ExportedInstanceFunction(
    this.exportCoreFunctionName,
    this.name,
    this.options,
    this.rawJson,
    this.interfaceIndex,
  );
}

final class ResolvedInterface {
  final String fullName;

  /// Index of this interface within the ABI's `interfaces` array.
  final int index;

  /// Raw ABI JSON for this interface's `exported_functions`.
  final Map<String, Object?> rawExportedFunctions;

  final List<ImportedInstanceFunction> importedFunctions = [];
  final List<ExportedInstanceFunction> exports = [];

  /// The encoded component instance type. For ABI-derived interfaces this is
  /// set by the assembler; synthetic interfaces (e.g. `wasi:random`, built by
  /// the module transformer) pre-supply it and use [index] `-1`.
  InstanceType? type;

  ResolvedInterface(
    this.fullName,
    this.index,
    this.rawExportedFunctions, {
    this.type,
  });

  /// Whether this interface was synthesized outside the ABI's `type_defs`
  /// (and so already carries a fully-built [type]).
  bool get isSynthetic => index < 0;
}
