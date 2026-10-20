import 'package:simulated/simulated.dart';
import 'package:test/test.dart';

void main() {
  group('SimConfig', () {
    test('the defaults match the Java config', () {
      const config = SimConfig.defaults;
      expect(config.server.assembly.maxBlocksMoved, 128000);
      expect(config.server.assembly.honeyGlueRange, 48);
      expect(config.server.assembly.mergingGlueRange, 4);
      expect(config.server.assembly.maxDisassemblyTicks, 20);
      expect(config.server.assembly.disassemblyDegreeTolerance, 4);
      expect(config.server.assembly.disallowMidAirDisassembly, isTrue);
      expect(config.server.assembly.primaryDisassembly, isFalse);
      expect(config.server.blocks.maxSwivelBearingSpeed, 96);
      expect(config.server.physics.swivelBearingStiffness, 1600);
      expect(config.server.equipment.maxPlungerLauncherRange, 64);
    });

    test('a parsed document overrides the defaults', () {
      final config = SimConfig.fromMap({
        'server': {
          'assembly': {'maxBlocksMoved': 64, 'disallowMidAirDisassembly': false},
          'physics': {'swivel_stiffness': 12.5},
        },
      });
      expect(config.server.assembly.maxBlocksMoved, 64);
      expect(config.server.assembly.disallowMidAirDisassembly, isFalse);
      expect(config.server.physics.swivelBearingStiffness, 12.5);
      // Untouched sections keep their defaults.
      expect(config.server.blocks.maxSwivelBearingSpeed, 96);
    });

    test('out of range values are clamped, unknown keys ignored', () {
      final config = SimConfig.fromMap({
        'server': {
          'assembly': {'maxDisassemblyTicks': 1, 'honeyGlueRange': -5},
          'unknown': {'x': 1},
        },
      });
      expect(config.server.assembly.maxDisassemblyTicks, 5);
      expect(config.server.assembly.honeyGlueRange, 1);
    });

    test('a malformed document falls back to the defaults', () {
      final config = SimConfig.fromMap({'server': 'nope'});
      expect(config.server.assembly.maxBlocksMoved, 128000);
    });

    test('the service can be loaded and read', () {
      final service = SimConfigService(SimConfig.defaults);
      expect(service.serverLoaded, isTrue);
      service.loadFromMap({
        'server': {
          'assembly': {'maxBlocksMoved': 7},
        },
      });
      expect(service.server.assembly.maxBlocksMoved, 7);
    });

    test('stress values prefer the configured entry', () {
      const stress = SimStressConfig(
        impacts: {'propeller_bearing': 4},
        configuredImpacts: {'propeller_bearing': 9},
      );
      expect(stress.impactOf('propeller_bearing'), 9);
      expect(stress.impactOf('sail'), 0);
    });
  });
}
