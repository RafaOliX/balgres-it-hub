import 'package:flutter/material.dart';

const kPinKinds = <(String, String, IconData)>[
  ('camara', 'Cámara', Icons.videocam),
  ('nvr', 'NVR / DVR', Icons.storage),
  ('switch', 'Switch', Icons.device_hub),
  ('ap', 'Access Point', Icons.wifi),
  ('rack', 'Rack', Icons.dns),
  ('router', 'Router', Icons.router),
  ('otro', 'Otro', Icons.place),
];

IconData pinIcon(String kind) => kPinKinds.where((k) => k.$1 == kind).firstOrNull?.$3 ?? Icons.place;
String pinLabel(String kind) => kPinKinds.where((k) => k.$1 == kind).firstOrNull?.$2 ?? kind;
