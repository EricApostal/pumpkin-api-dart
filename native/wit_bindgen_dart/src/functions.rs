use std::rc::Rc;
use std::{fmt::Write, mem};

use crate::dart_source::dart_ident;
use wit_bindgen_core::abi::{Bitcast, WasmType};
use wit_bindgen_core::wit_parser::{Alignment, ArchitectureSize, Handle};
use wit_bindgen_core::{
    abi::{Bindgen, Instruction},
    wit_parser::{Function, Resolve, SizeAlign, Type},
};
use wit_bindgen_core::{uwrite, uwriteln};

use crate::dart_source::DartSource;
use crate::{
    bindgen::{ExportedInstance, FunctionOptions},
    dart_source::{DartDefinition, KnownDartUri},
};

pub struct DartFunctionGenerator<'a> {
    size_align: &'a SizeAlign,
    pub dart: &'a mut DartSource,
    pub definition: DartDefinition,
    block_storage: Vec<DartDefinition>,
    /// Each finished block's generated code, its result operands, and (for
    /// blocks lowering a variant/option/result case's payload) the fresh
    /// name `VariantPayloadName` generated for that payload, if any. A fixed
    /// name like `value` would shadow itself when payloads nest -- e.g. an
    /// `option<T>` field inside a variant case, both wanting to name their
    /// own payload `value` -- so each block gets its own unique temporary
    /// instead, carried alongside the block itself rather than through a
    /// separate ordered list (which can't be made to agree with both the
    /// sequential order case-processing code wants and the depth-first order
    /// nested blocks actually finish in).
    blocks: Vec<(String, Vec<Rc<String>>, Option<Rc<String>>)>,
    /// The payload name generated for the block currently being built at
    /// each nesting level, if `VariantPayloadName` has fired for it yet.
    /// Mirrors `block_storage`'s stack shape: pushed alongside it in
    /// `push_block`, popped alongside it in `finish_block`.
    payload_name_stack: Vec<Option<Rc<String>>>,
    mode: FunctionMode<'a>,
    /// Pending `.free()` calls for temporaries allocated (via `StringLower`)
    /// within the block currently being built, one entry per nesting level
    /// -- mirrors `block_storage`/`payload_name_stack`'s stack shape. These
    /// can't be accumulated into one flat buffer and dumped at the very end
    /// of the function: a temporary allocated inside a switch case or an
    /// if-branch goes out of Dart scope once that block closes, so its
    /// `.free()` call has to be emitted before *that* block's closing brace,
    /// not after the whole function's.
    cleanup_stack: Vec<String>,
    next_temporary: usize,
    pub options: FunctionOptions,
    pub allocated_return_value: Option<(ArchitectureSize, Alignment)>,
    /// Whether the generated body references the function-level `_cleanups`
    /// list (import mode only): lowered argument buffers registered there are
    /// freed right after `CallWasm` returns. The surrounding code generator
    /// must declare `final _cleanups = <void Function()>[];` at the start of
    /// the function body when this is set.
    pub needs_cleanup_list: bool,
    /// The local holding the pointer allocated by `return_pointer`, so import
    /// mode can free the return area after lifting the results out of it.
    return_area: Option<Rc<String>>,
    /// Further areas allocated by `return_pointer` after the first one. An
    /// import with indirect params and a non-flat result needs two: one to
    /// pass the arguments in and one for the result.
    extra_return_areas: Vec<(Rc<String>, ArchitectureSize, Alignment)>,
}

/// Stands in for the current list element until the enclosing `ListLower`
/// picks a unique variable name for it.
const ELEMENT_PLACEHOLDER: &str = "@@element@@";

pub enum FunctionMode<'a> {
    Imported(ImportedFunctionMode<'a>),
    Exported(ExportedFunctionMode<'a>),
    ExportedFunc(ExportedFuncMode<'a>),
    PostReturn(PostReturn),
}

pub struct ImportedFunctionMode<'a> {
    pub core_name: &'a str,
    pub function: &'a Function,
}

pub struct ExportedFunctionMode<'a> {
    pub instance: &'a mut ExportedInstance,
    pub async_return_name: &'a str,
    pub async_return_params: &'a mut Option<Vec<WasmType>>,
}

/// Like `ExportedFunctionMode`, but for a function exported directly from
/// the world rather than one grouped into an interface instance: the call
/// dispatches to a method on the world-exports instance the plugin passes
/// to the generated `define<World>` function.
pub struct ExportedFuncMode<'a> {
    pub field_name: &'a str,
    pub async_return_name: &'a str,
    pub async_return_params: &'a mut Option<Vec<WasmType>>,
}

pub struct PostReturn {}

impl<'a> DartFunctionGenerator<'a> {
    pub fn new(
        size_align: &'a SizeAlign,
        dart: &'a mut DartSource,
        mode: FunctionMode<'a>,
    ) -> Self {
        Self {
            size_align,
            dart,
            definition: DartDefinition::default(),
            mode,
            block_storage: Default::default(),
            blocks: Default::default(),
            payload_name_stack: Default::default(),
            cleanup_stack: vec![String::new()],
            next_temporary: 0,
            options: Default::default(),
            allocated_return_value: None,
            needs_cleanup_list: false,
            return_area: None,
            extra_return_areas: Vec::new(),
        }
    }

    fn temporary_variable(&mut self) -> Rc<String> {
        let rc = Rc::new(format!("tmp{}", self.next_temporary));
        self.next_temporary += 1;
        rc
    }

    fn mem_store(
        &mut self,
        operands: &mut Vec<Rc<String>>,
        method: &str,
        offset: &ArchitectureSize,
    ) {
        let ptr = operands.pop().unwrap();
        let value = operands.pop().unwrap();

        self.definition
            .imported_identifier(self.dart, KnownDartUri::PkgWasmComponents, "memory");
        uwriteln!(
            &mut self.definition,
            ".{method}({ptr}.toIntUnsigned(), {value}, offset: {});",
            offset.size_wasm32()
        );
    }

    fn mem_load(
        &mut self,
        operands: &mut Vec<Rc<String>>,
        results: &mut Vec<Rc<String>>,
        method: &str,
        offset: &ArchitectureSize,
    ) {
        let ptr = operands.pop().unwrap();
        let tmp = self.temporary_variable();

        uwrite!(&mut self.definition, "final {tmp} = ");
        self.definition
            .imported_identifier(self.dart, KnownDartUri::PkgWasmComponents, "memory");
        uwriteln!(
            &mut self.definition,
            ".{method}({ptr}.toIntUnsigned(), offset: {});",
            offset.size_wasm32()
        );
        results.push(tmp);
    }

    fn dart_wasm_import(&mut self) -> Rc<String> {
        self.dart.import(KnownDartUri::DartWasm)
    }

    /// `dart:_wasm`'s `WasmI32`/`WasmF32`/etc. types have no bit-reinterpretation
    /// methods of their own (unlike, say, Rust's `f32::to_bits`), so
    /// float/int bitcasts go through a `dart:typed_data` list view: write the
    /// source value into a typed list of the source representation, then
    /// read it back through a view of the destination representation over
    /// the same backing bytes.
    fn bitcast(&mut self, cast: &Bitcast, value: &str) -> String {
        let wasm = self.dart_wasm_import();
        let typed_data = self.dart.import(KnownDartUri::DartTypedData);

        match cast {
            Bitcast::F32ToI32 => format!(
                "{wasm}.WasmI32.fromInt({typed_data}.Float32List.fromList([{value}.toDouble()]).buffer.asInt32List()[0])"
            ),
            Bitcast::I32ToF32 => format!(
                "{wasm}.WasmF32.fromDouble({typed_data}.Int32List.fromList([{value}.toIntSigned()]).buffer.asFloat32List()[0])"
            ),
            Bitcast::F64ToI64 => format!(
                "{wasm}.WasmI64.fromInt({typed_data}.Float64List.fromList([{value}.toDouble()]).buffer.asInt64List()[0])"
            ),
            Bitcast::I64ToF64 => format!(
                "{wasm}.WasmF64.fromDouble({typed_data}.Int64List.fromList([{value}.toInt()]).buffer.asFloat64List()[0])"
            ),
            Bitcast::F32ToI64 => format!(
                "{wasm}.WasmI64.fromInt({typed_data}.Float32List.fromList([{value}.toDouble()]).buffer.asInt32List()[0])"
            ),
            Bitcast::I64ToF32 => format!(
                "{wasm}.WasmF32.fromDouble({typed_data}.Int32List.fromList([{value}.toInt()]).buffer.asFloat32List()[0])"
            ),
            // On wasm32, `Pointer`, `Length` and `PointerOrI64` are all
            // natively represented as `WasmI32` (see `write_core_type`), so
            // any cast between two of them is a genuine no-op -- but a cast
            // between one of them and a real `I64` is not: it needs the same
            // real width conversion as a plain `I32ToI64`/`I64ToI32` would,
            // since the I32-native side is still only 32 bits wide.
            Bitcast::I32ToI64 | Bitcast::LToI64 | Bitcast::P64ToI64 => {
                format!("{wasm}.WasmI64.fromInt({value}.toIntUnsigned())")
            }
            Bitcast::I64ToI32 | Bitcast::I64ToL | Bitcast::I64ToP64 => {
                format!("{wasm}.WasmI32.fromInt({value}.toIntUnsigned())")
            }
            Bitcast::I32ToL
            | Bitcast::LToI32
            | Bitcast::I32ToP
            | Bitcast::PToI32
            | Bitcast::PToL
            | Bitcast::LToP
            | Bitcast::P64ToP
            | Bitcast::PToP64
            | Bitcast::None => value.to_string(),
            Bitcast::Sequence(casts) => {
                let first = self.bitcast(&casts[0], value);
                self.bitcast(&casts[1], &first)
            }
        }
    }

    pub fn write_cleanup(&mut self) {
        let cleanup = self.cleanup_stack.last_mut().unwrap();
        if !cleanup.is_empty() {
            let cleanup = std::mem::take(cleanup);
            let _ = write!(self.definition, "{}", cleanup);
        }
    }
}

impl<'a> Bindgen for DartFunctionGenerator<'a> {
    type Operand = Rc<String>;

    fn emit(
        &mut self,
        resolve: &wit_bindgen_core::wit_parser::Resolve,
        inst: &wit_bindgen_core::abi::Instruction<'_>,
        operands: &mut Vec<Self::Operand>,
        results: &mut Vec<Self::Operand>,
    ) {
        match inst {
            Instruction::GetArg { nth } => {
                let function = match &self.mode {
                    FunctionMode::Imported(import) => import.function,
                    FunctionMode::Exported(_)
                    | FunctionMode::ExportedFunc(_)
                    | FunctionMode::PostReturn(_) => {
                        results.push(Rc::new(format!("p{nth}")));
                        return;
                    }
                };

                results.push(Rc::new(dart_ident(&function.params[*nth].name)));
            }
            Instruction::CallWasm { name: _, sig } => {
                let has_results = !sig.results.is_empty();
                let core_name = match &self.mode {
                    FunctionMode::Imported(i) => i.core_name,
                    _ => {
                        panic!("Can't generate call instruction in export mode")
                    }
                };

                if has_results {
                    let temp = self.temporary_variable();
                    uwrite!(self.definition, "final {} = ", temp);
                    results.push(temp.clone());
                }

                uwrite!(self.definition, "{}(", core_name);

                let operands = operands.split_off(operands.len() - sig.params.len());
                for (i, operand) in operands.iter().enumerate() {
                    if i != 0 {
                        uwrite!(self.definition, ", ");
                    }

                    uwrite!(self.definition, "{}", operand);
                }
                uwriteln!(self.definition, ");");

                // The host has copied all lowered arguments by the time the
                // call returns, so the buffers registered during lowering can
                // be released now (before the results are lifted).
                if self.needs_cleanup_list {
                    uwriteln!(
                        self.definition,
                        "for (final cleanup in _cleanups) {{ cleanup(); }}"
                    );
                }
            }
            Instruction::CallInterface { func, async_ } => {
                if func.result.is_some() {
                    let tmp = self.temporary_variable();
                    uwrite!(self.definition, "final {tmp} = ");
                    results.push(tmp);
                }

                if *async_ {
                    uwrite!(self.definition, "await ");
                }

                let params = operands.split_off(operands.len() - func.params.len());

                match &mut self.mode {
                    FunctionMode::Exported(interface) => {
                        uwrite!(
                            self.definition,
                            "{}.{}(",
                            interface.instance.field_name,
                            dart_ident(&func.name)
                        );
                        for (value, param) in params.into_iter().zip(func.params.iter()) {
                            uwrite!(
                                self.definition,
                                "{}: {},",
                                dart_ident(&param.name),
                                value
                            );
                        }
                    }
                    FunctionMode::ExportedFunc(f) => {
                        // Bare world-level function exports are methods on
                        // the user's world-exports implementation (see
                        // `export_funcs`), declared with positional
                        // parameters, so they're called positionally too.
                        uwrite!(
                            self.definition,
                            "{}.{}(",
                            f.field_name,
                            dart_ident(&func.name)
                        );
                        for value in params {
                            uwrite!(self.definition, "{value}, ");
                        }
                    }
                    _ => panic!("Cannot use CallInterface in import mode"),
                }

                uwriteln!(self.definition, ");");
            }
            Instruction::Return { amt, func: _ } => {
                // Imports lift all results out of the return area before this
                // point, so it can be released ahead of the return statement.
                if let FunctionMode::Imported(_) = self.mode {
                    for (area, size, align) in mem::take(&mut self.extra_return_areas) {
                        self.definition.imported_identifier(
                            self.dart,
                            KnownDartUri::PkgWasmComponents,
                            "dartFree",
                        );
                        let wasm = self.dart_wasm_import();
                        uwriteln!(
                            self.definition,
                            "({area}, const {wasm}.WasmI32({}), const {wasm}.WasmI32({}));",
                            size.size_wasm32(),
                            align.align_wasm32(),
                        );
                    }
                    if let (Some(area), Some((size, align))) =
                        (self.return_area.take(), self.allocated_return_value)
                    {
                        self.definition.imported_identifier(
                            self.dart,
                            KnownDartUri::PkgWasmComponents,
                            "dartFree",
                        );
                        let wasm = self.dart_wasm_import();
                        uwriteln!(
                            self.definition,
                            "({area}, const {wasm}.WasmI32({}), const {wasm}.WasmI32({}));",
                            size.size_wasm32(),
                            align.align_wasm32(),
                        );
                    }
                }

                if *amt == 0 {
                    if let FunctionMode::Exported(_) | FunctionMode::ExportedFunc(_) = self.mode {
                        let import = self.dart.import(KnownDartUri::DartWasm);
                        uwriteln!(self.definition, "return {import}.WasmVoid();");
                    }
                } else if *amt == 1 {
                    let _ = writeln!(self.definition, "return {};", operands.pop().unwrap());
                } else {
                    todo!("Returning multiple parameters")
                }
            }
            Instruction::StringLower { realloc: _ } => {
                self.options.use_memory = true;
                self.options.uses_strings = true;

                let temp = self.temporary_variable();
                let _ = write!(self.definition, "final {} = ", temp);
                self.definition.imported_identifier(
                    self.dart,
                    KnownDartUri::PkgWasmComponents,
                    "AllocatedString",
                );
                let _ = writeln!(
                    self.definition,
                    ".allocateUtf16({});",
                    operands.pop().unwrap()
                );
                if let FunctionMode::Imported(_) = self.mode {
                    // The caller owns lowered arguments until the host call
                    // returns, so defer the free to after `CallWasm` (via the
                    // function-level `_cleanups` list, which stays in scope
                    // even when this string is lowered inside a nested block).
                    self.needs_cleanup_list = true;
                    uwriteln!(self.definition, "_cleanups.add({temp}.free);");
                }
                // In export mode the lowered results must stay live until the
                // host invokes the post-return function, which frees them.
                results.push(Rc::new(format!("{}.ptr", temp)));
                results.push(Rc::new(format!("{}.packedLength", temp)));
            }
            Instruction::StringLift {} => {
                self.options.use_memory = true;
                self.options.uses_strings = true;

                let length = operands.pop().unwrap();
                let ptr = operands.pop().unwrap();

                let import = self.dart.import(KnownDartUri::PkgWasmComponents);
                results.push(Rc::new(format!(
                    "{import}.AllocatedString.read({ptr}, {length})"
                )));
            }
            Instruction::OptionLift { payload, ty: _ } => {
                let tmp = self.temporary_variable();

                let (some, some_results, _) = self.blocks.pop().unwrap();
                let (none, _, _) = self.blocks.pop().unwrap();

                let has_value = operands.pop().unwrap();
                let components = self.dart.import(KnownDartUri::PkgWasmComponents);
                uwrite!(self.definition, "final {components}.Option<");
                self.definition.write_dart_type(self.dart, resolve, payload);
                uwriteln!(
                    self.definition,
                    "> {tmp};
if ({has_value}.toBool()) {{
  {some}
  {tmp} = {components}.Option.some({});
}} else {{
  {none}
  {tmp} = {components}.Option.none;
}}",
                    some_results[0]
                );

                results.push(tmp);
            }
            Instruction::OptionLower {
                payload,
                ty: _,
                results: result_types,
            } => {
                let (some, some_results, some_payload_name) = self.blocks.pop().unwrap();
                let (none, none_results, _) = self.blocks.pop().unwrap();
                let value = operands.pop().unwrap();

                let result_names = (0..result_types.len())
                    .map(|_| self.temporary_variable())
                    .collect::<Vec<_>>();
                for (wasm_type, name) in result_types.iter().zip(&result_names) {
                    self.definition.write_core_type(self.dart, wasm_type);
                    uwriteln!(self.definition, " {};", name);
                }

                let payload_var = some_payload_name
                    .expect("OptionLower's some-block should have a payload name");
                uwriteln!(self.definition, "if ({value}.hasValue) {{");
                uwrite!(self.definition, "final {payload_var} = ");
                let _ = payload; // payload type only needed for documentation here
                uwriteln!(self.definition, "{value}.requireValue();");
                uwriteln!(self.definition, "{some}");
                for (v, name) in some_results.iter().zip(&result_names) {
                    uwriteln!(self.definition, "{name} = {v};");
                }
                uwriteln!(self.definition, "}} else {{");
                uwriteln!(self.definition, "{none}");
                for (v, name) in none_results.iter().zip(&result_names) {
                    uwriteln!(self.definition, "{name} = {v};");
                }
                uwriteln!(self.definition, "}}");

                results.extend(result_names);
            }
            Instruction::ResultLift { result: r, ty: _ } => {
                let (err, err_results, _) = self.blocks.pop().unwrap();
                let (ok, ok_results, _) = self.blocks.pop().unwrap();
                let discriminant = operands.pop().unwrap();

                let components = self.dart.import(KnownDartUri::PkgWasmComponents);
                let tmp = self.temporary_variable();
                uwrite!(self.definition, "late final {components}.Result<");
                self.definition
                    .write_optional_dart_type(self.dart, resolve, r.ok.as_ref());
                uwrite!(self.definition, ", ");
                self.definition
                    .write_optional_dart_type(self.dart, resolve, r.err.as_ref());
                uwriteln!(self.definition, "> {tmp};");

                uwriteln!(
                    self.definition,
                    "if ({discriminant}.toIntUnsigned() == 0) {{"
                );
                uwriteln!(self.definition, "{ok}");
                uwriteln!(
                    self.definition,
                    "{tmp} = {components}.Result.ok({});",
                    ok_results.first().cloned().unwrap_or_else(|| Rc::new("null".to_string()))
                );
                uwriteln!(self.definition, "}} else {{");
                uwriteln!(self.definition, "{err}");
                uwriteln!(
                    self.definition,
                    "{tmp} = {components}.Result.error({});",
                    err_results.first().cloned().unwrap_or_else(|| Rc::new("null".to_string()))
                );
                uwriteln!(self.definition, "}}");

                results.push(tmp);
            }
            Instruction::GuestDeallocateString => {
                let length = operands.pop().unwrap();
                let ptr = operands.pop().unwrap();

                self.definition.imported_identifier(
                    self.dart,
                    KnownDartUri::PkgWasmComponents,
                    "AllocatedString",
                );
                uwriteln!(&mut self.definition, "({ptr}, {length}).free();");
            }
            Instruction::VariantPayloadName => {
                let name = self.temporary_variable();
                *self
                    .payload_name_stack
                    .last_mut()
                    .expect("VariantPayloadName emitted outside of a block") = Some(name.clone());
                results.push(name);
            }
            Instruction::I32Const { val } => {
                let mut def = DartDefinition::default();
                let _ = write!(&mut def, "const ");
                def.imported_identifier(self.dart, KnownDartUri::DartWasm, "WasmI32");
                let _ = write!(&mut def, "({})", *val);
                results.push(Rc::new(def.take_code()));
            }
            Instruction::ResultLower {
                result: _,
                ty: _,
                results: result_types,
            } => {
                let (err, err_results, err_payload_name) = self.blocks.pop().unwrap();
                let (ok, ok_results, ok_payload_name) = self.blocks.pop().unwrap();
                let value = operands.pop().unwrap();

                let result_names = (0..result_types.len())
                    .map(|_| self.temporary_variable())
                    .collect::<Vec<_>>();

                for (wasm_type, name) in result_types.iter().zip(&result_names) {
                    self.definition.write_core_type(self.dart, wasm_type);
                    uwriteln!(self.definition, " {};", name);
                }

                uwrite!(self.definition, "switch ({value}) {{\n  case ");
                self.definition.imported_identifier(
                    self.dart,
                    KnownDartUri::PkgWasmComponents,
                    "OkResult",
                );
                if let Some(ok_name) = ok_payload_name {
                    uwriteln!(self.definition, "(value: final {ok_name}):\n{ok}");
                } else {
                    uwriteln!(self.definition, "():\n{ok}");
                }
                for (value, name) in ok_results.iter().zip(&result_names) {
                    uwriteln!(self.definition, "{name} = {value};");
                }
                uwrite!(self.definition, "  case ");
                self.definition.imported_identifier(
                    self.dart,
                    KnownDartUri::PkgWasmComponents,
                    "ErrorResult",
                );
                if let Some(err_name) = err_payload_name {
                    uwriteln!(self.definition, "(value: final {err_name}):\n{err}");
                } else {
                    uwriteln!(self.definition, "():\n{err}");
                }
                for (value, name) in err_results.iter().zip(&result_names) {
                    uwriteln!(self.definition, "{name} = {value};");
                }
                uwriteln!(self.definition, "}}");

                results.extend(result_names);
            }
            Instruction::I32Store { offset }
            | Instruction::LengthStore { offset }
            | Instruction::PointerStore { offset } => {
                self.mem_store(operands, "storeInt32", offset);
            }
            Instruction::I32Store8 { offset } => self.mem_store(operands, "storeInt8", offset),
            Instruction::I32Store16 { offset } => self.mem_store(operands, "storeInt16", offset),
            Instruction::I64Store { offset } => self.mem_store(operands, "storeInt64", offset),
            Instruction::F32Store { offset } => self.mem_store(operands, "storeFloat32", offset),
            Instruction::F64Store { offset } => self.mem_store(operands, "storeFloat64", offset),
            Instruction::I32Load { offset }
            | Instruction::LengthLoad { offset }
            | Instruction::PointerLoad { offset } => {
                self.mem_load(operands, results, "loadInt32", offset);
            }
            Instruction::I32Load8U { offset } => {
                self.mem_load(operands, results, "loadUint8", offset)
            }
            Instruction::I32Load8S { offset } => {
                self.mem_load(operands, results, "loadInt8", offset)
            }
            Instruction::I32Load16U { offset } => {
                self.mem_load(operands, results, "loadUint16", offset)
            }
            Instruction::I32Load16S { offset } => {
                self.mem_load(operands, results, "loadInt16", offset)
            }
            Instruction::I64Load { offset } => {
                self.mem_load(operands, results, "loadInt64", offset)
            }
            Instruction::F32Load { offset } => {
                self.mem_load(operands, results, "loadFloat32", offset)
            }
            Instruction::F64Load { offset } => {
                self.mem_load(operands, results, "loadFloat64", offset)
            }
            Instruction::I32FromBool => {
                results.push(Rc::new(format!(
                    "{}.WasmI32.fromBool({})",
                    self.dart_wasm_import(),
                    operands.pop().unwrap(),
                )));
            }
            Instruction::I32FromChar => {
                results.push(Rc::new(format!(
                    "{}.WasmI32.fromInt({})",
                    self.dart_wasm_import(),
                    operands.pop().unwrap(),
                )));
            }
            Instruction::I64FromU64 | Instruction::I64FromS64 => {
                results.push(Rc::new(format!(
                    "{}.WasmI64.fromInt({})",
                    self.dart_wasm_import(),
                    operands.pop().unwrap(),
                )));
            }
            Instruction::I32FromS8 => {
                results.push(Rc::new(format!(
                    "{}.WasmI32.int8FromInt({})",
                    self.dart_wasm_import(),
                    operands.pop().unwrap(),
                )));
            }
            Instruction::I32FromU8 => {
                results.push(Rc::new(format!(
                    "{}.WasmI32.uint8FromInt({})",
                    self.dart_wasm_import(),
                    operands.pop().unwrap(),
                )));
            }
            Instruction::I32FromS16 => {
                results.push(Rc::new(format!(
                    "{}.WasmI32.int16FromInt({})",
                    self.dart_wasm_import(),
                    operands.pop().unwrap(),
                )));
            }
            Instruction::I32FromU16 => {
                results.push(Rc::new(format!(
                    "{}.WasmI32.uint16FromInt({})",
                    self.dart_wasm_import(),
                    operands.pop().unwrap(),
                )));
            }
            Instruction::I32FromS32 => {
                results.push(Rc::new(format!(
                    "{}.WasmI32.fromInt({})",
                    self.dart_wasm_import(),
                    operands.pop().unwrap(),
                )));
            }
            Instruction::I32FromU32 => {
                results.push(Rc::new(format!(
                    "{}.WasmI32.fromInt({})",
                    self.dart_wasm_import(),
                    operands.pop().unwrap(),
                )));
            }
            Instruction::CoreF32FromF32 => {
                let dart_double = operands.pop().unwrap();
                results.push(Rc::new(format!(
                    "{}.WasmF32.fromDouble({dart_double})",
                    self.dart_wasm_import()
                )));
            }
            Instruction::CoreF64FromF64 => {
                let dart_double = operands.pop().unwrap();
                results.push(Rc::new(format!(
                    "{}.WasmF64.fromDouble({dart_double})",
                    self.dart.import(KnownDartUri::DartWasm)
                )));
            }
            Instruction::BoolFromI32 => {
                results.push(Rc::new(format!("{}.toBool()", operands.pop().unwrap())));
            }
            Instruction::CharFromI32 => {
                let import = self.dart.import(KnownDartUri::PkgWasmComponents);
                results.push(Rc::new(format!(
                    "{import}.CharCode({}.toIntUnsigned())",
                    operands.pop().unwrap()
                )));
            }
            Instruction::S64FromI64 | Instruction::U64FromI64 => {
                results.push(Rc::new(format!("{}.toInt()", operands.pop().unwrap())));
            }
            Instruction::S8FromI32 | Instruction::S16FromI32 | Instruction::S32FromI32 => {
                results.push(Rc::new(format!(
                    "{}.toIntSigned()",
                    operands.pop().unwrap()
                )));
            }
            Instruction::U8FromI32 | Instruction::U16FromI32 | Instruction::U32FromI32 => {
                results.push(Rc::new(format!(
                    "{}.toIntUnsigned()",
                    operands.pop().unwrap()
                )));
            }
            Instruction::F32FromCoreF32 => {
                let f32 = operands.pop().unwrap();
                results.push(Rc::new(format!("{f32}.toDouble()")));
            }
            Instruction::F64FromCoreF64 => {
                let f64 = operands.pop().unwrap();
                results.push(Rc::new(format!("{f64}.toDouble()")));
            }
            Instruction::RecordLift {
                record,
                name: _,
                ty,
            } => {
                let tmp = self.temporary_variable();
                let class_name = self.dart.named_type(resolve, *ty);
                let values = operands.split_off(operands.len() - record.fields.len());
                uwrite!(self.definition, "  final {tmp} = {class_name}(");

                for (field, value) in record.fields.iter().zip(&values) {
                    uwrite!(self.definition, "{}: {value}, ", dart_ident(&field.name));
                }

                uwriteln!(self.definition, ");");
                results.push(tmp);
            }
            Instruction::RecordLower {
                record,
                name: _,
                ty: _,
            } => {
                let value = operands.pop().unwrap();
                for field in &record.fields {
                    results.push(Rc::new(format!(
                        "{value}.{}",
                        dart_ident(&field.name)
                    )));
                }
            }
            Instruction::TupleLift { tuple, ty: _ } => {
                let values = operands.split_off(operands.len() - tuple.types.len());
                let tmp = self.temporary_variable();
                uwrite!(self.definition, "final {tmp} = (");
                for value in &values {
                    uwrite!(self.definition, "{value}, ");
                }
                uwriteln!(self.definition, ");");
                results.push(tmp);
            }
            Instruction::TupleLower { tuple, ty: _ } => {
                let value = operands.pop().unwrap();
                for i in 0..tuple.types.len() {
                    results.push(Rc::new(format!("{value}.${}", i + 1)));
                }
            }
            Instruction::EnumLower { .. } => {
                let value = operands.pop().unwrap();
                results.push(Rc::new(format!(
                    "{}.WasmI32.fromInt({value}.index)",
                    self.dart_wasm_import()
                )));
            }
            Instruction::EnumLift { ty, .. } => {
                let value = operands.pop().unwrap();
                let enum_name = self.dart.named_type(resolve, *ty);
                results.push(Rc::new(format!(
                    "{enum_name}.values[{value}.toIntUnsigned()]"
                )));
            }
            Instruction::FlagsLower {
                flags, ty, name: _, ..
            } => {
                let value = operands.pop().unwrap();
                let flag_enum = self.dart.named_type(resolve, *ty);
                let count = flags.repr().count();

                for word_idx in 0..count {
                    let mut bits = String::new();
                    for (bit_idx, flag) in
                        flags.flags.iter().enumerate().skip(word_idx * 32).take(32)
                    {
                        if !bits.is_empty() {
                            bits.push_str(" | ");
                        }
                        let _ = write!(
                            bits,
                            "({value}.contains({flag_enum}.{}) ? {} : 0)",
                            dart_ident(&flag.name),
                            1u32 << (bit_idx % 32)
                        );
                    }
                    if bits.is_empty() {
                        bits.push('0');
                    }
                    let tmp = self.temporary_variable();
                    let wasm = self.dart_wasm_import();
                    uwriteln!(self.definition, "final {tmp} = {wasm}.WasmI32.fromInt({bits});");
                    results.push(tmp);
                }
            }
            Instruction::FlagsLift {
                flags, ty, name: _, ..
            } => {
                let count = flags.repr().count();
                let words = operands.split_off(operands.len() - count);
                let flag_enum = self.dart.named_type(resolve, *ty);
                let tmp = self.temporary_variable();
                uwriteln!(self.definition, "final {tmp} = <{flag_enum}>{{}};");
                for (word_idx, word) in words.iter().enumerate() {
                    for (bit_idx, flag) in
                        flags.flags.iter().enumerate().skip(word_idx * 32).take(32)
                    {
                        uwriteln!(
                            self.definition,
                            "if ({word}.toIntUnsigned() & {} != 0) {tmp}.add({flag_enum}.{});",
                            1u32 << (bit_idx % 32),
                            dart_ident(&flag.name)
                        );
                    }
                }
                results.push(tmp);
            }
            Instruction::VariantLower {
                variant,
                name: _,
                ty,
                results: result_types,
            } => {
                let value = operands.pop().unwrap();
                let mut case_blocks = (0..variant.cases.len())
                    .map(|_| self.blocks.pop().unwrap())
                    .collect::<Vec<_>>();
                case_blocks.reverse();

                let result_names = (0..result_types.len())
                    .map(|_| self.temporary_variable())
                    .collect::<Vec<_>>();
                for (wasm_type, name) in result_types.iter().zip(&result_names) {
                    self.definition.write_core_type(self.dart, wasm_type);
                    uwriteln!(self.definition, " {};", name);
                }

                uwriteln!(self.definition, "switch ({value}) {{");
                for (case, (code, block_results, payload_name)) in
                    variant.cases.iter().zip(&case_blocks)
                {
                    let case_class = self.dart.variant_case_name(resolve, *ty, &case.name);
                    if case.ty.is_some() {
                        let name = payload_name
                            .as_ref()
                            .expect("payload-bearing variant case should have a payload name");
                        uwriteln!(self.definition, "case {case_class}(value: final {name}):");
                    } else {
                        uwriteln!(self.definition, "case {case_class}():");
                    }
                    uwriteln!(self.definition, "{code}");
                    for (v, name) in block_results.iter().zip(&result_names) {
                        uwriteln!(self.definition, "{name} = {v};");
                    }
                }
                uwriteln!(self.definition, "}}");

                results.extend(result_names);
            }
            Instruction::VariantLift {
                variant,
                name: _,
                ty,
            } => {
                let discriminant = operands.pop().unwrap();
                let mut case_blocks = (0..variant.cases.len())
                    .map(|_| self.blocks.pop().unwrap())
                    .collect::<Vec<_>>();
                case_blocks.reverse();

                let variant_name = self.dart.named_type(resolve, *ty);
                let tmp = self.temporary_variable();
                uwriteln!(self.definition, "late final {variant_name} {tmp};");
                uwriteln!(
                    self.definition,
                    "switch ({discriminant}.toIntUnsigned()) {{"
                );
                for (i, (case, (code, block_results, _))) in
                    variant.cases.iter().zip(&case_blocks).enumerate()
                {
                    let case_class = self.dart.variant_case_name(resolve, *ty, &case.name);
                    uwriteln!(self.definition, "case {i}: {{");
                    uwriteln!(self.definition, "{code}");
                    if case.ty.is_some() {
                        uwriteln!(self.definition, "{tmp} = {case_class}({});", block_results[0]);
                    } else {
                        uwriteln!(self.definition, "{tmp} = const {case_class}();");
                    }
                    uwriteln!(self.definition, "}}");
                }
                uwriteln!(
                    self.definition,
                    "default: throw StateError('invalid variant discriminant for {variant_name}');"
                );
                uwriteln!(self.definition, "}}");

                results.push(tmp);
            }
            Instruction::HandleLower {
                handle: _,
                name: _,
                ty: _,
            } => {
                let value = operands.pop().unwrap();
                results.push(Rc::new(format!(
                    "{}.WasmI32.fromInt({value}._handle)",
                    self.dart_wasm_import()
                )));
            }
            Instruction::HandleLift { handle, ty: _, .. } => {
                let resource_id = match handle {
                    Handle::Own(id) | Handle::Borrow(id) => *id,
                };
                let value = operands.pop().unwrap();
                let resource_name = self.dart.named_type(resolve, resource_id);
                results.push(Rc::new(format!(
                    "{resource_name}._fromHandle({value}.toIntUnsigned())"
                )));
            }
            Instruction::DropHandle { ty: _ } => {
                // The Dart-side resource wrapper doesn't hold any native
                // resources of its own (the host owns the underlying
                // resource table entry), so there's nothing to release here
                // beyond letting the wrapper object become garbage.
                operands.pop().unwrap();
            }
            Instruction::ConstZero { tys } => {
                for ty in tys.iter() {
                    let zero = match ty {
                        WasmType::I32 | WasmType::Pointer | WasmType::PointerOrI64 => {
                            format!("{}.WasmI32.fromInt(0)", self.dart_wasm_import())
                        }
                        WasmType::I64 => format!("{}.WasmI64.fromInt(0)", self.dart_wasm_import()),
                        WasmType::F32 => {
                            format!("{}.WasmF32.fromDouble(0)", self.dart_wasm_import())
                        }
                        WasmType::F64 => {
                            format!("{}.WasmF64.fromDouble(0)", self.dart_wasm_import())
                        }
                        WasmType::Length => format!("{}.WasmI32.fromInt(0)", self.dart_wasm_import()),
                    };
                    results.push(Rc::new(zero));
                }
            }
            Instruction::Bitcasts { casts } => {
                let values = operands.split_off(operands.len() - casts.len());
                for (cast, value) in casts.iter().zip(&values) {
                    let converted = self.bitcast(cast, value);
                    results.push(Rc::new(converted));
                }
            }
            Instruction::IterElem { .. } => {
                // Resolved to a unique name by the enclosing `ListLower`, so
                // nested lists don't redeclare (and read) the same variable.
                results.push(Rc::new(ELEMENT_PLACEHOLDER.to_string()));
            }
            Instruction::IterBasePointer => {
                results.push(Rc::new("elementPtr".to_string()));
            }
            Instruction::Malloc { size, align, .. } => {
                let tmp = self.temporary_variable();
                uwrite!(self.definition, "final {tmp} = ");
                self.definition.imported_identifier(
                    self.dart,
                    KnownDartUri::PkgWasmComponents,
                    "mallocAligned",
                );
                uwrite!(self.definition, "(");
                self.definition
                    .imported_identifier(self.dart, KnownDartUri::DartWasm, "WasmI32");
                uwrite!(self.definition, ".fromInt({}), ", align.align_wasm32());
                self.definition
                    .imported_identifier(self.dart, KnownDartUri::DartWasm, "WasmI32");
                uwriteln!(self.definition, ".fromInt({}));", size.size_wasm32());
                results.push(tmp);
            }
            Instruction::ListLower { element, .. } => {
                self.options.use_memory = true;
                let (body, _, _) = self.blocks.pop().unwrap();
                let list = operands.pop().unwrap();

                let elem_size = self.size_align.size(element).size_wasm32();
                let elem_align = self.size_align.align(element).align_wasm32();

                let len = self.temporary_variable();
                let base = self.temporary_variable();
                let element_var = self.temporary_variable();
                let body = body.replace(ELEMENT_PLACEHOLDER, &element_var);
                uwriteln!(self.definition, "final {len} = {list}.length;");
                uwrite!(self.definition, "final {base} = ");
                self.definition.imported_identifier(
                    self.dart,
                    KnownDartUri::PkgWasmComponents,
                    "mallocAligned",
                );
                uwrite!(self.definition, "(");
                self.definition
                    .imported_identifier(self.dart, KnownDartUri::DartWasm, "WasmI32");
                uwrite!(self.definition, ".fromInt({elem_align}), ");
                self.definition
                    .imported_identifier(self.dart, KnownDartUri::DartWasm, "WasmI32");
                uwriteln!(self.definition, ".fromInt({elem_size} * {len}));");

                uwriteln!(self.definition, "for (var i = 0; i < {len}; i++) {{");
                uwriteln!(self.definition, "final {element_var} = {list}[i];");
                uwrite!(self.definition, "final elementPtr = ");
                self.definition
                    .imported_identifier(self.dart, KnownDartUri::DartWasm, "WasmI32");
                uwriteln!(
                    self.definition,
                    ".fromInt({base}.toIntUnsigned() + i * {elem_size});"
                );
                uwriteln!(self.definition, "{body}");
                uwriteln!(self.definition, "}}");

                let wasm_len = self.temporary_variable();
                let wasm = self.dart_wasm_import();
                uwriteln!(self.definition, "final {wasm_len} = {wasm}.WasmI32.fromInt({len});");

                if let FunctionMode::Imported(_) = self.mode {
                    // The caller owns the lowered list buffer until the call
                    // returns; element payloads (e.g. strings) register their
                    // own cleanups from within the loop body above.
                    self.needs_cleanup_list = true;
                    // Block-bodied closure: `dartFree` returns `WasmVoid`, a
                    // wasm value type that can't be boxed into a generic
                    // `void Function()` return, so discard it as a statement.
                    uwrite!(self.definition, "_cleanups.add(() {{ ");
                    self.definition.imported_identifier(
                        self.dart,
                        KnownDartUri::PkgWasmComponents,
                        "dartFree",
                    );
                    uwriteln!(
                        self.definition,
                        "({base}, {wasm}.WasmI32.fromInt({elem_size} * {len}), const {wasm}.WasmI32({elem_align})); }});"
                    );
                }

                results.push(base);
                results.push(wasm_len);
            }
            Instruction::ListLift { element, .. } => {
                self.options.use_memory = true;
                let (body, body_results, _) = self.blocks.pop().unwrap();
                let length = operands.pop().unwrap();
                let ptr = operands.pop().unwrap();
                let elem_size = self.size_align.size(element).size_wasm32();

                let tmp = self.temporary_variable();
                uwrite!(self.definition, "final {tmp} = <");
                self.definition.write_dart_type(self.dart, resolve, element);
                uwriteln!(self.definition, ">[];");
                uwriteln!(
                    self.definition,
                    "for (var i = 0; i < {length}.toIntUnsigned(); i++) {{"
                );
                uwrite!(self.definition, "final elementPtr = ");
                self.definition
                    .imported_identifier(self.dart, KnownDartUri::DartWasm, "WasmI32");
                uwriteln!(
                    self.definition,
                    ".fromInt({ptr}.toIntUnsigned() + i * {elem_size});"
                );
                uwriteln!(self.definition, "{body}");
                uwriteln!(self.definition, "{tmp}.add({});", body_results[0]);
                uwriteln!(self.definition, "}}");

                results.push(tmp);
            }
            Instruction::GuestDeallocate { size, align } => {
                let ptr = operands.pop().unwrap();
                self.definition.imported_identifier(
                    self.dart,
                    KnownDartUri::PkgWasmComponents,
                    "dartFree",
                );
                let wasm = self.dart_wasm_import();
                uwriteln!(
                    self.definition,
                    "({ptr}, const {wasm}.WasmI32({}), const {wasm}.WasmI32({}));",
                    size.size_wasm32(),
                    align.align_wasm32(),
                );
            }
            Instruction::GuestDeallocateList { element } => {
                let (body, _, _) = self.blocks.pop().unwrap();
                let length = operands.pop().unwrap();
                let ptr = operands.pop().unwrap();
                let elem_size = self.size_align.size(element).size_wasm32();
                let elem_align = self.size_align.align(element).align_wasm32();

                uwriteln!(
                    self.definition,
                    "for (var i = 0; i < {length}.toIntUnsigned(); i++) {{"
                );
                uwrite!(self.definition, "final elementPtr = ");
                self.definition
                    .imported_identifier(self.dart, KnownDartUri::DartWasm, "WasmI32");
                uwriteln!(
                    self.definition,
                    ".fromInt({ptr}.toIntUnsigned() + i * {elem_size});"
                );
                uwriteln!(self.definition, "{body}");
                uwriteln!(self.definition, "}}");

                // After the elements' own payloads are released, free the
                // list buffer itself.
                self.definition.imported_identifier(
                    self.dart,
                    KnownDartUri::PkgWasmComponents,
                    "dartFree",
                );
                let wasm = self.dart_wasm_import();
                uwriteln!(
                    self.definition,
                    "({ptr}, {wasm}.WasmI32.fromInt({length}.toIntUnsigned() * {elem_size}), const {wasm}.WasmI32({elem_align}));"
                );
            }
            Instruction::GuestDeallocateVariant { blocks } => {
                let mut case_blocks = (0..*blocks)
                    .map(|_| self.blocks.pop().unwrap())
                    .collect::<Vec<_>>();
                case_blocks.reverse();
                let discriminant = operands.pop().unwrap();

                uwriteln!(
                    self.definition,
                    "switch ({discriminant}.toIntUnsigned()) {{"
                );
                for (i, (code, _, _)) in case_blocks.iter().enumerate() {
                    uwriteln!(self.definition, "case {i}: {{\n{code}\n}}");
                }
                uwriteln!(self.definition, "}}");
            }
            Instruction::AsyncTaskReturn { name: _, params } => {
                let args = operands.split_off(operands.len() - params.len());

                let name = match &mut self.mode {
                    FunctionMode::Exported(exported) => {
                        *exported.async_return_params = Some(params.iter().cloned().collect());
                        self.options.task_return_import =
                            Some(exported.async_return_name.to_string());

                        exported.async_return_name
                    }
                    FunctionMode::ExportedFunc(exported) => {
                        *exported.async_return_params = Some(params.iter().cloned().collect());
                        self.options.task_return_import =
                            Some(exported.async_return_name.to_string());

                        exported.async_return_name
                    }
                    _ => panic!("AsyncTaskReturn only works in export mode"),
                };

                uwrite!(self.definition, "{name}(");
                for arg in args {
                    uwrite!(self.definition, "{arg},");
                }
                uwrite!(self.definition, ");");
            }
            Instruction::Flush { amt } => {
                let operands = operands.split_off(operands.len() - *amt);
                results.extend_from_slice(&operands);
            }
            _ => todo!("Instruction: {inst:?}"),
        }
    }

    fn return_pointer(&mut self, size: ArchitectureSize, align: Alignment) -> Self::Operand {
        let is_extra = self.allocated_return_value.is_some();
        assert!(
            !is_extra || matches!(self.mode, FunctionMode::Imported(_)),
            "only imports can allocate more than one return area"
        );

        let local = self.temporary_variable();
        uwrite!(&mut self.definition, "var {local} = ");
        self.definition.imported_identifier(
            self.dart,
            KnownDartUri::PkgWasmComponents,
            "mallocAligned",
        );
        uwrite!(&mut self.definition, "(const ");
        self.definition
            .imported_identifier(self.dart, KnownDartUri::DartWasm, "WasmI32");
        uwrite!(&mut self.definition, "({})", align.align_wasm32());
        uwrite!(&mut self.definition, ", const ");
        self.definition
            .imported_identifier(self.dart, KnownDartUri::DartWasm, "WasmI32");
        uwriteln!(&mut self.definition, "({}));", size.size_wasm32());
        if is_extra {
            self.extra_return_areas.push((local.clone(), size, align));
        } else {
            self.allocated_return_value = Some((size, align));
            self.return_area = Some(local.clone());
        }

        local
    }

    fn push_block(&mut self) {
        let prev = mem::take(&mut self.definition);
        self.block_storage.push(prev);
        self.payload_name_stack.push(None);
        self.cleanup_stack.push(String::new());
    }

    fn finish_block(&mut self, operands: &mut Vec<Self::Operand>) {
        let to_restore = self.block_storage.pop().unwrap();
        let mut def = mem::replace(&mut self.definition, to_restore);
        let payload_name = self.payload_name_stack.pop().unwrap();
        let cleanup = self.cleanup_stack.pop().unwrap();
        if !cleanup.is_empty() {
            let _ = write!(def, "{cleanup}");
        }
        self.blocks
            .push((def.take_code(), mem::take(operands), payload_name));
    }

    fn sizes(&self) -> &SizeAlign {
        self.size_align
    }

    fn is_list_canonical(&self, _resolve: &Resolve, _element: &Type) -> bool {
        false
    }
}
