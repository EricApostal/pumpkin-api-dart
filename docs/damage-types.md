# Damage types

`damage-types.wit`: plugin defined damage types. Wrappers: `damage_types.dart`
(`DamageTypeSpec`, `DamageTypeRegistries`, `damageWith`). Permission:
`registry.damage-types`; registration closes when the server accepts
connections. Plugin types get ids `vanillaCount + n`.

```dart
DamageTypeRegistries.register(const DamageTypeSpec(
  key: 'my_plugin:crush',
  messageId: 'my_plugin.crush',            // death.attack.my_plugin.crush
  exhaustion: 0.1,
  effects: DamageEffects.hurt,
));
await player.damageWith('my_plugin:crush', 4);
await livingEntity.damageWith('my_plugin:crush', 4);
```

Clients need a resource pack for the death message translation. The vanilla
`DamageType` enum is still used by `damage(amount:, damageType:)`.
