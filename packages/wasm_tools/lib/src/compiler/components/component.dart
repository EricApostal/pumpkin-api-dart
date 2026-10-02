import 'dart:typed_data';

import '../../third_party/wasm_builder/wasm_builder.dart' as w;

import 'binary.dart';
import 'core_module.dart';
import 'index_space.dart';
import 'linker.dart';
import 'type.dart';
import 'type_container.dart';

/// Utilities to build a WebAssembly component.
///
/// Since we only generate components (and don't transform / inspect existing
/// ones), we can get away with only supporting the supset of the full component
/// model we really need.
///
/// In our case, components unconditionally have the following shape:
///
///  1. Define core modules (the Rust helper and the dart2wasm-compiled app).
///  2. Define all (component-level) types.
///  3. Import used component instances.
///  4. Create a `(core instance)` of the Rust helper.
///  5. Create `(alias export)` and `(canon lower)` definitions to turn builtins
///     and imported definitions into core modules.
///  6. Create a `(core instance)` exporting those imports.
///  7. Create a `(core instance)` of the dart2wasm app.
///  8. Create a `(instance)` with inlineexports.
///  9. Export that instance.
/// One entry in the component's interleaved top-level declaration stream.
///
/// Type definitions, instance imports, and type aliases share index spaces
/// and must be emitted in dependency order (an instance import references a
/// previously-defined instance *type*; a type alias projects a type out of a
/// previously-imported *instance*; and a later instance type may reference an
/// aliased type). Keeping them in one ordered list preserves that ordering
/// and lets [ComponentBuilder.serialize] group runs of the same kind into
/// sections.
sealed class _TopLevelDecl {}

final class _DefineType extends _TopLevelDecl {
  final ModelType type;
  _DefineType(this.type);
}

final class _ImportInstance extends _TopLevelDecl {
  final String name;
  final ComponentTypeIndex type;
  final String? implements;
  _ImportInstance(this.name, this.type, this.implements);
}

final class _AliasTypeExport extends _TopLevelDecl {
  final ComponentInstanceIndex instance;
  final String name;
  _AliasTypeExport(this.instance, this.name);
}

final class ComponentBuilder implements w.Serializable {
  final List<CoreModule> _modules = [];

  final List<_TopLevelDecl> _decls = [];
  int _typeCount = 0;

  late final TypesContainer types = TypesContainer.allocated(defineType);

  final IndexSpaceCounters _counters = IndexSpaceCounters();

  /// Deduplicates `(instance, type-name)` type-export aliases so a foreign
  /// type projected out of an imported instance is only aliased once.
  final Map<(int, String), ComponentTypeIndex> _aliasCache = {};

  late final LinkingBuilder linker = LinkingBuilder(this);

  CoreModule _defineCoreModule(CoreModule Function(ModuleIndex) create) {
    final index = ModuleIndex(_modules.length);
    final module = create(index);
    _modules.add(module);
    return module;
  }

  CoreModule defineModuleFromBytes(Uint8List bytes) {
    return _defineCoreModule((idx) => CoreModuleFromBytes(idx, bytes));
  }

  CoreModule defineModule(w.Module module) {
    return _defineCoreModule((idx) => CoreModuleParsed(idx, module));
  }

  /// Appends a type definition to the component's type index space.
  ComponentTypeIndex defineType(ModelType type) {
    final idx = ComponentTypeIndex(_typeCount++);
    _decls.add(_DefineType(type));
    return idx;
  }

  ComponentInstanceIndex importInstance(
    String name,
    ModelTypeReference<InstanceType> type, {
    String? implements,
  }) {
    return importInstanceByType(name, type.index, implements: implements);
  }

  /// Imports an instance whose type is the already-defined component type
  /// [type].
  ComponentInstanceIndex importInstanceByType(
    String name,
    ComponentTypeIndex type, {
    String? implements,
  }) {
    final idx = _counters.incrementComponentInstance();
    _decls.add(_ImportInstance(name, type, implements));
    return idx;
  }

  /// Projects the type named [name] out of the previously-imported [instance]
  /// into the component's type index space (an `alias export` of the
  /// instance's type export), returning the new component type index.
  /// Deduplicated.
  ComponentTypeIndex aliasInstanceTypeExport(
    ComponentInstanceIndex instance,
    String name,
  ) {
    return _aliasCache.putIfAbsent((instance.index, name), () {
      final idx = ComponentTypeIndex(_typeCount++);
      _decls.add(_AliasTypeExport(instance, name));
      return idx;
    });
  }

  @override
  void serialize(w.Serializer s) {
    s.writeBytes(_preamble);
    for (final module in _modules) {
      ModuleSection(module).serialize(s);
    }
    _serializeDecls(s);
    linker.serialize(s);
  }

  /// Serializes [_decls] in order, coalescing consecutive declarations of the
  /// same kind into a single section.
  void _serializeDecls(w.Serializer s) {
    var i = 0;
    while (i < _decls.length) {
      final decl = _decls[i];
      switch (decl) {
        case _DefineType():
          final types = <ModelType>[];
          while (i < _decls.length && _decls[i] is _DefineType) {
            types.add((_decls[i] as _DefineType).type);
            i++;
          }
          TypesSection(types).serialize(s);
        case _ImportInstance():
          final imports = <_ImportInstance>[];
          while (i < _decls.length && _decls[i] is _ImportInstance) {
            imports.add(_decls[i] as _ImportInstance);
            i++;
          }
          ImportsSection([
            for (final imp in imports) (imp.name, imp.type, imp.implements),
          ]).serialize(s);
        case _AliasTypeExport():
          final aliases = <_AliasTypeExport>[];
          while (i < _decls.length && _decls[i] is _AliasTypeExport) {
            aliases.add(_decls[i] as _AliasTypeExport);
            i++;
          }
          TypeAliasSection([
            for (final a in aliases) (a.instance, a.name),
          ]).serialize(s);
      }
    }
  }

  Uint8List serializeToBytes() {
    final serializer = w.Serializer();
    serialize(serializer);
    return serializer.data;
  }

  static final _preamble = Uint8List.fromList([
    0x00,
    0x61,
    0x73,
    0x6d,
    0x0d,
    0x00,
    0x01,
    0x00,
  ]);
}

final class LinkingBuilder implements w.Serializable {
  final ComponentBuilder _component;
  final List<LinkingInstruction> _instructions = [];

  LinkingBuilder(this._component);

  I alias<I extends Index>(Sort<I> sort, AliasTarget target) {
    final index = _component._counters.increment(sort);
    _instructions.add(AliasDefinition(sort, index, target));
    return index;
  }

  CanonLower canonLower(ComponentFunctionIndex function) {
    final index = _component._counters.incrementCoreFunction();
    final def = CanonLower(function, index);
    _instructions.add(def);
    return def;
  }

  CanonLift canonLift(CoreFunctionIndex function, FunctionTypeReference type) {
    final index = _component._counters.incrementComponentFunction();
    final def = CanonLift(function, type, index);
    _instructions.add(def);
    return def;
  }

  T addCanonPrimitive<T extends CanonPrimitive>(
    T Function(CoreFunctionIndex index) create,
  ) {
    final index = _component._counters.incrementCoreFunction();
    final def = create(index);
    _instructions.add(def);
    return def;
  }

  CanonContextGet canonContextGet(int i) {
    return addCanonPrimitive((index) => CanonContextGet(index, i));
  }

  CanonContextSet canonContextSet(int i) {
    return addCanonPrimitive((index) => CanonContextSet(index, i));
  }

  ModuleInstanceIndex coreInstantiate(CoreInstanceExpression expr) {
    final index = _component._counters.incrementCoreInstance();
    _instructions.add(expr);
    return index;
  }

  ComponentInstanceIndex instance({
    required List<(String, Sort, Index)> inlineExports,
  }) {
    final index = _component._counters.incrementComponentInstance();
    _instructions.add(InstanceFromInlineExports(inlineExports));
    return index;
  }

  void export(Export export) {
    _instructions.add(export);
  }

  @override
  void serialize(w.Serializer s) {
    for (final section in _toSections()) {
      section.serialize(s);
    }
  }

  Iterable<w.Section> _toSections() sync* {
    w.Section? currentSection;

    for (final instruction in _instructions) {
      switch (instruction) {
        case AliasDefinition():
          if (currentSection is AliasSection) {
            currentSection.aliases.add(instruction);
          } else {
            if (currentSection != null) yield currentSection;
            currentSection = AliasSection([instruction]);
          }
        case CanonicalDefinition():
          if (currentSection is CanonSection) {
            currentSection.definitions.add(instruction);
          } else {
            if (currentSection != null) yield currentSection;
            currentSection = CanonSection([instruction]);
          }
        case CoreInstanceExpression():
          if (currentSection is CoreInstanceSection) {
            currentSection.instances.add(instruction);
          } else {
            if (currentSection != null) yield currentSection;
            currentSection = CoreInstanceSection([instruction]);
          }
        case InstanceFromInlineExports():
          if (currentSection is InstanceSection) {
            currentSection.instances.add(instruction);
          } else {
            if (currentSection != null) yield currentSection;
            currentSection = InstanceSection([instruction]);
          }
        case Export():
          if (currentSection is ExportsSection) {
            currentSection.exports.add(instruction);
          } else {
            if (currentSection != null) yield currentSection;
            currentSection = ExportsSection([instruction]);
          }
      }
    }

    if (currentSection != null) yield currentSection;
  }
}
