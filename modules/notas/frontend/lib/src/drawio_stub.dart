import 'package:flutter/material.dart';

/// Android / escritorio: el editor draw.io se incrusta solo en Web.
class DrawioFrame extends StatelessWidget {
  final String xml;
  final bool readOnly;
  final void Function(String xml, String? preview) onSave;
  const DrawioFrame({super.key, required this.xml, required this.onSave, this.readOnly = false});

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('El editor de diagramas está disponible en la versión web. Ábrelo desde el navegador.', textAlign: TextAlign.center),
        ),
      );
}
