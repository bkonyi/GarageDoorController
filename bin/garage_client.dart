import 'dart:async';
import 'dart:io';

import 'garage.dart';

main() async {
  print('Checking...');
  print('Door Open: ${await GarageDoorRemote.isOpen}');
  print('Done');
}
