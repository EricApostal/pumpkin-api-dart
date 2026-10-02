//! Standalone CLI for generating Dart component bindings from a directory
//! of WIT files, bypassing `dart:ffi` entirely.
//!
//! `wasm_tools witgen`'s normal `dart:ffi` path (`wit_bindgen_dart_gen`,
//! invoked from `pkg/wasm_tools/lib/src/wit_gen/generate.dart`) has a memory
//! safety bug in its FFI marshalling that only manifests with large inputs:
//! feeding it a real-world, multi-thousand-line WIT package (as opposed to
//! the tool's own test suite's few-line snippets) crashes non-deterministically
//! at different points on different runs -- the signature of undefined
//! behavior, not a logic bug (the same input drives the generator correctly,
//! every time, when called directly from Rust). This binary calls the exact
//! same generation code the FFI path does, just without a language boundary
//! in between, as a working way to actually use it until that bug is found.
//!
//! It also does real multi-file package merging via
//! `UnresolvedPackageGroup::parse_dir` + `Resolve::push_group`, which
//! `wasm_tools witgen`'s CLI doesn't support yet either (its `--input`
//! directory case is an unimplemented stub) and which
//! `generate_dart_bindings`'s per-file `push_str` loop can't do (each file
//! becomes its own standalone package that way, but WIT split across files
//! sharing one `package` declaration -- like `pumpkin-plugin-wit` -- needs
//! them merged).
//!
//! Usage: witgen_cli --input <dir> --world <name> --output <dart-file> --abi-output <json-file>

use std::path::PathBuf;

use wit_bindgen_dart::generate_dart_bindings_for_world;
use wit_bindgen_dart::wit_parser::Resolve;

struct Args {
    input: PathBuf,
    world: String,
    output: PathBuf,
    abi_output: PathBuf,
}

fn parse_args() -> anyhow::Result<Args> {
    let mut input = None;
    let mut world = None;
    let mut output = None;
    let mut abi_output = None;

    let mut args = std::env::args().skip(1);
    while let Some(flag) = args.next() {
        let mut value = || {
            args.next()
                .ok_or_else(|| anyhow::anyhow!("{flag} requires a value"))
        };
        match flag.as_str() {
            "--input" => input = Some(PathBuf::from(value()?)),
            "--world" => world = Some(value()?),
            "--output" => output = Some(PathBuf::from(value()?)),
            "--abi-output" => abi_output = Some(PathBuf::from(value()?)),
            other => anyhow::bail!("unknown argument: {other}"),
        }
    }

    Ok(Args {
        input: input.ok_or_else(|| anyhow::anyhow!("--input <dir> is required"))?,
        world: world.ok_or_else(|| anyhow::anyhow!("--world <name> is required"))?,
        output: output.ok_or_else(|| anyhow::anyhow!("--output <file> is required"))?,
        abi_output: abi_output
            .ok_or_else(|| anyhow::anyhow!("--abi-output <file> is required"))?,
    })
}

fn main() -> anyhow::Result<()> {
    let args = parse_args()?;

    // `push_dir` also loads the packages in `<input>/deps`.
    let mut resolve = Resolve::default();
    let (package_id, _) = resolve.push_dir(&args.input)?;
    let world = resolve.select_world(&[package_id], Some(&args.world))?;

    let (dart_source, abi_json) = generate_dart_bindings_for_world(&mut resolve, world)?;

    if let Some(parent) = args.output.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&args.output, dart_source)?;
    if let Some(parent) = args.abi_output.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&args.abi_output, abi_json)?;

    eprintln!(
        "Wrote {} and {}",
        args.output.display(),
        args.abi_output.display()
    );
    Ok(())
}
