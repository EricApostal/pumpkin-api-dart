// The advancement tree as data: the definitions are the mod's generated JSON, verbatim, and
// the registered copy rewrites exactly the criteria the host never fires.
//
// The reference is `simulated/common/src/generated/resources/data/simulated/advancement/*.json`
// and the builder that wrote them (`data/advancements/SimulatedAdvancement.java`): criterion
// "0" is the `_builtin` trigger, and the extra criteria are `whenIconCollected` /
// `whenIconPlaced` (`InventoryChangeTrigger` / `ItemUsedOnLocationTrigger`).
//
// Pure: no host imports (the installer file is the host half and is not covered here).
import 'dart:convert';

import 'package:simulated/src/content/advancements/sim_advancement_data.dart';
import 'package:test/test.dart';

/// `SimAdvancements.SIM_ADVANCEMENTS`, field for field and in declaration order.
const List<String> javaIds = [
  'root',
  'applied_kinematics',
  'opposite_attract',
  'a_calculated_connection',
  'you_spin_me_right_round',
  'learning_the_ropes',
  'stuck_together',
  'not_gonna_sugarcoat_it',
  'i_declare_thee',
  'measure_once_build_twice',
  'get_a_grip',
  'got_a_grip',
  'unpowered_steering',
  'steamless_engine',
  'that_should_do_for_now',
  'what_goes_down',
  'must_come_up',
  'rewind_time',
  'i_paid_for_the_whole_typewriter',
  'no_pressure',
  'can_we_get_much_higher',
  'convoluted_circumvolutions',
  'the_definition_of_up',
  'thataway',
  'far_from_home',
  'speed_is_key',
  'big_beam',
  'nearsighted',
  'my_eye',
  'call_of_the_void',
];

/// The five `awardedForFree` / `whenIconCollected` advancements: no `_builtin` criterion at
/// all, so `awardTo` cannot grant them (`SimulatedAdvancement.awardTo` throws).
const List<String> inventoryOnlyIds = [
  'root',
  'applied_kinematics',
  'stuck_together',
  'what_goes_down',
  'convoluted_circumvolutions',
];

Map<String, dynamic> _raw(String path) => jsonDecode(simAdvancementJson[path]!) as Map<String, dynamic>;

Map<String, dynamic> _registered(String path) =>
    jsonDecode(simAdvancementsRegisteredJson(path)) as Map<String, dynamic>;

Map<String, dynamic> _criteria(Map<String, dynamic> doc) => doc['criteria'] as Map<String, dynamic>;

void main() {
  group('the definitions', () {
    test('are the 30 advancements of SimAdvancements, in declaration order', () {
      expect(simAdvancementIds, javaIds);
      expect(simAdvancementJson.length, 30);
      expect(simAdvancementJson.keys, containsAll(javaIds));
    });

    test('decode, and carry only `_builtin` or the two host triggers', () {
      for (final path in simAdvancementIds) {
        final doc = _raw(path);
        expect(doc['criteria'], isNotNull, reason: path);
        expect(doc['display'], isNotNull, reason: path);
        expect(doc['requirements'], isNotNull, reason: path);
        for (final entry in _criteria(doc).entries) {
          final trigger = (entry.value as Map<String, dynamic>)['trigger'];
          expect(
            trigger,
            anyOf(
              simBuiltinTrigger(path),
              'minecraft:inventory_changed',
              'minecraft:placed_block',
            ),
            reason: '$path/${entry.key}',
          );
        }
      }
    });

    test('keep the vanilla triggers verbatim, so the rewrite is the registered copy only', () {
      expect(simAdvancementJson['root'], contains('"minecraft:inventory_changed"'));
      expect(simAdvancementJson['what_goes_down'], contains('"minecraft:inventory_changed"'));
      expect(simAdvancementJson['no_pressure'], contains('"minecraft:placed_block"'));
      expect(simAdvancementJson['nearsighted'], contains('"minecraft:placed_block"'));
      expect(simAdvancementJson['nearsighted'], contains('"blocks": "simulated:optical_sensor"'));
    });
  });

  group('the registered JSON', () {
    test('root: the awardedForFree criterion becomes the inventory trigger, group kept', () {
      final registered = _registered('root');
      final criterion = _criteria(registered)['1'] as Map<String, dynamic>;
      expect(criterion['trigger'], inventoryCheckTrigger);
      expect((criterion['conditions'] as Map<String, dynamic>)['plugin_tag'], 'root/1');
      expect(registered['requirements'], [
        ['1'],
      ]);
      // The rest of the definition (the root tab: background, icon, no toast) is untouched.
      expect(registered['display'], _raw('root')['display']);
      expect(registered['sends_telemetry_event'], isTrue);
    });

    test('applied_kinematics: the icon predicate becomes the inventory trigger', () {
      final registered = _registered('applied_kinematics');
      final criterion = _criteria(registered)['1'] as Map<String, dynamic>;
      expect(criterion['trigger'], inventoryCheckTrigger);
      expect((criterion['conditions'] as Map<String, dynamic>)['plugin_tag'], 'applied_kinematics/1');
      // The predicate itself is dropped: the plugin owns the item check.
      expect(criterion['conditions'], isNot(contains('items')));
      expect(registered['parent'], 'simulated:root');
      expect(registered['requirements'], [
        ['1'],
      ]);
    });

    test('no_pressure: the builtin stays, the placed criterion becomes the placed trigger', () {
      final registered = _registered('no_pressure');
      final criteria = _criteria(registered);
      final builtin = criteria['0'] as Map<String, dynamic>;
      expect(builtin['trigger'], 'simulated:no_pressure_builtin');
      expect(builtin['conditions'], 'simulated:no_pressure_builtin');
      final placed = criteria['1'] as Map<String, dynamic>;
      expect(placed['trigger'], placedBlockCheckTrigger);
      expect((placed['conditions'] as Map<String, dynamic>)['plugin_tag'], 'no_pressure/1');
      // Java's requirement groups are alternatives: both criteria are needed.
      expect(registered['requirements'], [
        ['0'],
        ['1'],
      ]);
    });

    test('a definition with neither trigger is registered byte for byte', () {
      for (final path in ['steamless_engine', 'must_come_up', 'call_of_the_void', 'opposite_attract']) {
        expect(simAdvancementsRegisteredJson(path), simAdvancementJson[path], reason: path);
      }
    });

    test('every id: same criterion keys, tags `<id>/<criterion>`, nothing else touched', () {
      for (final path in simAdvancementIds) {
        final raw = _raw(path);
        final registered = _registered(path);
        expect(_criteria(registered).keys, _criteria(raw).keys, reason: path);
        expect(registered['requirements'], raw['requirements'], reason: path);
        expect(registered['display'], raw['display'], reason: path);
        expect(registered['parent'], raw['parent'], reason: path);
        for (final entry in _criteria(registered).entries) {
          final before = _criteria(raw)[entry.key] as Map<String, dynamic>;
          final after = entry.value as Map<String, dynamic>;
          final trigger = before['trigger'];
          if (trigger == 'minecraft:inventory_changed') {
            expect(after['trigger'], inventoryCheckTrigger, reason: '$path/${entry.key}');
          } else if (trigger == 'minecraft:placed_block') {
            expect(after['trigger'], placedBlockCheckTrigger, reason: '$path/${entry.key}');
          } else {
            // A `_builtin` criterion, and the only case where the entry must be identical.
            expect(after, before, reason: '$path/${entry.key}');
            continue;
          }
          expect((after['conditions'] as Map<String, dynamic>)['plugin_tag'], '$path/${entry.key}');
        }
      }
    });

    test('rejects an id that is not in the tree', () {
      expect(() => simAdvancementsRegisteredJson('no_such_advancement'), throwsArgumentError);
    });
  });

  group('the criteria the plugin evaluates', () {
    test('are the five inventory and the five placed ones, in tree order', () {
      expect(
        simInventoryCriteria.map((c) => c.tag),
        ['root/1', 'applied_kinematics/1', 'stuck_together/1', 'what_goes_down/1', 'convoluted_circumvolutions/1'],
      );
      expect(
        simPlacedCriteria.map((c) => c.tag),
        ['no_pressure/1', 'the_definition_of_up/1', 'thataway/1', 'speed_is_key/1', 'nearsighted/1'],
      );
    });

    test('carry the predicate of the definition they replace', () {
      for (final c in simInventoryCriteria) {
        final raw = _criteria(_raw(c.advancementId))[c.criterion] as Map<String, dynamic>;
        final items = [
          for (final entry in (raw['conditions'] as Map<String, dynamic>?)?['items'] as List<dynamic>? ?? const [])
            (entry as Map<String, dynamic>)['items'],
        ];
        expect(c.anyOf, items, reason: c.tag);
      }
      for (final c in simPlacedCriteria) {
        final raw = _criteria(_raw(c.advancementId))[c.criterion] as Map<String, dynamic>;
        final location = (raw['conditions'] as Map<String, dynamic>)['location'] as Map<String, dynamic>;
        expect(location['type'], 'minecraft:match_block', reason: c.tag);
        expect(c.blocks, [location['blocks']], reason: c.tag);
      }
    });

    test('the inventory match: any for `awardedForFree`, the item otherwise', () {
      final root = simInventoryCriteria.first;
      expect(root.matches(const []), isTrue, reason: '`awardedForFree` has no item predicate');
      final assembler = simInventoryCriteria[1];
      expect(assembler.matches(const ['minecraft:stone']), isFalse);
      expect(assembler.matches(const ['minecraft:stone', 'simulated:physics_assembler']), isTrue);
    });

    test('the placed match is the block key', () {
      final altitude = simPlacedCriteria.first;
      expect(altitude.matches('simulated:altitude_sensor'), isTrue);
      expect(altitude.matches('simulated:optical_sensor'), isFalse);
    });
  });

  group('the triggers', () {
    test('are the 25 builtin ones plus the two plugin triggers', () {
      final triggers = simAdvancementTriggers();
      expect(triggers.length, 27);
      expect(triggers.toSet().length, triggers.length, reason: 'no duplicates: a trigger fires once');
      expect(triggers, contains(inventoryCheckTrigger));
      expect(triggers, contains(placedBlockCheckTrigger));
      expect(triggers.where((t) => t.endsWith('_builtin')).length, 25);
      expect(triggers, contains('simulated:steamless_engine_builtin'));
      expect(triggers, isNot(contains('simulated:root_builtin')));
    });

    test('the builtin discovery matches the criteria of the definitions', () {
      for (final path in simAdvancementIds) {
        expect(
          simHasBuiltinTrigger(path),
          !inventoryOnlyIds.contains(path),
          reason: path,
        );
      }
      for (final path in inventoryOnlyIds) {
        // The whole definition is one criterion, and it is the inventory one.
        expect(_criteria(_raw(path)).length, 1, reason: path);
      }
    });

    test('triggerOf takes the bare path and the prefixed id', () {
      expect(simBuiltinTrigger('unpowered_steering'), 'simulated:unpowered_steering_builtin');
      expect(simBuiltinTrigger('simulated:unpowered_steering'), 'simulated:unpowered_steering_builtin');
      expect(simAdvancementId('nearsighted'), 'simulated:nearsighted');
      expect(simAdvancementPath('simulated:nearsighted'), 'nearsighted');
    });
  });
}