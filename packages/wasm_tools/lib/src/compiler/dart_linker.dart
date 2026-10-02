import 'program_abi.dart';

import 'components/component.dart';
import 'components/index_space.dart';
import 'components/linker.dart';

final class DartLinker {
  final DartProgramAbi abi;
  final ModuleInstanceIndex libc;
  final ComponentBuilder builder;

  CoreMemoryIndex? _libcMemory;
  CoreFunctionIndex? _libcRealloc;

  DartLinker(this.builder, this.abi, this.libc) {
    var needsMemory = false;
    var needsRealloc = false;

    // A `realloc` is required whenever strings or lists cross the boundary
    // (the receiving side has to allocate), even if the ABI didn't set the
    // explicit `needs_realloc` flag (it isn't emitted for world-level export
    // hooks).
    bool optionsNeedRealloc(FunctionOptions o) =>
        o.needsRealloc || o.usesStrings;

    for (final import
        in abi.functionImports.values.whereType<ImportedInstanceFunction>()) {
      if (import.options.usesMemory) {
        needsMemory = true;
      }
      if (optionsNeedRealloc(import.options)) {
        needsRealloc = true;
      }
    }

    for (final export in abi.functionExports.values) {
      if (export.options.usesMemory) {
        needsMemory = true;
      }
      if (optionsNeedRealloc(export.options)) {
        needsRealloc = true;
      }
    }

    if (needsMemory) {
      _libcMemory = builder.linker.alias(
        .coreMemory,
        .coreInstanceExport(libc, 'memory'),
      );
    }

    if (needsRealloc) {
      _libcRealloc = builder.linker.alias(
        .coreFunction,
        .coreInstanceExport(libc, 'dart_realloc'),
      );
    }
  }

  /// Lowers every called import function into a core function and gathers them
  /// (plus canonical primitives) into a single core instance that the app
  /// module imports as `component`.
  ///
  /// [instances] maps each imported interface to the component instance it
  /// was imported as (built by the assembler in dependency order).
  ModuleInstanceIndex createCoreImportInstance(
    Map<ResolvedInterface, ComponentInstanceIndex> instances,
  ) {
    final importedInterfaces = abi.interfaces
        .where((e) => e.importedFunctions.isNotEmpty)
        .toList();

    // First all aliases, then all lowerings, so consecutive definitions share
    // one section each.
    final functionAliases = [
      for (final interface in importedInterfaces)
        for (final function in interface.importedFunctions)
          builder.linker.alias(
            .componentFunction,
            .instanceExport(
              instances[interface]!,
              function.interfaceMethod,
            ),
          ),
    ];

    final lowered =
        <
          ImportedInstanceFunctionOrCanon,
          CanonDefinitionCreatingCoreFunction
        >{};
    var i = 0;
    for (final interface in importedInterfaces) {
      for (final function in interface.importedFunctions) {
        final lower = lowered[function] = builder.linker.canonLower(
          functionAliases[i++],
        );
        applyOptions(function.options, lower);
      }
    }

    for (final primitive
        in abi.functionImports.values.whereType<ImportedCanonPrimitive>()) {
      lowered[primitive] = primitive.resolve(this);
    }

    final inlineExports = <(String, Sort, Index)>[];
    for (final MapEntry(:key, :value) in abi.functionImports.entries) {
      inlineExports.add((
        key,
        .coreFunction,
        lowered[value]!.createdCoreFunction,
      ));
    }

    return builder.linker.coreInstantiate(.inlineExports(inlineExports));
  }

  void applyOptions(FunctionOptions options, CanonicalHasOptions canon) {
    if (options.usesMemory) {
      canon.memory = _libcMemory!;
    }
    if (options.needsRealloc || options.usesStrings) {
      canon.realloc = _libcRealloc;
    }
    if (options.usesStrings) canon.stringEncoding = .utf16;
  }
}
