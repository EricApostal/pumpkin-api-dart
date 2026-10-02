use anyhow::Result;
use heck::ToUpperCamelCase;
use crate::dart_source::{dart_ident, option_is_nullable};
use serde::Serialize;
use std::{borrow::Cow, fmt::Write, rc::Rc};
use wit_bindgen_core::{
    WorldGenerator,
    abi::{
        AbiVariant, LiftLower, WasmSignature, call, guest_export_needs_post_return, post_return,
    },
    uwrite, uwriteln,
    wit_parser::{
        Function, FunctionKind, InterfaceId, Resolve, SizeAlign, Type, TypeDefKind, TypeId,
        TypeOwner, WorldKey,
    },
};

use crate::{
    abi_export::SerializableAbi,
    dart_source::{DartDefinition, DartSource, KnownDartUri},
    functions::{
        DartFunctionGenerator, ExportedFuncMode, ExportedFunctionMode, FunctionMode,
        ImportedFunctionMode, PostReturn,
    },
};

#[derive(Default, Clone, Serialize)]
pub struct FunctionOptions {
    pub use_memory: bool,
    pub uses_strings: bool,
    /// The function receives lists, which the host allocates in guest memory
    /// through `realloc`.
    pub needs_realloc: bool,
    pub uses_callback: bool,
    /// Only set on lifted (export) functions, a function to clean up temporary values allocated by
    /// this function.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub post_return: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub task_return_import: Option<String>,
}

/// A core import that drops handles of one resource type, lowered to
/// `canon resource.drop`.
#[derive(Serialize)]
pub struct ResourceDropImport {
    pub core_name: String,
    /// Index of the resource in the ABI's `type_defs`.
    pub type_id: usize,
}

#[derive(Serialize)]
pub struct ImportedCoreFunction {
    pub interface_id: usize,
    pub function_name: String,
    pub core_name: Rc<String>,
    pub options: FunctionOptions,
}

pub struct ExportedInstance {
    /// The private top-level Dart variable storing the instance to export.
    pub field_name: String,
    /// The generated interface of the instance to export.
    pub class_name: Rc<String>,
    pub interface: InterfaceId,
    pub functions: Vec<ExportedCoreFunction>,
}

impl ExportedInstance {
    pub fn public_field_name(&self) -> &str {
        assert!(self.field_name.chars().nth(0) == Some('_'));
        &self.field_name[1..]
    }
}

#[derive(Serialize)]
pub struct ExportedCoreFunction {
    pub function_name: String,
    pub core_export_name: String,
    pub options: FunctionOptions,
}

/// A function exported directly from the world (`export foo: func(...)`),
/// as opposed to one grouped into an interface instance. Populated in two
/// steps: `export_funcs` records which functions need this treatment (and
/// keeps an owned copy of their signature, since `DartWorldGenerator` isn't
/// generic over the `Resolve`'s lifetime), then `finish` fills in the
/// generated core export name/options once the wrapper function has
/// actually been generated.
pub struct PendingBareExport {
    pub field_name: String,
    pub function: Function,
}

#[derive(Serialize)]
pub struct SerializableBareExport {
    pub function_name: String,
    pub core_export_name: String,
    pub options: FunctionOptions,
    #[serde(flatten)]
    pub function: Function,
}

#[derive(Default)]
pub struct DartWorldGenerator {
    pub size_align: SizeAlign,
    pub main: DartSource,
    pub function_imports: Vec<ImportedCoreFunction>,
    /// One `resource.drop` import per resource type.
    pub resource_drops: Vec<ResourceDropImport>,
    pub instance_exports: Vec<ExportedInstance>,
    pub pending_bare_exports: Vec<PendingBareExport>,
    pub bare_exports: Vec<SerializableBareExport>,
    /// The generated `abstract interface class` collecting the world's
    /// bare function exports (e.g. `PluginExports`), when the world has any.
    /// Plugin authors implement it and pass an instance to `define<World>`.
    pub world_exports_class: Option<String>,
}

impl DartWorldGenerator {
    pub fn serialize_abi(&self, resolve: &Resolve) -> anyhow::Result<String> {
        Ok(serde_json::to_string(&SerializableAbi {
            resolve,
            imports: &self.function_imports,
            resource_drops: &self.resource_drops,
            exports: &self.instance_exports,
            bare_exports: &self.bare_exports,
        })?)
    }
}

use crate::debug_checkpoint;

/// Returns the short, Dart-facing name of a resource-attached function given
/// its mangled WIT name (`[method]player.name` -> `name`, `[static]player.foo`
/// -> `foo`). Constructors have no meaningful short name in WIT (there's at
/// most one per resource) so they're generated as a fixed `create` factory.
fn resource_function_short_name(mangled_name: &str) -> &str {
    match mangled_name.rsplit_once('.') {
        Some((_, short)) => short,
        None => "create",
    }
}

impl DartWorldGenerator {
    /// Generates a Dart class for every resource type in the package, ahead
    /// of any interface/function processing. Resources are handled as their
    /// own pass (rather than as part of `import_interface`'s function loop)
    /// because a resource's methods live in the same interface's function
    /// map as ordinary freestanding functions, but need to become instance
    /// methods on a dedicated class instead of members of the interface's
    /// abstract class. Only the import direction is implemented: Pumpkin's
    /// plugin API only ever hands the guest opaque handles to host-owned
    /// resources (Player, World, Entity, ...), never asks the guest to
    /// implement one, so guest-side resource tables/drop dispatch aren't
    /// needed.
    fn generate_resources(&mut self, resolve: &Resolve) {
        let resource_ids: Vec<TypeId> = resolve
            .types
            .iter()
            .filter(|(_, def)| matches!(def.kind, TypeDefKind::Resource))
            .map(|(id, _)| id)
            .collect();
        debug_checkpoint(&format!("generate_resources: {} resources", resource_ids.len()));

        // Reserve every resource's Dart class name up front so that
        // signatures can reference resources regardless of the order
        // bodies are generated in (Dart doesn't require forward
        // declarations within a library, so this is purely so
        // `resource_name` lookups never miss).
        for &id in &resource_ids {
            self.main.reserve_resource_name(resolve, id);
        }
        debug_checkpoint(&format!("reserved resource ids: {:?}", resource_ids));

        // With resources named, give every other named type its Dart name
        // before any bodies (which may lazily define referenced types) or
        // interface classes are generated, so types win bare names.
        self.main.reserve_named_types(resolve);

        for id in resource_ids {
            self.generate_resource(resolve, id);
        }
    }


    /// Starts the Dart class for a resource: the `resource.drop` import, the
    /// class declaration extending the runtime's `Resource`, and its owned
    /// and borrowed constructors.
    fn write_resource_header(
        &mut self,
        def: &mut DartDefinition,
        id: TypeId,
        class_name: &str,
        docs: &wit_bindgen_core::wit_parser::Docs,
    ) {
        let drop_name = format!("_drop{}", self.resource_drops.len());
        self.resource_drops.push(ResourceDropImport {
            core_name: drop_name.clone(),
            type_id: id.index(),
        });
        uwriteln!(def, "@pragma(\"wasm:import\", r\"component.{drop_name}\")");
        uwrite!(def, "external ");
        def.imported_identifier(&mut self.main, KnownDartUri::DartWasm, "WasmVoid");
        uwrite!(def, " {drop_name}(");
        def.imported_identifier(&mut self.main, KnownDartUri::DartWasm, "WasmI32");
        uwriteln!(def, " handle);");

        def.write_docs(docs);
        uwrite!(def, "final class {class_name} extends ");
        def.imported_identifier(&mut self.main, KnownDartUri::PkgWasmComponents, "Resource");
        uwriteln!(def, " {{");
        uwriteln!(
            def,
            "  {class_name}._own(int handle) : super.owned(handle, _drop{class_name});"
        );
        uwriteln!(def, "  {class_name}._borrowed(int handle) : super.borrowed(handle);");
        uwrite!(def, "  static void _drop{class_name}(int handle) {{ {drop_name}(");
        def.imported_identifier(&mut self.main, KnownDartUri::DartWasm, "WasmI32");
        uwriteln!(def, ".fromInt(handle)); }}");
    }

    fn generate_resource(&mut self, resolve: &Resolve, id: TypeId) {
        let def = &resolve.types[id];
        let class_name = self.main.reserve_resource_name(resolve, id);
        debug_checkpoint(&format!("generate_resource: {:?} name={class_name}", id));

        let TypeOwner::Interface(owner_iface) = def.owner else {
            // Resources without an owning interface (e.g. declared directly
            // in a world) have no functions to bind; still emit a bare
            // handle-wrapper class so references to the type compile.
            let mut def = DartDefinition::default();
            self.write_resource_header(&mut def, id, &class_name, &resolve.types[id].docs);
            let _ = writeln!(def, "}}");
            self.main.consume_definition(def);
            return;
        };

        let mut body = DartDefinition::default();
        self.write_resource_header(&mut body, id, &class_name, &def.docs);

        let interface = &resolve.interfaces[owner_iface];
        let mut accessors = ResourceAccessors::default();
        for (name, function) in &interface.functions {
            let resource_id = match function.kind {
                FunctionKind::Method(rid) | FunctionKind::AsyncMethod(rid) => Some((rid, true)),
                FunctionKind::Static(rid) | FunctionKind::AsyncStatic(rid) => Some((rid, false)),
                FunctionKind::Constructor(rid) => Some((rid, false)),
                FunctionKind::Freestanding | FunctionKind::AsyncFreestanding => None,
            };
            let Some((resource_id, is_method)) = resource_id else {
                continue;
            };
            if resource_id != id {
                continue;
            }

            let variant = if function.kind.is_async() {
                AbiVariant::GuestImportAsync
            } else {
                AbiVariant::GuestImport
            };
            let core_name = Rc::new(format!("_import{}", self.function_imports.len()));
            let short_name = resource_function_short_name(name);
            debug_checkpoint(&format!("generate_resource fn: {name}"));

            body.write_docs(&function.docs);
            let is_constructor = matches!(function.kind, FunctionKind::Constructor(_));
            let is_async = function.kind.is_async();

            if is_async {
                uwrite!(body, "Future<");
            }
            if is_constructor {
                uwrite!(body, "static ");
                body.write_dart_type(&mut self.main, resolve, &Type::Id(resource_id));
            } else if !is_method {
                uwrite!(body, "static ");
                body.write_optional_dart_type(&mut self.main, resolve, function.result.as_ref());
            } else {
                body.write_optional_dart_type(&mut self.main, resolve, function.result.as_ref());
            }
            if is_async {
                uwrite!(body, ">");
            }

            let _ = write!(body, " {}(", dart_ident(short_name));
            let params_to_write = if is_method {
                &function.params[1..]
            } else {
                &function.params[..]
            };
            if !params_to_write.is_empty() {
                let _ = write!(body, "{{");
                for param in params_to_write {
                    let _ = write!(body, "required ");
                    body.write_dart_type(&mut self.main, resolve, &param.ty);
                    let _ = write!(body, " {}, ", dart_ident(&param.name));
                }
                let _ = write!(body, "}}");
            }
            let _ = writeln!(body, ") {{");

            if is_method {
                let _ = writeln!(body, "final self = this;");
            }

            let mut generator = DartFunctionGenerator::new(
                &self.size_align,
                &mut self.main,
                FunctionMode::Imported(ImportedFunctionMode {
                    core_name: &core_name,
                    function,
                }),
            );
            call(
                resolve,
                variant,
                LiftLower::LowerArgsLiftResults,
                function,
                &mut generator,
                is_async,
            );
            generator.write_cleanup();
            if generator.needs_cleanup_list {
                let _ = writeln!(body, "final _cleanups = <void Function()>[];");
            }
            let _ = writeln!(body, "{}", generator.definition.take_code());
            let _ = writeln!(body, "}}");

            {
                let options = generator.options;
                let signature = resolve.wasm_signature(variant, function);
                let mut import = DartDefinition::default();
                uwriteln!(
                    &mut import,
                    "@pragma(\"wasm:import\", r\"component.{}\")",
                    core_name
                );
                uwrite!(&mut import, "external ");
                import.write_core_signature(&mut self.main, &core_name, &signature);
                let _ = writeln!(&mut import, ";");
                self.main.consume_definition(import);

                self.function_imports.push(ImportedCoreFunction {
                    interface_id: owner_iface.index(),
                    function_name: name.to_string(),
                    core_name: core_name.clone(),
                    options,
                });
            }

            accessors.method_idents.push(dart_ident(short_name));
            if is_method && !is_async && !is_constructor {
                self.collect_accessor(&mut accessors, resolve, short_name, function);
            }
        }

        self.write_property_accessors(&mut body, &accessors);
        let _ = writeln!(body, "}}");
        self.main.consume_definition(body);

        self.generate_views(resolve, id, &class_name, &accessors);
    }

    fn type_string(&mut self, resolve: &Resolve, ty: &Type) -> String {
        let mut scratch = DartDefinition::default();
        scratch.write_dart_type(&mut self.main, resolve, ty);
        scratch.take_code()
    }

    /// Records `get-x` / `set-x` methods so they can be exposed as properties.
    fn collect_accessor(
        &mut self,
        accessors: &mut ResourceAccessors,
        resolve: &Resolve,
        short_name: &str,
        function: &Function,
    ) {
        if let Some(rest) = short_name.strip_prefix("get-") {
            if function.params.len() == 1 {
                if let Some(result) = &function.result {
                    let ty = self.type_string(resolve, result);
                    accessors.getters.push(GetterInfo {
                        property: dart_ident(rest),
                        method: dart_ident(short_name),
                        ty,
                        result: *result,
                        docs: function.docs.clone(),
                    });
                }
            }
        } else if let Some(rest) = short_name.strip_prefix("set-") {
            if function.params.len() == 2 {
                let returns_bool = match &function.result {
                    None => false,
                    Some(Type::Bool) => true,
                    // Setters that report errors can't be property setters.
                    Some(_) => return,
                };
                let ty = self.type_string(resolve, &function.params[1].ty);
                accessors.setters.push(SetterInfo {
                    property: dart_ident(rest),
                    method: dart_ident(short_name),
                    parameter: dart_ident(&function.params[1].name),
                    ty,
                    returns_bool,
                });
            }
        }
    }

    /// Emits `T get foo => getFoo();` (and the setter, when there's a matching
    /// `set-foo`) for every getter that doesn't collide with another member.
    fn write_property_accessors(&self, body: &mut DartDefinition, accessors: &ResourceAccessors) {
        const RESERVED: &[&str] = &[
            "isValid",
            "isOwned",
            "dispose",
            "hashCode",
            "runtimeType",
            "toString",
            "resourceHandle",
            "takeHandle",
            "keep",
        ];
        for getter in &accessors.getters {
            if accessors.method_idents.contains(&getter.property)
                || RESERVED.contains(&getter.property.as_str())
            {
                continue;
            }
            body.write_docs(&getter.docs);
            let _ = writeln!(body, "{} get {} => {}();", getter.ty, getter.property, getter.method);
            let setter = accessors
                .setters
                .iter()
                .find(|s| s.property == getter.property && s.ty == getter.ty && !s.returns_bool);
            if let Some(setter) = setter {
                let _ = writeln!(
                    body,
                    "set {}({} value) {{ {}({}: value); }}",
                    getter.property, setter.ty, setter.method, setter.parameter
                );
            }
        }
    }

    /// For a `get-x-data`/`set-x-data` pair over a variant whose cases hold
    /// records, generates one view type per case: the resource, known to be of
    /// that case, with the record's fields as properties.
    fn generate_views(
        &mut self,
        resolve: &Resolve,
        owner_id: TypeId,
        class_name: &str,
        accessors: &ResourceAccessors,
    ) {
        for getter in &accessors.getters {
            if !getter.property.ends_with("Data") {
                continue;
            }
            let Type::Id(result_id) = getter.result else { continue };
            let variant_id = DartSource::resolve_alias_chain(resolve, result_id);
            let TypeDefKind::Variant(variant) = &resolve.types[variant_id].kind else {
                continue;
            };
            let Some(setter) = accessors
                .setters
                .iter()
                .find(|s| s.property == getter.property && s.ty == getter.ty)
            else {
                continue;
            };

            let mut cast_methods = Vec::new();
            for case in &variant.cases {
                let Some(Type::Id(payload)) = case.ty else { continue };
                let record_id = DartSource::resolve_alias_chain(resolve, payload);
                let TypeDefKind::Record(record) = &resolve.types[record_id].kind else {
                    continue;
                };

                let case_class = self.main.variant_case_name(resolve, variant_id, &case.name);
                let record_class = self.main.named_type(resolve, record_id);
                let view = self
                    .main
                    .reserve_extra_name(heck::ToUpperCamelCase::to_upper_camel_case(case.name.as_str()), "View");

                let mut def = DartDefinition::default();
                let _ = writeln!(
                    def,
                    "/// A [{class_name}] known to be of kind `{}`: its `{}` fields as properties.\n\
                     /// Get one with `as{view}()` or [{view}.tryFrom].",
                    case.name, case.name
                );
                let _ = writeln!(
                    def,
                    "extension type {view}._({class_name} {owner}) implements {class_name} {{",
                    owner = "base"
                );
                let _ = writeln!(
                    def,
                    "  /// Views [base] as `{}`, or returns null if it is another kind.\n  static {view}? tryFrom({class_name} base) => base.{}() is {case_class} ? {view}._(base) : null;",
                    case.name, getter.method
                );
                let _ = writeln!(
                    def,
                    "  /// All data of this kind.\n  {record_class} get data => (base.{}() as {case_class}).value;",
                    getter.method
                );
                if setter.returns_bool {
                    let _ = writeln!(
                        def,
                        "  set data({record_class} value) {{\n    if (!base.{}({}: {case_class}(value))) {{\n      throw StateError('The host rejected the update of {view} data.');\n    }}\n  }}",
                        setter.method, setter.parameter
                    );
                } else {
                    let _ = writeln!(
                        def,
                        "  set data({record_class} value) {{ base.{}({}: {case_class}(value)); }}",
                        setter.method, setter.parameter
                    );
                }
                for field in &record.fields {
                    let ident = dart_ident(&field.name);
                    let ty = self.type_string(resolve, &field.ty);
                    let is_option = matches!(field.ty, Type::Id(id) if matches!(&resolve.types[id].kind, TypeDefKind::Option(inner) if option_is_nullable(resolve, inner)));
                    def.write_docs(&field.docs);
                    let _ = writeln!(def, "  {ty} get {ident} => data.{ident};");
                    if is_option {
                        let clear = crate::dart_source::clear_flag_name(&field.name);
                        let _ = writeln!(
                            def,
                            "  set {ident}({ty} value) => data = data.copyWith({ident}: value, {clear}: value == null);"
                        );
                    } else {
                        let _ = writeln!(
                            def,
                            "  set {ident}({ty} value) => data = data.copyWith({ident}: value);"
                        );
                    }
                }
                let _ = writeln!(def, "}}");
                self.main.consume_definition(def);
                cast_methods.push((view, case.name.clone()));
            }

            if cast_methods.is_empty() {
                continue;
            }

            // `asZombie()` on the resource itself...
            let extension = self.main.reserve_extra_name(format!("{class_name}Views"), "Ext");
            let mut def = DartDefinition::default();
            let _ = writeln!(def, "extension {extension} on {class_name} {{");
            for (view, _) in &cast_methods {
                if accessors.method_idents.contains(&format!("as{view}")) {
                    continue;
                }
                let _ = writeln!(
                    def,
                    "  /// This as a [{view}], or null if it is another kind.\n  {view}? as{view}() => {view}.tryFrom(this);"
                );
            }
            let _ = writeln!(def, "}}");
            self.main.consume_definition(def);

            // ... and on resources that can be turned into it with `as-<resource>`.
            let owner_wit_name = resolve.types[owner_id].name.clone().unwrap_or_default();
            let converter = format!("as-{owner_wit_name}");
            let mut others: Vec<(TypeId, String)> = Vec::new();
            for (_, iface) in &resolve.interfaces {
                for (fname, function) in &iface.functions {
                    let FunctionKind::Method(rid) = function.kind else { continue };
                    if rid == owner_id || resource_function_short_name(fname) != converter {
                        continue;
                    }
                    let Some(Type::Id(result)) = function.result else { continue };
                    let TypeDefKind::Option(Type::Id(inner)) = &resolve.types[result].kind else {
                        continue;
                    };
                    // An `option<resource>` holds a handle type, not the resource.
                    let mut target = DartSource::resolve_alias_chain(resolve, *inner);
                    if let TypeDefKind::Handle(handle) = &resolve.types[target].kind {
                        let (wit_bindgen_core::wit_parser::Handle::Own(h)
                        | wit_bindgen_core::wit_parser::Handle::Borrow(h)) = handle;
                        target = DartSource::resolve_alias_chain(resolve, *h);
                    }
                    if target == owner_id {
                        others.push((rid, dart_ident(&converter)));
                    }
                }
            }
            for (other_id, converter_ident) in others {
                let other_class = self.main.named_type(resolve, other_id);
                let extension = self
                    .main
                    .reserve_extra_name(format!("{other_class}{class_name}Views"), "Ext");
                let mut def = DartDefinition::default();
                let _ = writeln!(def, "extension {extension} on {other_class} {{");
                for (view, _) in &cast_methods {
                    let _ = writeln!(
                        def,
                        "  /// This as a [{view}], or null if it is not a {class_name} of that kind.\n  {view}? as{view}() => {converter_ident}()?.as{view}();"
                    );
                }
                let _ = writeln!(def, "}}");
                self.main.consume_definition(def);
            }
        }
    }
}

#[derive(Default)]
struct ResourceAccessors {
    /// The Dart names of every method of the resource.
    method_idents: Vec<String>,
    getters: Vec<GetterInfo>,
    setters: Vec<SetterInfo>,
}

struct GetterInfo {
    property: String,
    method: String,
    ty: String,
    result: Type,
    docs: wit_bindgen_core::wit_parser::Docs,
}

struct SetterInfo {
    property: String,
    method: String,
    parameter: String,
    ty: String,
    returns_bool: bool,
}

impl WorldGenerator for DartWorldGenerator {
    fn preprocess(&mut self, resolve: &Resolve, _world: wit_bindgen_core::wit_parser::WorldId) {
        self.size_align.fill(resolve);
        self.generate_resources(resolve);
    }

    fn import_interface(
        &mut self,
        resolve: &wit_bindgen_core::wit_parser::Resolve,
        name: &wit_bindgen_core::wit_parser::WorldKey,
        iface: wit_bindgen_core::wit_parser::InterfaceId,
        _files: &mut wit_bindgen_core::Files,
    ) -> Result<()> {
        let class_name = self.main.define_interface(&resolve, iface);

        let mut def = DartDefinition::default();

        {
            let def = &mut def;
            let _ = writeln!(
                def,
                "final class _Imported${} implements {} {{\n  const _Imported${}();",
                class_name, class_name, class_name
            );

            let interface = &resolve.interfaces[iface];
            for (name, function) in &interface.functions {
                if !matches!(
                    function.kind,
                    FunctionKind::Freestanding | FunctionKind::AsyncFreestanding
                ) {
                    // Resource-attached functions (methods/statics/constructors) are
                    // generated as part of the resource's own class by
                    // `generate_resources`, not as members of the interface.
                    continue;
                }

                let variant = if function.kind.is_async() {
                    AbiVariant::GuestImportAsync
                } else {
                    AbiVariant::GuestImport
                };
                let core_name = Rc::new(format!("_import{}", self.function_imports.len()));
                debug_checkpoint(&format!("import_interface fn: {name}"));

                uwriteln!(def, "@override");
                def.write_function_signature(&mut self.main, resolve, name, function);
                let _ = writeln!(def, "{{");
                let mut generator = DartFunctionGenerator::new(
                    &self.size_align,
                    &mut self.main,
                    FunctionMode::Imported(ImportedFunctionMode {
                        core_name: &core_name,
                        function,
                    }),
                );
                call(
                    resolve,
                    variant,
                    LiftLower::LowerArgsLiftResults,
                    function,
                    &mut generator,
                    function.kind.is_async(),
                );
                generator.write_cleanup();
                if generator.needs_cleanup_list {
                    let _ = writeln!(def, "final _cleanups = <void Function()>[];");
                }
                let _ = writeln!(def, "{}\n}}", generator.definition.take_code());

                {
                    let options = generator.options;
                    let signature = resolve.wasm_signature(variant, function);
                    let mut import = DartDefinition::default();
                    uwriteln!(
                        &mut import,
                        "@pragma(\"wasm:import\", r\"component.{}\")",
                        core_name
                    );
                    uwrite!(&mut import, "external ");
                    import.write_core_signature(&mut self.main, &core_name, &signature);
                    let _ = writeln!(&mut import, ";");
                    self.main.consume_definition(import);

                    self.function_imports.push(ImportedCoreFunction {
                        interface_id: iface.index(),
                        function_name: name.to_string(),
                        core_name: core_name.clone(),
                        options,
                    });
                }
            }

            let _ = writeln!(def, "}}");

            // Expose the instance under the interface's own name
            // (`logging`, `scheduler`, ...) rather than an opaque index.
            let import_name: Cow<str> = match name {
                WorldKey::Name(name) => dart_ident(name).into(),
                WorldKey::Interface(id) => match &resolve.interfaces[*id].name {
                    Some(name) => dart_ident(name).into(),
                    None => format!("importedInstance{}", id.index()).into(),
                },
            };
            let _ = writeln!(def, "const {} = _Imported${}();", import_name, class_name);
        }
        self.main.consume_definition(def);

        Ok(())
    }

    fn export_interface(
        &mut self,
        resolve: &wit_bindgen_core::wit_parser::Resolve,
        name: &wit_bindgen_core::wit_parser::WorldKey,
        iface: wit_bindgen_core::wit_parser::InterfaceId,
        _files: &mut wit_bindgen_core::Files,
    ) -> Result<()> {
        let class_name = self.main.define_interface(&resolve, iface);
        // Name the `define<World>` parameter after the exported interface
        // (`metadata`, ...) rather than an opaque index.
        let field_name = match name {
            WorldKey::Name(name) => format!("_{}", dart_ident(name)),
            WorldKey::Interface(id) => match &resolve.interfaces[*id].name {
                Some(name) => format!("_{}", dart_ident(name)),
                None => format!("_unnamedExport{}", id.index()),
            },
        };

        {
            let mut def = DartDefinition::default();
            let _ = writeln!(&mut def, "late {} {};", class_name, field_name);
            self.main.consume_definition(def);
        }

        self.instance_exports.push(ExportedInstance {
            field_name,
            class_name,
            interface: iface,
            functions: Default::default(),
        });
        Ok(())
    }

    fn import_funcs(
        &mut self,
        _resolve: &wit_bindgen_core::wit_parser::Resolve,
        _world: wit_bindgen_core::wit_parser::WorldId,
        _funcs: &[(&str, &wit_bindgen_core::wit_parser::Function)],
        _files: &mut wit_bindgen_core::Files,
    ) {
    }

    fn export_funcs(
        &mut self,
        resolve: &wit_bindgen_core::wit_parser::Resolve,
        world: wit_bindgen_core::wit_parser::WorldId,
        funcs: &[(&str, &wit_bindgen_core::wit_parser::Function)],
        _files: &mut wit_bindgen_core::Files,
    ) -> Result<()> {
        if funcs.is_empty() {
            return Ok(());
        }

        // Collect the world's bare function exports into one abstract class
        // plugin authors implement (Kotlin-bindgen style), instead of a
        // callback parameter per function.
        let world_name = resolve.worlds[world].name.to_upper_camel_case();
        let class_name = self
            .main
            .unique_top_level_name(format!("{world_name}Exports"));

        let mut def = DartDefinition::default();
        let _ = writeln!(
            def,
            "/// The world's exported functions. Implement this and pass an instance to\n/// [define{world_name}] from `main()`.",
        );
        let _ = writeln!(def, "abstract interface class {class_name} {{");
        for (name, function) in funcs {
            def.write_docs(&function.docs);
            let is_async = function.kind.is_async();
            if is_async {
                uwrite!(def, "Future<");
            }
            def.write_optional_dart_type(&mut self.main, resolve, function.result.as_ref());
            if is_async {
                uwrite!(def, ">");
            }
            let _ = write!(def, " {}(", dart_ident(name));
            for (i, param) in function.params.iter().enumerate() {
                if i != 0 {
                    let _ = write!(def, ", ");
                }
                def.write_dart_type(&mut self.main, resolve, &param.ty);
                let _ = write!(def, " {}", dart_ident(&param.name));
            }
            let _ = writeln!(def, ");");

            self.pending_bare_exports.push(PendingBareExport {
                field_name: "_worldExports".to_string(),
                function: (*function).clone(),
            });
        }
        let _ = writeln!(def, "}}");
        let _ = writeln!(def, "late {class_name} _worldExports;");
        self.main.consume_definition(def);

        self.world_exports_class = Some(class_name);
        Ok(())
    }

    fn import_types(
        &mut self,
        _resolve: &wit_bindgen_core::wit_parser::Resolve,
        _world: wit_bindgen_core::wit_parser::WorldId,
        _types: &[(&str, wit_bindgen_core::wit_parser::TypeId)],
        _files: &mut wit_bindgen_core::Files,
    ) {
    }

    fn finish(
        &mut self,
        resolve: &wit_bindgen_core::wit_parser::Resolve,
        world: wit_bindgen_core::wit_parser::WorldId,
        _files: &mut wit_bindgen_core::Files,
    ) -> Result<()> {
        if self.instance_exports.is_empty() && self.pending_bare_exports.is_empty() {
            return Ok(());
        }

        // Generate `define<World>` to install the plugin's implementations;
        // users are supposed to call it in their main() function. The
        // world's bare function exports arrive bundled in one
        // `<World>Exports` instance, interface exports as one named
        // parameter per interface.
        let world_name = resolve.worlds[world].name.to_upper_camel_case();

        let mut def = DartDefinition::default();
        {
            let def = &mut def;
            let _ = write!(def, "void define{world_name}({{");
            if let Some(class_name) = &self.world_exports_class {
                let _ = write!(def, "required {class_name} exports,");
            }
            for export in &self.instance_exports {
                let _ = write!(
                    def,
                    "required {} {},",
                    export.class_name,
                    export.public_field_name()
                );
            }
            let _ = writeln!(def, "}}) {{");
            if self.world_exports_class.is_some() {
                let _ = writeln!(def, "  _worldExports = exports;");
            }
            for export in &self.instance_exports {
                let _ = writeln!(
                    def,
                    "  {} = {};",
                    export.field_name,
                    export.public_field_name()
                );
            }
            let _ = writeln!(def, "}}");
        }

        let mut export_id = 0usize;
        for mut export in &mut self.instance_exports {
            let interface = &resolve.interfaces[export.interface];

            for (name, function) in &interface.functions {
                let this_export_id = export_id;
                export_id += 1;
                let _ = writeln!(
                    def,
                    "@pragma('wasm:export', r'component_{}')",
                    this_export_id
                );
                let abi_variant = if function.kind.is_async() {
                    AbiVariant::GuestExportAsync
                } else {
                    AbiVariant::GuestExport
                };
                let core_signature = resolve.wasm_signature(abi_variant, function);
                def.write_core_signature(
                    &mut self.main,
                    &format!("_component_{}", this_export_id),
                    &core_signature,
                );
                let is_async = function.kind.is_async();
                let async_return_name = format!("_component_{}taskReturn", { this_export_id });
                let mut async_return_params = None;

                let mut generator = DartFunctionGenerator::new(
                    &self.size_align,
                    &mut self.main,
                    FunctionMode::Exported(ExportedFunctionMode {
                        instance: &mut export,
                        async_return_name: &async_return_name,
                        async_return_params: &mut async_return_params,
                    }),
                );
                call(
                    resolve,
                    abi_variant,
                    LiftLower::LiftArgsLowerResults,
                    function,
                    &mut generator,
                    is_async,
                );
                let body = generator.definition.take_code();

                if is_async {
                    let components = generator.dart.import(KnownDartUri::PkgWasmComponents);

                    uwriteln!(
                        def,
                        "{{
final task = {components}.Task.spawn(
  run: () async {{
    {body}
  }},
  debugName: '{name}',
);
return task.finishEventLoopIteration().toWasmI32();
}}"
                    );
                } else {
                    let components = generator.dart.import(KnownDartUri::PkgWasmComponents);
                    uwriteln!(
                        def,
                        "{{\nfinal _scope = {components}.ResourceScope.enter();\ntry {{\n{body}\n}} finally {{\n_scope.exit();\n}}\n}}"
                    );
                }

                let mut options = generator.options;
                let allocated_return = generator.allocated_return_value;

                if let Some(params) = async_return_params {
                    uwrite!(
                        def,
                        "@pragma('wasm:import', 'component.{}')\nexternal ",
                        async_return_name
                    );
                    def.write_core_signature(
                        &mut self.main,
                        &async_return_name,
                        &WasmSignature {
                            params,
                            results: vec![],
                            indirect_params: false,
                            retptr: false,
                        },
                    );
                    uwrite!(def, ";")
                }

                if guest_export_needs_post_return(resolve, function) {
                    let mut generator = DartFunctionGenerator::new(
                        &self.size_align,
                        &mut self.main,
                        FunctionMode::PostReturn(PostReturn {}),
                    );
                    post_return(resolve, function, &mut generator);
                    let code = generator.definition.take_code();
                    options.post_return = Some(format!("component_{this_export_id}_postreturn"));

                    uwriteln!(
                        def,
                        "@pragma('wasm:export', r'component_{this_export_id}_postreturn')",
                    );
                    def.write_core_signature(
                        &mut self.main,
                        &format!("_component_{this_export_id}$postreturn",),
                        &WasmSignature {
                            params: core_signature.results.clone(),
                            results: vec![],
                            indirect_params: false,
                            retptr: false,
                        },
                    );
                    uwrite!(def, "{{\n{code}");
                    let wasm_import = self.main.import(KnownDartUri::DartWasm);

                    if let Some((size, align)) = allocated_return {
                        assert!(core_signature.retptr);
                        def.imported_identifier(
                            &mut self.main,
                            KnownDartUri::PkgWasmComponents,
                            "dartFree",
                        );
                        uwriteln!(
                            &mut def,
                            "(p0, const {wasm_import}.WasmI32({}), const {wasm_import}.WasmI32({}));",
                            size.size_wasm32(),
                            align.align_wasm32(),
                        );
                    }
                    uwriteln!(def, "return {wasm_import}.WasmVoid();");

                    uwriteln!(def, "}}");
                }

                options.uses_callback = is_async;
                export.functions.push(ExportedCoreFunction {
                    core_export_name: format!("component_{}", this_export_id),
                    function_name: name.clone(),
                    options,
                });
            }
        }

        for pending in &self.pending_bare_exports {
            let function = &pending.function;
            let this_export_id = export_id;
            export_id += 1;
            let _ = writeln!(
                def,
                "@pragma('wasm:export', r'component_{}')",
                this_export_id
            );
            let abi_variant = if function.kind.is_async() {
                AbiVariant::GuestExportAsync
            } else {
                AbiVariant::GuestExport
            };
            let core_signature = resolve.wasm_signature(abi_variant, function);
            def.write_core_signature(
                &mut self.main,
                &format!("_component_{}", this_export_id),
                &core_signature,
            );
            let is_async = function.kind.is_async();
            let async_return_name = format!("_component_{}taskReturn", { this_export_id });
            let mut async_return_params = None;

            let mut generator = DartFunctionGenerator::new(
                &self.size_align,
                &mut self.main,
                FunctionMode::ExportedFunc(ExportedFuncMode {
                    field_name: &pending.field_name,
                    async_return_name: &async_return_name,
                    async_return_params: &mut async_return_params,
                }),
            );
            call(
                resolve,
                abi_variant,
                LiftLower::LiftArgsLowerResults,
                function,
                &mut generator,
                is_async,
            );
            let body = generator.definition.take_code();

            if is_async {
                let components = generator.dart.import(KnownDartUri::PkgWasmComponents);

                uwriteln!(
                    def,
                    "{{
final task = {components}.Task.spawn(
  run: () async {{
    {body}
  }},
  debugName: '{}',
);
return task.finishEventLoopIteration().toWasmI32();
}}",
                    function.name
                );
            } else {
                let components = generator.dart.import(KnownDartUri::PkgWasmComponents);
                uwriteln!(
                    def,
                    "{{\nfinal _scope = {components}.ResourceScope.enter();\ntry {{\n{body}\n}} finally {{\n_scope.exit();\n}}\n}}"
                );
            }

            let mut options = generator.options;
            let allocated_return = generator.allocated_return_value;

            if let Some(params) = async_return_params {
                uwrite!(
                    def,
                    "@pragma('wasm:import', 'component.{}')\nexternal ",
                    async_return_name
                );
                def.write_core_signature(
                    &mut self.main,
                    &async_return_name,
                    &WasmSignature {
                        params,
                        results: vec![],
                        indirect_params: false,
                        retptr: false,
                    },
                );
                uwrite!(def, ";")
            }

            if guest_export_needs_post_return(resolve, function) {
                let mut generator = DartFunctionGenerator::new(
                    &self.size_align,
                    &mut self.main,
                    FunctionMode::PostReturn(PostReturn {}),
                );
                post_return(resolve, function, &mut generator);
                let code = generator.definition.take_code();
                options.post_return = Some(format!("component_{this_export_id}_postreturn"));

                uwriteln!(
                    def,
                    "@pragma('wasm:export', r'component_{this_export_id}_postreturn')",
                );
                def.write_core_signature(
                    &mut self.main,
                    &format!("_component_{this_export_id}$postreturn",),
                    &WasmSignature {
                        params: core_signature.results.clone(),
                        results: vec![],
                        indirect_params: false,
                        retptr: false,
                    },
                );
                uwrite!(def, "{{\n{code}");
                let wasm_import = self.main.import(KnownDartUri::DartWasm);

                if let Some((size, align)) = allocated_return {
                    assert!(core_signature.retptr);
                    def.imported_identifier(
                        &mut self.main,
                        KnownDartUri::PkgWasmComponents,
                        "dartFree",
                    );
                    uwriteln!(
                        &mut def,
                        "(p0, const {wasm_import}.WasmI32({}), const {wasm_import}.WasmI32({}));",
                        size.size_wasm32(),
                        align.align_wasm32(),
                    );
                }
                uwriteln!(def, "return {wasm_import}.WasmVoid();");

                uwriteln!(def, "}}");
            }

            options.uses_callback = is_async;
            self.bare_exports.push(SerializableBareExport {
                function_name: function.name.clone(),
                core_export_name: format!("component_{}", this_export_id),
                options,
                function: function.clone(),
            });
        }

        self.main.consume_definition(def);

        Ok(())
    }
}
