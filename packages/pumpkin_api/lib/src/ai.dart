import 'bindings.g.dart';
import 'registry.dart';

/// A custom behavior for a mob, added with [MobAi.addGoal]. Goals with a lower
/// priority number are considered first, like Minecraft's own goals.
///
/// Override the callbacks you need. [entity] and [server] are only valid
/// during the callback.
abstract class AiGoal {
  /// Whether the goal should start running.
  bool canStart(Server server, Entity entity) => false;

  /// Whether the goal keeps running on the next tick.
  bool shouldContinue(Server server, Entity entity) => false;

  /// Called when the goal starts.
  void start(Server server, Entity entity) {}

  /// Called every tick while the goal is running.
  void tick(Server server, Entity entity) {}

  /// Called when the goal stops.
  void stop(Server server, Entity entity) {}
}

final aiGoals = HandlerRegistry<AiGoal>();

extension MobAi on Mob {
  /// Adds a custom [goal] to this mob.
  void addGoal(int priority, AiGoal goal) {
    addCustomAiGoal(priority: priority, goalId: aiGoals.add(goal));
  }
}
