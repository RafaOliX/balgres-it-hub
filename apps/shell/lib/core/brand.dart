import 'package:balgres_it_inventario/balgres_it_inventario.dart';
import 'package:flutter/material.dart';

/// Logo de Balgres. Archivos: assets/brand/logo.png (+ opcional logo_dark.png).
/// Si no existen, muestra una "B" de respaldo.
class BrandLogo extends StatelessWidget {
  final double height;
  const BrandLogo({super.key, this.height = 40});

  Widget _mark(BuildContext context) => Container(
        width: height,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: kBrandNavy, borderRadius: BorderRadius.circular(height * 0.28)),
        child: Text('B', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: height * 0.5)),
      );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget normal() => Image.asset('assets/brand/logo.png', height: height, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _mark(context));
    if (!dark) return normal();
    return Image.asset(
      'assets/brand/logo_dark.png',
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: normal(),
      ),
    );
  }
}
