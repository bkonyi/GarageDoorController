import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rpi_gpio/rpi_gpio.dart';
import 'package:rpi_gpio/gpio.dart';
import 'package:rpi_gpio/gpio_pins.dart';
import 'package:rpi_gpio/wiringpi_gpio.dart';

import 'src/garage_common.dart';

String localFile(path) => Platform.script.resolve(path).toFilePath();
final _serverContext = SecurityContext()
  ..useCertificateChain(localFile('domain.crt'))
  ..usePrivateKey(localFile('domain.key'))
  ..setTrustedCertificates(localFile('client.crt'));

enum GarageDoorTriggerType {
  Open,
  Close,
  Trigger,
  IsOpenQuery,
  CloseIn,
  OpenFor,
}

class GarageDoorTrigger {
  final int _type;
  final DateTime time;
  final int delay;
  final SecureSocket _socket;

  GarageDoorTriggerType get type {
    switch (_type) {
      case garageOpenEvent:
        return GarageDoorTriggerType.Open;
      case garageCloseEvent:
        return GarageDoorTriggerType.Close;
      case garageTriggerEvent:
        return GarageDoorTriggerType.Trigger;
      case garageIsOpenEvent:
        return GarageDoorTriggerType.IsOpenQuery;
      case garageCloseInEvent:
        return GarageDoorTriggerType.CloseIn;
      case garageOpenForEvent:
        return GarageDoorTriggerType.OpenFor;
      default:
        throw 'Unexpected GarageDoorTriggerType: $_type';
    }
  }

  Future<void> complete() => _socket.close();

  Future<void> response(r) {
    final message = <String, dynamic>{
      garageResponse: r,
    };
    _socket.write(JSON.encode(message));
  }

  GarageDoorTrigger._(this._type, this._socket, this.delay)
      : time = DateTime.now();
}

class GarageDoorRemoteHandler {
  static final _controller = StreamController<GarageDoorTrigger>.broadcast();
  static Stream<GarageDoorTrigger> get remoteRequests => _controller.stream;

  static _onErrorDefault(e) => null;

  static StreamSubscription listen(void f(GarageDoorTrigger t),
          {Function onError: _onErrorDefault}) =>
      remoteRequests.listen(f, onError: onError);

  static Future startListening() => SecureServerSocket.bind(
          InternetAddress.anyIPv6, garagePort, _serverContext,
          requireClientCertificate: true)
      .then((server) => server.listen(_onConnection));

  static void _onConnection(SecureSocket s) => s
          .transform(UTF8.decoder)
          .transform(JSON.decoder)
          .listen((dynamic requestObj) {
        assert(requestObj is Map);
        Map request = requestObj;
        print('Request: $request');
        assert(request.containsKey(garageEventType));
        _controller.add(GarageDoorTrigger._(
            request[garageEventType], s, request[garageEventDelay]));
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

  static Future<void> closeDoorIn(int seconds) =>
      _delay(seconds * 1000).then((void v) => closeDoor());

  static Future<void> openDoorFor(int seconds) => openDoor().then((void v) {
        _delay(seconds * 1000);
      }).then((void _) => closeDoor());

  static Future<void> _delay(int ms) async =>
      await Future.delayed(Duration(milliseconds: ms));
}
