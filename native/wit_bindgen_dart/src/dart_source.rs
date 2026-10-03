use std::fmt::{Display, Write};
use std::{
    collections::{HashMap, hash_map::Entry},
    rc::Rc,
};

use heck::{AsLowerCamelCase, AsUpperCamelCase, ToUpperCamelCase};
use wit_bindgen_core::abi::{WasmSignature, WasmType};
use wit_bindgen_core::wit_parser::{
    Docs, Enum, Flags, Function, Handle, InterfaceId, Record, Resolve, Type, TypeDefKind, TypeId,
    TypeOwner, Variant,
};
use wit_bindgen_core::{uwrite, uwriteln};

/// Dart's reserved words (Dart language spec ??16.33): identifiers that can
/// never be used as-is, unlike "built-in identifiers" (like `late` or
/// `required`) which are contextually reserved but still legal names. WIT
/// has no such restriction, so names like `with` or `default` -- both
/// perfectly ordinary WIT record field/parameter names -- need escaping
/// wherever they're emitted as a lower-camel-case Dart identifier.
const DART_RESERVED_WORDS: &[&str] = &[
    "assert", "break", "case", "catch", "class", "const", "continue", "default", "do", "else",
    "enum", "extends", "false", "final", "finally", "for", "if", "in", "is", "new", "null",
    "rethrow", "return", "super", "switch", "this", "throw", "true", "try", "var", "void",
    "while", "with",
    // Not reserved words, but members every Dart `Object` (hence every
    // class) already has. A WIT function or field named e.g. `to-string`
    // is completely ordinary -- Pumpkin's `uuid` interface has one -- but
    // emitting it as a method literally named `toString` collides with
    // `Object.toString()`'s fixed, incompatible signature (and similarly
    // for the others below), which is a compile error, not a shadowing
    // warning. Over-escaping the rare non-method identifier that happens to
    // share one of these names (a field or parameter) is harmless.
    "toString", "hashCode", "runtimeType", "noSuchMethod",
];

/// Converts a WIT name (kebab-case) to a lower-camel-case Dart identifier,
/// escaping it with a trailing underscore if it collides with a Dart
/// reserved word or an inherited `Object` member. Use this (rather than
/// `AsLowerCamelCase` directly) for every WIT-derived name that becomes a
/// real Dart identifier: parameter names, record fields, enum/flags cases,
/// function names.
pub fn dart_ident(name: &str) -> String {
    let camel = AsLowerCamelCase(name).to_string();
    if DART_RESERVED_WORDS.contains(&camel.as_str()) {
        format!("{camel}_")
    } else {
        camel
    }
}

#[derive(Default)]
pub struct DartSource {
    pub header: String,
    definitions: String,
    import_aliases: HashMap<KnownDartUri, Rc<String>>,
    interface_names: HashMap<InterfaceId, Rc<String>>,
    /// Dart type names for named types generated on demand: resources, flags,
    /// variants and enums. Resources are name-reserved eagerly (before any
    /// function signature can reference them) because generating their
    /// bodies requires the world generator's function-call machinery; flags,
    /// variants and enums are self-contained and generated lazily, the first
    /// time they're referenced.
    named_type_names: HashMap<TypeId, Rc<String>>,
    /// Every Dart top-level name handed out so far (interfaces, resources,
    /// flags, variants, enums), used to detect collisions. WIT scopes names
    /// per-interface, so two different interfaces (e.g. Pumpkin's Java and
    /// Bedrock packet interfaces) can both define a type called
    /// `clientbound-packet` -- distinct WIT types, but identical once
    /// upper-camel-cased to a bare Dart class name. A second definition
    /// under the same name is a duplicate top-level declaration in Dart, so
    /// new names are disambiguated (by qualifying with the owning
    /// interface) before that happens.
    used_names: std::collections::HashSet<String>,
    /// Type ids whose Dart name has been reserved (by
    /// [Self::reserve_named_types]) but whose declaration body hasn't been
    /// generated yet. Reserving all named types up front gives *types* first
    /// claim on the bare upper-camel name; the rarely-user-referenced
    /// interface classes yield instead (`event` the variant becomes `Event`,
    /// `event` the interface becomes `EventInterface`) rather than the other
    /// way around (which produced `EventEvent`).
    reserved_pending: std::collections::HashSet<TypeId>,
    /// The Dart class name generated for each variant case, keyed by the
    /// variant's (alias-resolved) type id and the case's WIT name. Case
    /// classes are uniquified like any other top-level name (a case's
    /// `{Variant}{Case}` name can collide with a payload record like
    /// `dialog-input`'s `text(dialog-input-text)`, where both come out as
    /// `DialogInputText`), so the lowering code in `functions.rs` must look
    /// the final name up here instead of re-deriving it.
    variant_case_names: HashMap<(TypeId, String), Rc<String>>,
}

impl DartSource {
    pub fn import(&mut self, uri: KnownDartUri) -> Rc<String> {
        let length = self.import_aliases.len();

        match self.import_aliases.entry(uri.clone()) {
            Entry::Occupied(e) => e.get().clone(),
            Entry::Vacant(vacant) => {
                let name = Rc::new(format!("i{}", length));

                if let KnownDartUri::DartWasm = uri {
                    uwriteln!(&mut self.header, "// ignore: import_internal_library");
                }

                self.header.push_str("import ");
                push_dart_string_literal(&mut self.header, uri.uri_str());
                let _ = write!(&mut self.header, " as {};\n", name);

                vacant.insert(name.clone());
                name
            }
        }
    }

    pub fn define_interface(&mut self, resolve: &Resolve, iface: InterfaceId) -> Rc<String> {
        match self.interface_names.entry(iface) {
            Entry::Occupied(e) => e.get().clone(),
            Entry::Vacant(vacant) => {
                let interface = &resolve.interfaces[iface];
                let base_name = match &interface.name {
                    Some(name) => name.to_upper_camel_case(),
                    None => format!("UnnamedInterface{}", iface.index()),
                };
                // Types have first claim on bare names (see
                // `reserved_pending`); an interface sharing a name with one
                // of its own types (like Pumpkin's `event`) takes an
                // `Interface` suffix instead.
                let unique = if self.used_names.insert(base_name.clone()) {
                    base_name
                } else {
                    Self::unique_name_impl(
                        &mut self.used_names,
                        None,
                        format!("{base_name}Interface"),
                    )
                };
                let class_name = Rc::new(unique);
                vacant.insert(class_name.clone());

                let mut definition = DartDefinition::default();

                definition.write_docs(&interface.docs);
                let _ = writeln!(
                    &mut definition,
                    "abstract interface class {} {{",
                    class_name
                );
                for (name, function) in &interface.functions {
                    if !matches!(
                        function.kind,
                        wit_bindgen_core::wit_parser::FunctionKind::Freestanding
                            | wit_bindgen_core::wit_parser::FunctionKind::AsyncFreestanding
                    ) {
                        // Resource-attached functions become methods on the
                        // resource's own generated class, not members of the
                        // interface abstract class.
                        continue;
                    }
                    definition.write_docs(&function.docs);
                    definition.write_function_signature(self, resolve, name, function);
                    let _ = writeln!(&mut definition, ";");
                }
                let _ = writeln!(&mut definition, "}}");
                self.consume_definition(definition);

                class_name
            }
        }
    }

    pub fn consume_definition(&mut self, definition: DartDefinition) {
        self.definitions.push_str(&definition.0);
    }

    fn fallback_name(id: TypeId) -> String {
        format!("UnnamedType{}", id.index())
    }

    /// Ensures `base_name` is a unique top-level Dart identifier, first
    /// trying `base_name` as-is, then qualifying it with `qualifier` (the
    /// owning interface's name, when known), then falling back to a numeric
    /// suffix. WIT scopes type names per-interface, so e.g. Pumpkin's Java
    /// and Bedrock packet interfaces can both declare a `clientbound-packet`
    /// type -- distinct WIT types that would otherwise collide into the same
    /// bare Dart class name (`ClientboundPacket`), silently producing two
    /// classes with that one name where only the second remains meaningfully
    /// usable, while code generated against the first still compiles (Dart
    /// resolves the name lookup to whichever declaration analysis prefers)
    /// but reads and writes fields that don't match the value's real shape.
    fn unique_name_impl(
        used_names: &mut std::collections::HashSet<String>,
        qualifier: Option<&str>,
        base_name: String,
    ) -> String {
        if used_names.insert(base_name.clone()) {
            return base_name;
        }
        if let Some(qualifier) = qualifier {
            let qualified = format!("{qualifier}{base_name}");
            if used_names.insert(qualified.clone()) {
                return qualified;
            }
        }
        let mut n = 2;
        loop {
            let candidate = format!("{base_name}{n}");
            if used_names.insert(candidate.clone()) {
                return candidate;
            }
            n += 1;
        }
    }

    /// The owning interface's name, upper-camel-cased, if `owner` is an
    /// interface with one -- used as `unique_name_impl`'s disambiguating
    /// qualifier.
    fn owner_qualifier(resolve: &Resolve, owner: TypeOwner) -> Option<String> {
        match owner {
            TypeOwner::Interface(id) => resolve.interfaces[id]
                .name
                .as_ref()
                .map(|n| n.to_upper_camel_case()),
            _ => None,
        }
    }

    /// The Dart base name (before uniquification) for a named, non-resource
    /// type declaration, or `None` for kinds that don't get their own Dart
    /// declaration (aliases, lists, options, ...).
    fn declared_type_base_name(def: &wit_bindgen_core::wit_parser::TypeDef) -> Option<String> {
        let name = def.name.as_ref()?;
        match &def.kind {
            TypeDefKind::Record(_) | TypeDefKind::Variant(_) | TypeDefKind::Enum(_) => {
                Some(name.to_upper_camel_case())
            }
            TypeDefKind::Flags(_) => Some(format!("{}Flag", name.to_upper_camel_case())),
            _ => None,
        }
    }

    /// Reserves Dart names for every named record/variant/enum/flags type up
    /// front (bodies are still generated lazily on first reference). Run
    /// after resources but before any interface class is named, so that
    /// types win bare names over the interface classes that share them.
    pub fn reserve_named_types(&mut self, resolve: &Resolve) {
        for (id, def) in resolve.types.iter() {
            if self.named_type_names.contains_key(&id) {
                continue;
            }
            let Some(base_name) = Self::declared_type_base_name(def) else {
                continue;
            };
            let qualifier = Self::owner_qualifier(resolve, def.owner);
            let name = Rc::new(Self::unique_name_impl(
                &mut self.used_names,
                qualifier.as_deref(),
                base_name,
            ));
            self.named_type_names.insert(id, name);
            self.reserved_pending.insert(id);
        }
    }

    /// Reserves a top-level name for a generated convenience type, preferring
    /// `base_name` and falling back to `{base_name}{suffix}` when it is taken.
    pub fn reserve_extra_name(&mut self, base_name: String, suffix: &str) -> String {
        if self.used_names.insert(base_name.clone()) {
            return base_name;
        }
        Self::unique_name_impl(&mut self.used_names, None, format!("{base_name}{suffix}"))
    }

    /// Ensures `base_name` is a unique top-level Dart identifier and marks it
    /// used. For names that aren't tied to a `TypeId` (like the generated
    /// world-exports class).
    pub fn unique_top_level_name(&mut self, base_name: String) -> String {
        Self::unique_name_impl(&mut self.used_names, None, base_name)
    }

    /// Resolves the Dart name for the named type `id`, computing and
    /// reserving a fresh one when it hasn't been seen yet. Returns the name
    /// and whether the type's declaration body still needs to be generated.
    fn named_type_entry(
        &mut self,
        resolve: &Resolve,
        id: TypeId,
        base_name: String,
    ) -> (Rc<String>, bool) {
        if let Some(name) = self.named_type_names.get(&id) {
            let name = name.clone();
            let needs_body = self.reserved_pending.remove(&id);
            return (name, needs_body);
        }
        let qualifier = Self::owner_qualifier(resolve, resolve.types[id].owner);
        let name = Rc::new(Self::unique_name_impl(
            &mut self.used_names,
            qualifier.as_deref(),
            base_name,
        ));
        self.named_type_names.insert(id, name.clone());
        (name, true)
    }

    /// Reserves (but does not define the body of) a Dart class name for a
    /// resource type. Must be called for every resource before any function
    /// signature referencing it is generated, since resource bodies are
    /// generated eagerly by the world generator (which alone has access to
    /// the call-lowering machinery), while type declarations may be visited
    /// in any order.
    pub fn reserve_resource_name(&mut self, resolve: &Resolve, id: TypeId) -> Rc<String> {
        if let Some(name) = self.named_type_names.get(&id) {
            return name.clone();
        }

        let def = &resolve.types[id];
        let base_name = match &def.name {
            Some(name) => name.to_upper_camel_case(),
            None => Self::fallback_name(id),
        };
        let qualifier = Self::owner_qualifier(resolve, def.owner);
        let name = Rc::new(Self::unique_name_impl(
            &mut self.used_names,
            qualifier.as_deref(),
            base_name,
        ));
        self.named_type_names.insert(id, name.clone());
        name
    }

    /// Resolves `id` through any `use`-introduced alias chain
    /// (`TypeDefKind::Type(Type::Id(..))`) down to the underlying type that
    /// actually declares the resource. `use other.{some-resource}` creates a
    /// new `TypeId` in the importing interface whose kind is an alias
    /// pointing at the original resource's `TypeId`; only the original ever
    /// gets a name reserved by `generate_resources`, so lookups from a
    /// handle referencing the alias need to follow the chain first.
    pub fn resolve_alias_chain(resolve: &Resolve, mut id: TypeId) -> TypeId {
        while let TypeDefKind::Type(Type::Id(inner)) = &resolve.types[id].kind {
            id = *inner;
        }
        id
    }

    fn resource_name(&self, resolve: &Resolve, id: TypeId) -> Rc<String> {
        let id = Self::resolve_alias_chain(resolve, id);
        self.named_type_names
            .get(&id)
            .expect("resource name must be reserved before it is referenced")
            .clone()
    }

    /// Looks up the Dart name generated for a resource, flags, variant or
    /// enum type. Used by instruction lowering/lifting code (in
    /// `functions.rs`), which only has a `TypeId` to work with, to refer to
    /// the same class/enum that `write_def_type` already generated (or will
    /// generate) for that type.
    pub fn named_type(&self, resolve: &Resolve, id: TypeId) -> Rc<String> {
        let id = Self::resolve_alias_chain(resolve, id);
        self.named_type_names
            .get(&id)
            .expect("named type must already be generated by the time it's used in a lowering")
            .clone()
    }

    /// Looks up the Dart class name generated for a variant case (see
    /// `variant_case_names`).
    pub fn variant_case_name(&self, resolve: &Resolve, id: TypeId, case: &str) -> Rc<String> {
        let id = Self::resolve_alias_chain(resolve, id);
        self.variant_case_names
            .get(&(id, case.to_string()))
            .expect("variant must already be generated by the time its cases are lowered")
            .clone()
    }

    fn define_flags(&mut self, resolve: &Resolve, id: TypeId, flags: &Flags) -> Rc<String> {
        let base_name = match &resolve.types[id].name {
            Some(name) => format!("{}Flag", name.to_upper_camel_case()),
            None => Self::fallback_name(id),
        };
        let (name, needs_body) = self.named_type_entry(resolve, id, base_name);
        if !needs_body {
            return name;
        }

        let def = &resolve.types[id];
        let mut definition = DartDefinition::default();
        definition.write_docs(&def.docs);
        let _ = writeln!(&mut definition, "enum {} {{", name);
        for flag in &flags.flags {
            definition.write_docs(&flag.docs);
            let _ = writeln!(&mut definition, "  {},", dart_ident(&flag.name));
        }
        let _ = writeln!(&mut definition, "}}");
        self.consume_definition(definition);

        name
    }

    fn define_enum(&mut self, resolve: &Resolve, id: TypeId, enum_: &Enum) -> Rc<String> {
        let base_name = match &resolve.types[id].name {
            Some(name) => name.to_upper_camel_case(),
            None => Self::fallback_name(id),
        };
        let (name, needs_body) = self.named_type_entry(resolve, id, base_name);
        if !needs_body {
            return name;
        }

        let def = &resolve.types[id];
        let mut definition = DartDefinition::default();
        definition.write_docs(&def.docs);
        let _ = writeln!(&mut definition, "enum {} {{", name);
        let last = enum_.cases.len().saturating_sub(1);
        for (i, case) in enum_.cases.iter().enumerate() {
            definition.write_docs(&case.docs);
            let terminator = if i == last { ";" } else { "," };
            let _ = writeln!(
                &mut definition,
                "  {}('{}'){terminator}",
                dart_ident(&case.name),
                case.name
            );
        }
        // Every enum can be converted to and from its name in the WIT, which
        // is the form used by registries and config files.
        let _ = writeln!(&mut definition, "  const {name}(this.wireName);");
        let _ = writeln!(
            &mut definition,
            "  /// The name of this case in the WIT (kebab-case).\n  final String wireName;"
        );
        let _ = writeln!(
            &mut definition,
            "  /// The case called [wireName] in the WIT, or `null` if there is none.\n  static {name}? fromWireName(String wireName) => _byWireName[wireName];"
        );
        let _ = writeln!(
            &mut definition,
            "  static final Map<String, {name}> _byWireName = {{for (final value in values) value.wireName: value}};"
        );
        let _ = writeln!(&mut definition, "}}");
        self.consume_definition(definition);

        name
    }

    fn define_variant(&mut self, resolve: &Resolve, id: TypeId, variant: &Variant) -> Rc<String> {
        let base_name = match &resolve.types[id].name {
            Some(name) => name.to_upper_camel_case(),
            None => Self::fallback_name(id),
        };
        let (name, needs_body) = self.named_type_entry(resolve, id, base_name);
        if !needs_body {
            return name;
        }

        let def = &resolve.types[id];
        let mut definition = DartDefinition::default();
        definition.write_docs(&def.docs);
        let _ = writeln!(&mut definition, "sealed class {} {{", name);
        let _ = writeln!(&mut definition, "  const {}();", name);
        let _ = writeln!(&mut definition, "}}");

        // Claim every case's class name before writing bodies (payload types
        // may recursively define other variants, which claim names of their
        // own). On collision -- typically with the case's own payload record
        // -- fall back to a `Case` suffix.
        let case_names: Vec<Rc<String>> = variant
            .cases
            .iter()
            .map(|case| {
                let base = format!("{}{}", name, AsUpperCamelCase(&case.name));
                let unique = if self.used_names.insert(base.clone()) {
                    base
                } else {
                    Self::unique_name_impl(&mut self.used_names, None, format!("{base}Case"))
                };
                let case_name = Rc::new(unique);
                self.variant_case_names
                    .insert((id, case.name.clone()), case_name.clone());
                case_name
            })
            .collect();

        for (case, case_name) in variant.cases.iter().zip(case_names) {
            definition.write_docs(&case.docs);
            let _ = write!(&mut definition, "final class {} extends {} {{", case_name, name);
            match &case.ty {
                Some(ty) => {
                    let _ = write!(&mut definition, "\n  final ");
                    definition.write_dart_type(self, resolve, ty);
                    let _ = writeln!(&mut definition, " value;");
                    let _ = writeln!(&mut definition, "  const {}(this.value);", case_name);
                }
                None => {
                    let _ = writeln!(&mut definition, "\n  const {}();", case_name);
                }
            }
            let _ = writeln!(&mut definition, "}}");
        }
        self.consume_definition(definition);

        name
    }

    /// Generates a Dart class for a WIT record: final fields plus a `const`
    /// constructor with required named parameters, so construction reads
    /// like the WIT declaration (`PluginMetadata(name: ..., version: ...)`)
    /// instead of an anonymous record literal.
    pub fn define_record(&mut self, resolve: &Resolve, id: TypeId, record: &Record) -> Rc<String> {
        let base_name = match &resolve.types[id].name {
            Some(name) => name.to_upper_camel_case(),
            None => Self::fallback_name(id),
        };
        let (name, needs_body) = self.named_type_entry(resolve, id, base_name);
        if !needs_body {
            return name;
        }

        let def = &resolve.types[id];
        let mut definition = DartDefinition::default();
        definition.write_docs(&def.docs);
        let _ = writeln!(&mut definition, "final class {} {{", name);
        for field in &record.fields {
            definition.write_docs(&field.docs);
            let _ = write!(&mut definition, "  final ");
            definition.write_dart_type(self, resolve, &field.ty);
            let _ = writeln!(&mut definition, " {};", dart_ident(&field.name));
        }
        if record.fields.is_empty() {
            let _ = writeln!(&mut definition, "  const {}();", name);
        } else {
            let _ = write!(&mut definition, "  const {}({{", name);
            for field in &record.fields {
                let _ = write!(&mut definition, "required this.{}, ", dart_ident(&field.name));
            }
            let _ = writeln!(&mut definition, "}});");

            // Records are immutable, so offer `copyWith` for the common
            // "return the event with one field changed" pattern.
            // Optional fields are nullable, so `null` can't also mean "keep the
            // current value": they get a `clear<Field>` flag to reset them.
            let nullable = |ty: &Type| match ty {
                Type::Id(id) => match &resolve.types[*id].kind {
                    TypeDefKind::Option(inner) => option_is_nullable(resolve, inner),
                    _ => false,
                },
                _ => false,
            };
            let _ = write!(&mut definition, "  {} copyWith({{", name);
            for field in &record.fields {
                if nullable(&field.ty) {
                    // The type already ends in `?`.
                    definition.write_dart_type(self, resolve, &field.ty);
                    let ident = dart_ident(&field.name);
                    let clear = clear_flag_name(&field.name);
                    let _ = write!(&mut definition, " {ident}, bool {clear} = false, ");
                } else {
                    definition.write_dart_type(self, resolve, &field.ty);
                    let _ = write!(&mut definition, "? {}, ", dart_ident(&field.name));
                }
            }
            let _ = write!(&mut definition, "}}) => {}(", name);
            for field in &record.fields {
                let ident = dart_ident(&field.name);
                if nullable(&field.ty) {
                    let clear = clear_flag_name(&field.name);
                    let _ = write!(
                        &mut definition,
                        "{ident}: {clear} ? null : ({ident} ?? this.{ident}), "
                    );
                } else {
                    let _ = write!(&mut definition, "{ident}: {ident} ?? this.{ident}, ");
                }
            }
            let _ = writeln!(&mut definition, ");");

            // Events carry a `cancelled` flag: `event.cancel()` reads better
            // than `event.copyWith(cancelled: true)`.
            if record
                .fields
                .iter()
                .any(|f| f.name == "cancelled" && matches!(f.ty, Type::Bool))
            {
                let _ = writeln!(
                    &mut definition,
                    "  /// This event, cancelled.\n  {name} cancel() => copyWith(cancelled: true);"
                );
            }
        }
        let _ = writeln!(&mut definition, "}}");
        self.consume_definition(definition);

        name
    }
}

/// Whether `option<inner>` is represented as a nullable Dart type. Options of
/// options can't be, since `T??` collapses, so those keep the `Option` wrapper
/// of `package:wasm_components`.
pub fn option_is_nullable(resolve: &Resolve, inner: &Type) -> bool {
    let mut current = *inner;
    loop {
        match current {
            Type::Id(id) => match &resolve.types[id].kind {
                TypeDefKind::Option(_) => return false,
                TypeDefKind::Type(next) => current = *next,
                _ => return true,
            },
            _ => return true,
        }
    }
}

/// The name of the `copyWith` flag that resets the optional field [wit_name].
pub fn clear_flag_name(wit_name: &str) -> String {
    format!("clear{}", wit_name.to_upper_camel_case())
}

impl Display for DartSource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("// ignore_for_file: type=warning\n")?;
        f.write_str(&self.header)?;
        f.write_str("\n")?;
        f.write_str(&self.definitions)
    }
}

#[derive(Default, Debug)]
pub struct DartDefinition(String);

impl DartDefinition {
    pub fn imported_identifier<I: Display>(
        &mut self,
        dart: &mut DartSource,
        import: KnownDartUri,
        id: I,
    ) {
        let name = dart.import(import);
        let _ = write!(self, "{}.{}", name, id);
    }

    pub fn write_docs(&mut self, docs: &Docs) {
        let Some(content) = &docs.contents else {
            return;
        };
        for line in content.lines() {
            let _ = writeln!(self, "/// {}", line);
        }
    }

    pub fn write_function_signature(
        &mut self,
        dart: &mut DartSource,
        resolve: &Resolve,
        name: &str,
        function: &Function,
    ) {
        let is_async = function.kind.is_async();
        if is_async {
            uwrite!(self, "Future<");
        }

        self.write_optional_dart_type(dart, resolve, function.result.as_ref());
        if is_async {
            uwrite!(self, ">");
        }

        let _ = write!(self, " {}(", dart_ident(name));
        if !function.params.is_empty() {
            let _ = write!(self, "{{");
            for param in &function.params {
                let _ = write!(self, "required ");
                self.write_dart_type(dart, resolve, &param.ty);
                let _ = write!(self, " {}, ", dart_ident(&param.name));
            }
            let _ = write!(self, "}}");
        }
        let _ = write!(self, ")");
    }

    pub fn write_optional_dart_type(
        &mut self,
        dart: &mut DartSource,
        resolve: &Resolve,
        wit_type: Option<&Type>,
    ) {
        if let Some(wit_type) = wit_type {
            self.write_dart_type(dart, resolve, wit_type);
        } else {
            self.0.push_str("void");
        }
    }

    pub fn write_dart_type(&mut self, dart: &mut DartSource, resolve: &Resolve, wit_type: &Type) {
        let simple_name = match wit_type {
            Type::Bool => "bool",
            Type::U8
            | Type::U16
            | Type::U32
            | Type::U64
            | Type::S8
            | Type::S16
            | Type::S32
            | Type::S64
            | Type::Char => "int",
            Type::F32 | Type::F64 => "double",
            Type::String => "String",
            Type::ErrorContext => {
                self.imported_identifier(dart, KnownDartUri::PkgWasmComponents, "ErrorContext");
                return;
            }
            Type::Id(id) => {
                self.write_def_type(dart, resolve, *id);
                return;
            }
        };

        self.0.push_str(simple_name);
    }

    pub fn write_def_type(&mut self, dart: &mut DartSource, resolve: &Resolve, id: TypeId) {
        let def_type = &resolve.types[id];

        match &def_type.kind {
            TypeDefKind::Record(record) => {
                let name = dart.define_record(resolve, id, record);
                self.0.push_str(&name);
            }
            TypeDefKind::Resource => {
                let name = dart.resource_name(resolve, id);
                self.0.push_str(&name);
            }
            TypeDefKind::Handle(handle) => {
                let resource_id = match handle {
                    Handle::Own(id) | Handle::Borrow(id) => *id,
                };
                let name = dart.resource_name(resolve, resource_id);
                self.0.push_str(&name);
            }
            TypeDefKind::Flags(flags) => {
                let name = dart.define_flags(resolve, id, flags);
                self.0.push_str("Set<");
                self.0.push_str(&name);
                self.0.push_str(">");
            }
            TypeDefKind::Tuple(tuple) => {
                let _ = write!(self, "(");
                for ty in &tuple.types {
                    self.write_dart_type(dart, resolve, ty);
                    let _ = write!(self, ", ");
                }
                let _ = write!(self, ")");
            }
            TypeDefKind::Variant(variant) => {
                let name = dart.define_variant(resolve, id, variant);
                self.0.push_str(&name);
            }
            TypeDefKind::Enum(enum_) => {
                let name = dart.define_enum(resolve, id, enum_);
                self.0.push_str(&name);
            }
            TypeDefKind::Option(inner) => {
                if option_is_nullable(resolve, inner) {
                    self.write_dart_type(dart, resolve, inner);
                    self.0.push_str("?");
                } else {
                    self.imported_identifier(dart, KnownDartUri::PkgWasmComponents, "Option");
                    self.0.push_str("<");
                    self.write_dart_type(dart, resolve, inner);
                    self.0.push_str(">");
                }
            }
            TypeDefKind::Result(result) => {
                self.imported_identifier(dart, KnownDartUri::PkgWasmComponents, "Result");
                self.0.push_str("<");
                self.write_optional_dart_type(dart, resolve, result.ok.as_ref());
                self.0.push_str(", ");
                self.write_optional_dart_type(dart, resolve, result.err.as_ref());
                self.0.push_str(">");
            }
            TypeDefKind::List(element_type) | TypeDefKind::FixedLengthList(element_type, _) => {
                self.0.push_str("List<");
                self.write_dart_type(dart, resolve, element_type);
                self.0.push_str(">");
            }
            TypeDefKind::Map(k, v) => {
                self.0.push_str("Map<");
                self.write_dart_type(dart, resolve, k);
                self.0.push_str(", ");
                self.write_dart_type(dart, resolve, v);
                self.0.push_str(">");
            }
            TypeDefKind::Future(element_type) => {
                self.0.push_str("Future<");
                self.write_optional_dart_type(dart, resolve, element_type.as_ref());
                self.0.push_str(">");
            }
            TypeDefKind::Stream(element_type) => {
                self.0.push_str("Stream<");
                self.write_optional_dart_type(dart, resolve, element_type.as_ref());
                self.0.push_str(">");
            }
            TypeDefKind::Type(wit_type) => self.write_dart_type(dart, resolve, wit_type),
            TypeDefKind::Unknown => self.0.push_str("Never /* unknown wit type */"),
        }
    }

    pub fn write_core_signature(
        &mut self,
        dart: &mut DartSource,
        name: &str,
        signature: &WasmSignature,
    ) {
        if signature.results.is_empty() {
            self.imported_identifier(dart, KnownDartUri::DartWasm, "WasmVoid");
        } else {
            assert!(signature.results.len() == 1);
            self.write_core_type(dart, &signature.results[0]);
        }

        let _ = write!(self, " {}(", name);
        for (i, param) in signature.params.iter().enumerate() {
            if i != 0 {
                let _ = write!(self, ", ");
            }
            self.write_core_type(dart, param);
            uwrite!(self, " p{i}");
        }
        let _ = write!(self, ")");
    }

    pub fn write_core_type(&mut self, dart: &mut DartSource, core_type: &WasmType) {
        let simple_name = match core_type {
            WasmType::I32 => "WasmI32",
            WasmType::I64 => "WasmI64",
            WasmType::F32 => "WasmF32",
            WasmType::F64 => "WasmF64",
            WasmType::Pointer => "WasmI32",
            WasmType::PointerOrI64 => "WasmI32",
            WasmType::Length => "WasmI32",
        };
        self.imported_identifier(dart, KnownDartUri::DartWasm, simple_name);
    }

    pub fn take_code(self) -> String {
        self.0
    }
}

impl Write for DartDefinition {
    fn write_str(&mut self, s: &str) -> std::fmt::Result {
        self.0.write_str(s)
    }
}

#[derive(PartialEq, Eq, Hash, Clone)]
pub enum KnownDartUri {
    /// `dart:_wasm`
    DartWasm,
    /// `package:wasm_components/component.dart`
    PkgWasmComponents,
    /// `dart:typed_data`
    DartTypedData,
}

impl KnownDartUri {
    fn uri_str(&self) -> &str {
        match self {
            KnownDartUri::DartWasm => "dart:_wasm",
            KnownDartUri::PkgWasmComponents => "package:wasm_components/wasm_components.dart",
            KnownDartUri::DartTypedData => "dart:typed_data",
        }
    }
}

pub fn push_dart_string_literal(target: &mut String, contents: &str) {
    // TODO: Escape
    target.push_str("r'");
    target.push_str(contents);
    target.push('\'');
}
