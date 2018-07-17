import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rpi_gpio/rpi_gpio.dart';
import 'package:rpi_gpio/gpio.dart';
import 'package:rpi_gpio/gpio_pins.dart';
import 'package:rpi_gpio/wiringpi_gpio.dart';

String localFile(path) => Platform.script.resolve(path).toFilePath();
final _serverContext = SecurityContext()
  ..useCertificateChain(localFile('domain.crt'))
  ..usePrivateKey(localFile('domain.key'))
  ..setTrustedCertificates(localFile('client.crt'));

final clientContext = SecurityContext()
  ..useCertificateChain(localFile('client.crt'))
  ..usePrivateKey(localFile('client.key'))
  ..setTrustedCertificates(localFile('domain.crt'));

// Since we're using a self-signed cert, we can't verify. Not ideal, but it is
// what it is.
bool _onBadCertificate(X509Certificate cert) => true;

final _garageExternalIP = InternetAddress.loopbackIPv6;
const _garagePort = 1416;
const _garageEventType = 'event_type';
const _garageResponse = 'response';
const _garageOpenEvent = 1;
const _garageCloseEvent = 2;
const _garageTriggerEvent = 3;
const _garageIsOpenEvent = 4;

enum GarageDoorTriggerType {
  Open,
  Close,
  Trigger,
  IsOpenQuery,
}

class GarageDoorTrigger {
  final int _type;
  final DateTime time;
  final SecureSocket _socket;

  GarageDoorTriggerType get type {
    switch (_type) {
      case _garageOpenEvent:
        return GarageDoorTriggerType.Open;
      case _garageCloseEvent:
        return GarageDoorTriggerType.Close;
      case _garageTriggerEvent:
        return GarageDoorTriggerType.Trigger;
      case _garageIsOpenEvent:
        return GarageDoorTriggerType.IsOpenQuery;
      default:
        throw 'Unexpected GarageDoorTriggerType: $_type';
    }
  }

  Future<void> complete() => _socket.close();

  Future<void> response(r) {
    final message = <String, dynamic>{
      _garageResponse: r,
    };
    return _socket.write(JSON.encode(message));
  }

  GarageDoorTrigger._(this._type, this._socket) : time = DateTime.now();
}

class GarageDoorRemote {
  static Future<bool> get isOpen async =>
      _sendRequest(_garageIsOpenEvent, true);
  static Future<bool> openDoor() async => _sendRequest(_garageOpenEvent);
  static Future<bool> closeDoor() async => _sendRequest(_garageCloseEvent);
  static Future<bool> triggerDoor() async => _sendRequest(_garageTriggerEvent);

  static Future<bool> _sendRequest(int type,
      [bool returnResponse = false]) async {
    try {
      final connection = await SecureSocket.connect(
          _garageExternalIP, _garagePort,
          context: clientContext, onBadCertificate: _onBadCertificate);
      final request = {
        _garageEventType: type,
      };
      connection.write(JSON.encode(request));
      if (returnResponse) {
        final completer = Completer<bool>();
        connection.listen((r) {
          final Map response = JSON.decode(UTF8.decode(r));
          completer.complete(response[_garageResponse]);
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

class GarageDoorRemoteHandler {
  static final _controller = StreamController<GarageDoorTrigger>.broadcast();
  static Stream<GarageDoorTrigger> get remoteRequests => _controller.stream;

  static StreamSubscription listen(void f(GarageDoorTrigger t)) =>
      remoteRequests.listen(f);

  static Future startListening() => SecureServerSocket.bind(
          InternetAddress.loopbackIPv6, _garagePort, _serverContext,
          requireClientCertificate: true)
      .then((server) => server.listen(_onConnection));

  static void _onConnection(SecureSocket s) => s
          .transform(UTF8.decoder)
          .transform(JSON.decoder)
          .listen((dynamic requestObj) {
        assert(requestObj is Map);
        Map request = requestObj;
        print('Request: $request');
        assert(request.containsKey(_garageEventType));
        _controller.add(GarageDoorTrigger._(request[_garageEventType], s));
      });
}

class GarageDoor {
  static const _kOpenerPin = 7;
  static const _kProximityPin = 0;
  static const _kOpenerTriggerDelayMs = 300;
  static final _openerPin = pin(_kOpenerPin, Mode.output);
  static final _proximityPin = pin(_kProximityPin, Mode.input);
  static bool _initialized = false;
  static bool _isOpen = false;

  static bool get isOpen => _isOpen;

  static void initialize() {
    assert(isRaspberryPi);
    if (_initialized) {
      return;
    }
    Pin.gpio = new WiringPiGPIO();
    _isOpen = _proximityPin.value;
    _proximityPin.events().listen((PinEvent e) {
      assert(e.pin == _kProximityPin);
      _isOpen = e.value;
    });
  }

  static Future<void> triggerDoor() async {
    assert(isRaspberryPi);
    assert(_initialized);
    _openerPin.value = true;
    await _delay(_kOpenerTriggerDelayMs);
    _openerPin.value = false;
  }

  static Future<void> closeDoor() {
    assert(isRaspberryPi);
    assert(_initialized);
    if (_isOpen) {
      return triggerDoor();
    }
  }

  static Future<void> openDoor() {
    assert(isRaspberryPi);
    assert(_initialized);
    if (!_isOpen) {
      return triggerDoor();
    }
  }

  static Future<void> _delay(int ms) async =>
      await Future.delayed(Duration(milliseconds: ms));
}
