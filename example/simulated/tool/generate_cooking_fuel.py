#!/usr/bin/env python3
"""Regenerates `lib/src/manifest/cooking_fuel.g.dart` from the host's data.

26.3 made fuel a data component (`minecraft:cooking_fuel`), and a plugin cannot
read an item's *default* components, so the port carries the resolved table.
Both halves come from the host source, which is generated from the vanilla data:

  * `crates/pumpkin-data/src/data_component_impl/utility.rs` — the provider table
    (`cooking/time_coal` -> 1600, ...) that `CookingFuelImpl::get_burn_ticks`
    applies;
  * `crates/pumpkin-data/src/generated/item.rs` — every item's
    `CookingFuelImpl { burn_time, speed_multiplier }`.

usage: tool/generate_cooking_fuel.py [path/to/Pumpkin]
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / 'lib' / 'src' / 'manifest' / 'cooking_fuel.g.dart'
HOST = Path(sys.argv[1] if len(sys.argv) > 1 else '~/Documents/development/languages/rust/Pumpkin').expanduser()

utility = (HOST / 'crates/pumpkin-data/src/data_component_impl/utility.rs').read_text()
items = (HOST / 'crates/pumpkin-data/src/generated/item.rs').read_text()

# The provider -> ticks arms of `CookingFuelImpl::get_burn_ticks`.
providers = {}
start = utility.index('fn get_burn_ticks')
body = utility[start:utility.index('let factor', start)]
for match in re.finditer(r'((?:"cooking/[a-z_]+"\s*(?:\|\s*)?)+)=>\s*(\d+),', body):
    for name in re.findall(r'"(cooking/[a-z_]+)"', match.group(1)):
        providers[name] = int(match.group(2))

fuel = {}
unresolved = []
for block in re.split(r'\n    pub const [A-Z0-9_]+: Self = Self \{', items):
    key = re.search(r'registry_key: "([a-z0-9_]+)"', block)
    if not key or 'CookingFuel,' not in block:
        continue
    entry = re.search(r'CookingFuel,\s*&CookingFuelImpl \{(.*?)speed_multiplier', block, re.S)
    if not entry:
        unresolved.append(key.group(1))
        continue
    provider = re.search(r'Cow::Borrowed\("minecraft:(cooking/[a-z_]+)"\)', entry.group(1))
    if provider:
        ticks = providers.get(provider.group(1))
        if ticks is None:
            unresolved.append(f'{key.group(1)} ({provider.group(1)})')
            continue
    else:
        inline = re.search(r'IntProvider::Inline\((\d+)\)', entry.group(1))
        if not inline:
            unresolved.append(key.group(1))
            continue
        ticks = int(inline.group(1))
    fuel[f'minecraft:{key.group(1)}'] = ticks

if unresolved:
    sys.exit(f'unresolved fuel entries: {unresolved}')

lines = [
    '// The cooking-fuel value of every vanilla item, in ticks -- the table the host',
    '// resolves `minecraft:cooking_fuel` to (`CookingFuelImpl::get_burn_ticks`,',
    '// `crates/pumpkin-data/src/data_component_impl/utility.rs:112`).',
    '//',
    '// Why a table: 26.3 made fuel a data component, and the plugin API cannot read',
    "// it. `ItemStack.getComponents` answers with the stack's *patched* components",
    '// only (`crates/pumpkin-wasm-host-v0_2/src/item_stack.rs:701`), while an item\'s',
    '// fuel is a *default* component of the item definition, and',
    '// `DataComponentCodec.notReadByHost` lists `minecraft:cooking_fuel` as having no',
    "// reader. The numbers are the host's own, so they are what its furnaces burn;",
    '// `tool/generate_cooking_fuel.py` regenerates the table from the host\'s item',
    '// table and its provider table.',
    '//',
    '// Fidelity: an item registered by a plugin or a datapack has no entry here (the',
    '// Java reads the component and would burn it). Re-generate after a host data',
    '// update. The values are `get_burn_ticks(false)`.',
    'library;',
    '',
    '/// `minecraft:cooking_fuel` burn time, in ticks, by item key.',
    'const Map<String, int> vanillaCookingFuelTicks = {',
]
lines += [f"  '{key}': {fuel[key]}," for key in sorted(fuel)]
lines += [
    '};',
    '',
    '/// `CreateDataMaps.SUPERHEATED_BLAZE_BURNER_FUELS`: the items whose burn time',
    '/// counts as superheated fuel. The data map the Create jar ships',
    '/// (`data/create/data_maps/item/superheated_blaze_burner_fuels.json`), which',
    "/// Java's `getSuperheatedBurnTime` reads; anything else is 0.",
    'const Map<String, int> superheatedFuelTicks = {',
    "  'create:blaze_cake': 3200,",
    '};',
]
OUT.write_text('\n'.join(lines) + '\n')
print(f'{len(fuel)} items -> {OUT}')
