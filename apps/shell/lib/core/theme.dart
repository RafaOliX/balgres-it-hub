import 'package:balgres_it_inventario/balgres_it_inventario.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light([Color? accent]) => buildSwissTheme(Brightness.light, accent);
  static ThemeData dark([Color? accent]) => buildSwissTheme(Brightness.dark, accent);
}
