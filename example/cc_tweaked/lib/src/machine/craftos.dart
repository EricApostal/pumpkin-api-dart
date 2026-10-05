// Where a computer's operating system comes from: the `rom/` tree and
// `bios.lua` of the CC: Tweaked mod jar, which the server owner puts into the
// plugin's data folder. The ROM is licensed separately from this plugin
// (the mod ships it under the ComputerCraft Public License), so it is read
// from the owner's jar and never redistributed.
import 'dart:typed_data';

import 'fallback_bios.dart';
import 'filesystem.dart';
import 'mounts.dart';
import 'zip.dart';

/// The path of the BIOS inside the jar.
const String biosEntry = 'data/computercraft/lua/bios.lua';

/// The directory that becomes `/rom` inside the jar.
const String romPrefix = 'data/computercraft/lua/rom/';

/// A BIOS and a ROM to boot computers with.
final class CraftOsImage {
  /// The Lua source of `bios.lua`.
  final String bios;

  /// The read-only `/rom` mount, or null for the fallback BIOS.
  final Mount? rom;

  /// Where the image came from, for logs and `/cc status`.
  final String source;

  /// The mod version the jar declares (`neoforge.mods.toml`), if found. It is
  /// also the version string CC: Tweaked's network channels are registered
  /// with.
  final String? modVersion;

  const CraftOsImage({
    required this.bios,
    required this.rom,
    required this.source,
    this.modVersion,
  });

  /// The built-in minimal BIOS, without a ROM.
  factory CraftOsImage.fallback() => const CraftOsImage(
    bios: fallbackBios,
    rom: null,
    source: 'built-in fallback BIOS',
  );

  /// Reads the BIOS and the ROM from the bytes of a CC: Tweaked jar. Throws
  /// [ZipException] or [FileSystemException] if it is not one.
  factory CraftOsImage.fromJar(Uint8List jar, String name) {
    final archive = ZipArchive.parse(jar);
    final bios = archive.find(biosEntry);
    if (bios == null) {
      throw FileSystemException('$name has no $biosEntry: not a CC: Tweaked jar');
    }
    final rom = ArchiveMount(archive, romPrefix);
    if (rom.fileCount == 0) {
      throw FileSystemException('$name has no ${romPrefix}files: not a CC: Tweaked jar');
    }
    return CraftOsImage(
      bios: String.fromCharCodes(bios.read()),
      rom: rom,
      source: '$name (${rom.fileCount} ROM files)',
      modVersion: _readVersion(archive),
    );
  }

  static String? _readVersion(ZipArchive archive) {
    final toml = archive.find('META-INF/neoforge.mods.toml');
    if (toml == null) return null;
    final match = RegExp(
      r'^version\s*=\s*"([^"$]+)"',
      multiLine: true,
    ).firstMatch(String.fromCharCodes(toml.read()));
    return match?.group(1);
  }
}
