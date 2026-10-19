/// `MovementBehaviour` (actors) and the contraption kinds, for other modules. The registry and
/// the `MovementContext` live in the contraptions module; this is the API path.
///
/// ```dart
/// MovementBehaviours.register('create:my_block', const MyActor());
/// ```
library;

export '../../contraptions/core/contraption_type.dart'
    show ContraptionType, ContraptionTypes;
export '../../contraptions/core/movement.dart'
    show
        ActorControlHooks,
        BlockRegistryOf,
        CollidingEntity,
        InteractingPlayer,
        MovementBehaviour,
        MovementBehaviours,
        MovementContext,
        MovingInteractionBehaviour,
        MovingInteractions,
        SimpleBlockMovingInteraction;
