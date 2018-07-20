import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'src/garage_common.dart';

// Since we're using a self-signed cert, we can't verify. Not ideal, but it is
// what it is.
bool _onBadCertificate(X509Certificate cert) => true;

abstract class GarageDoorRemote {
  static SecurityContext _context;

  static void initialize(SecurityContext context) => _context = context;

  static Future<bool> get isOpen async =>
      _sendRequest(garageIsOpenEvent, true);
  static Future<bool> openDoor() async => _sendRequest(garageOpenEvent);
  static Future<bool> closeDoor() async => _sendRequest(garageCloseEvent);
  static Future<bool> triggerDoor() async => _sendRequest(garageTriggerEvent);

  static Future<bool> _sendRequest(int type,
      [bool returnResponse = false]) async {
    try {
      final connection = await SecureSocket.connect(
          garageExternalIP, garagePort,
          context: context, onBadCertificate: _onBadCertificate);
      final request = {
        garageEventType: type,
      };
      connection.write(JSON.encode(request));
      if (returnResponse) {
        final completer = Completer<bool>();
        connection.listen((r) {
          final Map response = JSON.decode(UTF8.decode(r));
          completer.complete(response[garageResponse]);
        });
        connection.close();
        return completer.future;
      }
      connection.close();
      return true;
    } catch (e) {
      print('Client Error: $e');
      return false;
    }
  }
}
