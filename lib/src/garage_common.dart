import 'dart:io' show InternetAddress;

final garageExternalIP = InternetAddress.loopbackIPv6;
const garagePort = 1416;
const garageEventType = 'event_type';
const garageResponse = 'response';
const garageEventDelay = 'delay';
const garageOpenEvent = 1;
const garageCloseEvent = 2;
const garageTriggerEvent = 3;
const garageIsOpenEvent = 4;
const garageCloseInEvent = 5;
const garageOpenForEvent = 6;
