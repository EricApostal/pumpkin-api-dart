// Checks the host applies to `shape-rules` and placement rules that
// `BlockDefinition.validate()` does not: the host stops at the first bad block,
// so running these over the whole registry first names every bad definition in
// one server start instead of one per run.
import 'package:pumpkin_api/pumpkin_api.dart';

import 'blocks.dart';

/// The host's `MAX_SHAPE_RULES` (`crates/pumpkin-data/src/block_registry.rs`).
const int maxShapeRules = 64;

/// The host's `MAX_PLACEMENT_RULES`.
const int maxPlacementRules = 64;

/// The problems the host would report for the shape rules of [definition].
List<String> checkShapeRules(BlockDefinition definition) {
  final issues = <String>[];
  if (definition.shapeRules.length > maxShapeRules) {
    issues.add(
      'more than $maxShapeRules shape rules (${definition.shapeRules.length}).',
    );
  }
  final byName = {for (final p in definition.properties) p.name: p};
  for (final rule in definition.shapeRules) {
    for (final entry in rule.when.entries) {
      final property = byName[entry.key];
      if (property == null) {
        issues.add("a shape rule names unknown property '${entry.key}'.");
      } else if (property.valueIndex(entry.value) == null) {
        issues.add(
          "'${entry.value}' is not a value of property '${entry.key}' in a shape rule.",
        );
      }
    }
    for (final (what, shape) in [
      ('collision', rule.collisionShape),
      ('selection', rule.selectionShape),
    ]) {
      if (shape is BoxesShape &&
          shape.boxes.length > BlockRegistryChecks.maxBoxes) {
        issues.add(
          'a shape rule $what shape has more than ${BlockRegistryChecks.maxBoxes} boxes.',
        );
      }
    }
  }
  return issues;
}

/// The problems the host would report for the placement rules of [block].
List<String> checkPlacementRules(CreateBlock block) {
  final issues = <String>[];
  if (block.placement.length > maxPlacementRules) {
    issues.add(
      'more than $maxPlacementRules placement rules (${block.placement.length}).',
    );
  }
  final byName = {for (final p in block.properties) p.name: p};
  for (final rule in block.placement) {
    final property = byName[rule.property];
    if (property == null) {
      issues.add("a placement rule names unknown property '${rule.property}'.");
      continue;
    }
    final value = rule.constantValue;
    if (value != null && property.valueIndex(value) == null) {
      issues.add(
        "'$value' is not a value of property '${rule.property}' in a placement rule.",
      );
    }
  }
  return issues;
}
