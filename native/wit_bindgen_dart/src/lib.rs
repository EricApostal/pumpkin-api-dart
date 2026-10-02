use std::{ffi::c_char, mem::MaybeUninit, ptr::null, slice};

use wit_bindgen_core::{
    Files, WorldGenerator,
    wit_parser::{PackageId, Resolve},
};

pub use wit_bindgen_core::wit_parser;

use crate::bindgen::DartWorldGenerator;

mod abi_export;
mod bindgen;
mod dart_source;
mod functions;

pub(crate) fn debug_checkpoint(msg: &str) {
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open("/tmp/wit_bindgen_dart_debug.log")
    {
        let _ = writeln!(f, "CHECKPOINT {msg}");
        let _ = f.sync_all();
    }
}

#[repr(C)]
pub struct GenerateDartOptions {
    pub files: *const ImportFile,
    pub file_count: usize,
    pub main: *const u8,
    pub main_length: usize,
}

#[repr(C)]
pub struct ImportFile {
    pub contents: *const u8,
    pub contents_len: usize,
    pub path: *const u8,
    pub path_len: usize,
    pub is_main: c_char,
}

#[repr(C)]
pub struct ExportResult {
    pub output: *const u8,
    pub output_len: usize,
    pub output_capacity: usize,
    pub abi: *const u8,
    pub abi_len: usize,
    pub abi_capacity: usize,
    pub is_error: c_char,
}

#[unsafe(no_mangle)]
pub extern "C" fn wit_bindgen_dart_gen(
    options: &GenerateDartOptions,
    result: &mut MaybeUninit<ExportResult>,
) {
    debug_checkpoint("wit_bindgen_dart_gen entry");
    let (dart, abi) = match wit_bindgen_dart_internal(options) {
        Ok((dart, abi)) => (dart, abi),
        Err(e) => {
            let e = format!("{e:?}");
            let (output, output_len, output_capacity) = String::into_raw_parts(e);

            result.write(ExportResult {
                output,
                output_len,
                output_capacity,
                abi: null(),
                abi_len: 0,
                abi_capacity: 0,
                is_error: 1,
            });
            return;
        }
    };

    let (output, output_len, output_capacity) = String::into_raw_parts(dart);
    let (abi, abi_len, abi_capacity) = String::into_raw_parts(abi);

    result.write(ExportResult {
        output,
        output_len,
        output_capacity,
        abi,
        abi_len,
        abi_capacity,
        is_error: 0,
    });
}

#[unsafe(no_mangle)]
pub extern "C" fn wit_bindgen_dart_free(options: &ExportResult) {
    drop(unsafe {
        String::from_raw_parts(
            options.output.cast_mut(),
            options.output_len,
            options.output_capacity,
        )
    });
    if !options.abi.is_null() {
        drop(unsafe {
            String::from_raw_parts(
                options.abi.cast_mut(),
                options.abi_len,
                options.abi_capacity,
            )
        });
    }
}

fn wit_bindgen_dart_internal(options: &GenerateDartOptions) -> anyhow::Result<(String, String)> {
    let world = if options.main.is_null() {
        None
    } else {
        Some(
            unsafe {
                str::from_utf8_unchecked(slice::from_raw_parts(options.main, options.main_length))
            }
            .to_string(),
        )
    };
    let input_files = unsafe { slice::from_raw_parts(options.files, options.file_count) };

    let files: Vec<GenerateInputFile> = input_files
        .iter()
        .map(|file| GenerateInputFile {
            path: unsafe {
                str::from_utf8_unchecked(slice::from_raw_parts(file.path, file.path_len))
            }
            .to_string(),
            contents: unsafe {
                str::from_utf8_unchecked(slice::from_raw_parts(file.contents, file.contents_len))
            }
            .to_string(),
            is_main: file.is_main != 0,
        })
        .collect();

    generate_dart_bindings(files, world)
}

/// A single WIT source file to feed into generation: its (virtual) path,
/// contents, and whether it's the file whose `world` should be used as the
/// entry point.
pub struct GenerateInputFile {
    pub path: String,
    pub contents: String,
    pub is_main: bool,
}

/// The core, safe generation entry point: turns a set of WIT source files
/// into generated Dart source plus a JSON-encoded component ABI. Both the
/// `extern "C"` FFI entry point (`wit_bindgen_dart_gen`, used by
/// `wasm_tools`' `dart:ffi` binding) and the standalone `witgen_cli` binary
/// (a `dart:ffi`-free escape hatch -- see its module doc for why one exists)
/// call into this.
pub fn generate_dart_bindings(
    files: Vec<GenerateInputFile>,
    main_world: Option<String>,
) -> anyhow::Result<(String, String)> {
    let mut resolve = Resolve::default();
    let mut main: Vec<PackageId> = vec![];

    for file in &files {
        debug_checkpoint(&format!(
            "push_str: {} ({} bytes)",
            file.path,
            file.contents.len()
        ));
        // Note: each file is pushed as its own standalone package, since
        // that's what the individual-file-contents shape the FFI boundary
        // hands us supports. WIT source that's split across multiple files
        // sharing one `package` declaration (as `pumpkin-plugin-wit` is)
        // needs `generate_dart_bindings_for_resolve` with a `Resolve` built
        // via `UnresolvedPackageGroup::parse_dir`/`push_group` instead --
        // see `witgen_cli`.
        let package_id = resolve.push_str(&file.path, &file.contents)?;
        debug_checkpoint(&format!("push_str done: {}", file.path));
        if file.is_main {
            main.push(package_id);
        }
    }

    debug_checkpoint("select_world start");
    let world = resolve.select_world(&main, main_world.as_deref())?;
    generate_dart_bindings_for_world(&mut resolve, world)
}

/// Lower-level entry point for callers that already have a fully-populated
/// `Resolve` and a selected world -- e.g. `witgen_cli`, which builds its
/// `Resolve` via `UnresolvedPackageGroup::parse_dir` + `Resolve::push_group`
/// to get correct multi-file package merging (files sharing one `package`
/// declaration), something the per-file `push_str` loop in
/// `generate_dart_bindings` can't do.
pub fn generate_dart_bindings_for_world(
    resolve: &mut Resolve,
    world: wit_bindgen_core::wit_parser::WorldId,
) -> anyhow::Result<(String, String)> {
    debug_checkpoint("generate start");
    let mut generator = DartWorldGenerator::default();
    let mut out_files = Files::default();
    generator.generate(resolve, world, &mut out_files)?;
    debug_checkpoint("generate done");

    Ok((
        generator.main.to_string(),
        generator.serialize_abi(resolve)?,
    ))
}

#[cfg(test)]
mod test {
    use wit_bindgen_core::{Files, WorldGenerator, wit_parser::Resolve};

    use crate::bindgen::DartWorldGenerator;

    fn print_definitions(wit: &str) -> anyhow::Result<()> {
        print_definitions_with_world(wit, "root")
    }

    fn print_definitions_with_world(wit: &str, world_name: &str) -> anyhow::Result<()> {
        let mut resolve = Resolve::default();
        let package = resolve.push_str("test.wit", wit)?;

        let world = resolve.select_world(&[package], Some(world_name))?;

        let mut generator = DartWorldGenerator::default();
        let mut files = Files::default();
        generator.generate(&mut resolve, world, &mut files)?;

        print!("{}", generator.main);
        Ok(())
    }

    #[test]
    fn playground() {
        print_definitions(
            "
package root:component;

world root {
  import dart:components/print@0.0.1;

  export wasi:cli/run@0.2.12;
}
package dart:components@0.0.1 {
  /// Component that can print stuff.
  interface print {
    /// Prints a message to stdout.
    print: func(line: string);
  }
}

package wasi:cli@0.2.12 {
  interface run {
    run: func() -> result;
  }
}
",
        )
        .expect("Could not generate definitions")
    }

    #[test]
    fn async_export() {
        print_definitions(
            "
package root:component;

world root {
  export wasi:cli/run@0.3.0;
}

package wasi:cli@0.3.0 {
  interface run {
    run: async func() -> result;
  }
}
",
        )
        .expect("Could not generate definitions")
    }

    #[test]
    fn post_return() {
        print_definitions(
            "
package demo:component;

world root {
  export greeting;
}

interface greeting {
  generate-greeting: func() -> string;
}
",
        )
        .expect("Could not generate definitions")
    }

    #[test]
    fn return_struct() {
        print_definitions(
            "
package demo:component;

world root {
  import greeting;
}

interface greeting {
  record instant {
        seconds: s64,
        nanoseconds: u32,
    }

 now: func() -> instant;
}
",
        )
        .expect("Could not generate definitions")
    }

    #[test]
    fn pumpkin_combined() {
        let wit = std::fs::read_to_string(
            "/private/tmp/claude-501/-Users-eric-Documents-development-languages-rust-Pumpkin/c72af1c8-05cc-499c-896b-3b0190b829a4/scratchpad/pumpkin-witgen-test/combined.wit",
        )
        .expect("read combined.wit");
        print_definitions_with_world(&wit, "plugin").expect("Could not generate definitions")
    }

    #[test]
    fn pumpkin_combined_full_path() {
        let path = "/private/tmp/claude-501/-Users-eric-Documents-development-languages-rust-Pumpkin/c72af1c8-05cc-499c-896b-3b0190b829a4/scratchpad/pumpkin-witgen-test/combined.wit";
        let wit = std::fs::read_to_string(path).expect("read combined.wit");

        let mut resolve = Resolve::default();
        let package = resolve.push_str(path, &wit).expect("push_str");
        let world = resolve
            .select_world(&[package], Some("plugin"))
            .expect("select_world");

        let mut generator = DartWorldGenerator::default();
        let mut files = Files::default();
        generator
            .generate(&mut resolve, world, &mut files)
            .expect("generate");
        print!("{}", generator.main);
    }
}
