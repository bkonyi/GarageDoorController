import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:garage_door_controller/garage.dart';

void remoteEventHandler(GarageDoorTrigger t) {
  switch (t.type) {
    case GarageDoorTriggerType.Open:
      GarageDoor.openDoor();
      break;
    case GarageDoorTriggerType.Close:
      GarageDoor.closeDoor();
      break;
    case GarageDoorTriggerType.Trigger:
      GarageDoor.triggerDoor();
      break;
    case GarageDoorTriggerType.IsOpenQuery:
      t.response(GarageDoor.isOpen);
      break;
    case GarageDoorTriggerType.CloseIn:
      assert(t.delay != null);
      GarageDoor.closeDoorIn(t.delay);
      break;
    case GarageDoorTriggerType.OpenFor:
      assert(t.delay != null);
      GarageDoor.openDoorFor(t.delay);
      break;
    default:
      throw UnimplementedError();
  }
  t.complete();
}

main() async {
  GarageDoor.initialize();
  await GarageDoorRemoteHandler.startListening();
  GarageDoorRemoteHandler.listen(remoteEventHandler);
  print('Garage door server running...');
}
