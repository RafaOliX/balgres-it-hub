import 'package:flutter/material.dart';

const kPinKinds = <(String, String, IconData)>[
  ('camara', 'Cámara', Icons.videocam),
  ('nvr', 'NVR / DVR', Icons.storage),
  ('switch', 'Switch', Icons.device_hub),
  ('ap', 'Access Point', Icons.wifi),
  ('rack', 'Rack', Icons.dns),
  ('router', 'Router', Icons.router),
  ('computadora', 'Computadora', Icons.computer),
  ('impresora', 'Impresora', Icons.print),
  ('monitor', 'Monitor', Icons.monitor),
  ('telefono', 'Teléfono IP', Icons.phone_in_talk),
  ('servidor', 'Servidor', Icons.memory),
  ('ups', 'UPS', Icons.battery_charging_full),
  ('otro', 'Otro', Icons.place),
];

IconData pinIcon(String kind) => kPinKinds.where((k) => k.$1 == kind).firstOrNull?.$3 ?? Icons.place;
String pinLabel(String kind) => kPinKinds.where((k) => k.$1 == kind).firstOrNull?.$2 ?? kind;
