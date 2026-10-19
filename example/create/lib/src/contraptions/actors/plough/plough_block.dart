// `PloughBlock`: the mechanical plough block. It has no block entity; the fake player the actor
// uses to hoe the ground is defined here, like Java's `PloughFakePlayer`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../core/blocks.dart';
import '../attached_actor_block.dart';

/// `PloughBlock.PloughFakePlayer`: the name of the fake player that uses the hoe.
const String ploughFakePlayerName = 'Plough';

/// `PloughFakePlayer.PLOUGH_PROFILE` (the profile uuid is the offline uuid of the name).
const String ploughProfileUuid = '9e2faded-eeee-4ec2-c314-dad129ae971d';

/// Creates the fake player of a plough (`PloughFakePlayer`). The caller removes it when the actor
/// stops moving.
Player createPloughFakePlayer(World world) =>
    FakePlayers.create(world, ploughFakePlayerName);

/// `PloughBlock`.
CreateBlock buildPloughBlock() => buildAttachedActorBlock('mechanical_plough');
