// The NeoForge declaration of the plugin, and the permission it needs.
//
// `lonsdaleiteDeclaration` builds types from `pumpkin_api`, which is wasm-only
// (`bindings.g.dart` uses `dart:wasm`), so this file holds the binding-free list
// (`declared_registries.dart`) against what the plugin registers and against the
// source that turns it into a declaration — the way `block_install_test.dart` reads
// the ids from the manifest instead of the host.
import 'dart:io';

import 'package:lonsdaleite/src/declared_registries.dart';
import 'package:lonsdaleite/src/manifest.g.dart';
import 'package:lonsdaleite/src/manifest.dart';
import 'package:test/test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  final manifest = Manifest.parse(lonsdaleiteManifestJson);
  final plugin = _read('lib/src/plugin.dart');
  final neoforge = _read('lib/src/neoforge.dart');
  final library = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.readAsStringSync())
      .join('\n');

  test('the two registries the plugin registers content into are declared', () {
    // `installManifestItems` registers into `minecraft:item` and
    // `installManifestBlock` into `minecraft:block`; both are host-numbered, so the
    // host sends them only when the declaration names them — and leaves them out of
    // the sync for *every* plugin when it does not.
    expect(manifest.items, isNotEmpty);
    expect(lonsdaleiteDeclaredRegistries, contains('minecraft:item'));
    expect(lonsdaleiteDeclaredRegistries, contains('minecraft:block'));
    expect(lonsdaleiteDeclaredRegistries.toSet().length, lonsdaleiteDeclaredRegistries.length);
  });

  test('the declaration is built from that list and carries it to the host', () {
    expect(neoforge, contains('for (final key in lonsdaleiteDeclaredRegistries)'));
    expect(neoforge, contains('NeoForgeRegistryAddition(key'));
    expect(plugin, contains('context.declareNeoForge(lonsdaleiteDeclaration(manifest))'));
    expect(
      plugin,
      contains('Permissions.neoforge'),
      reason: 'Context.declareNeoForge needs the neoforge permission',
    );
  });

  test('the plugin no longer runs the library handshake itself', () {
    // `pumpkin_neoforge`'s README: only one plugin per server may install a
    // `NeoForgeServer`, and the host owns the handshake now. Two of them would talk
    // to the same client — and the plugin's own sync could not vouch for anything to
    // the host's snapshot.
    expect(library, isNot(contains('installNeoForge(')));
    expect(library, isNot(contains('NeoForgeServer(')));
    expect(library, isNot(contains('NeoForgeNegotiation')));
  });
}