/// `MovingInteractionBehaviour`: what a block on a contraption does when a player interacts with
/// it or an entity collides with it. The base classes live in the contraptions module.
library;

export '../../contraptions/core/movement.dart'
    show
        CollidingEntity,
        InteractingPlayer,
        MovingInteractionBehaviour,
        MovingInteractions,
        SimpleBlockMovingInteraction;
