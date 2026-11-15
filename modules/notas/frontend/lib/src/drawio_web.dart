import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

int _seq = 0;

/// draw.io autoalojado (Caddy lo sirve en /drawio/) incrustado con su protocolo postMessage.
class DrawioFrame extends StatefulWidget {
  final String xml;
  final bool readOnly;
  final void Function(String xml) onSave;
  const DrawioFrame({super.key, required this.xml, required this.onSave, this.readOnly = false});

  @override
  State<DrawioFrame> createState() => _DrawioFrameState();
}

class _DrawioFrameState extends State<DrawioFrame> {
  late final String _viewType = 'drawio-frame-${_seq++}';
  late final web.HTMLIFrameElement _iframe;
  late final JSFunction _listener = _onMessage.toJS;

  @override
  void initState() {
    super.initState();
    final params = ['embed=1', 'proto=json', 'spin=1', 'lang=es', 'saveAndExit=0', 'noExitBtn=1', if (widget.readOnly) 'chrome=0'].join('&');
    _iframe = web.HTMLIFrameElement()
      ..src = '/drawio/?$params'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _iframe);
    web.window.addEventListener('message', _listener);
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    super.dispose();
  }

  void _post(Map<String, dynamic> m) {
    _iframe.contentWindow?.postMessage(jsonEncode(m).toJS, web.window.location.origin.toJS);
  }

  void _onMessage(web.MessageEvent e) {
    if (e.origin != web.window.location.origin) return; // solo el draw.io de este mismo sitio
    final raw = e.data?.dartify();
    if (raw is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final ev = msg['event'];
    if (ev == 'init') {
      _post({'action': 'load', 'autosave': 1, 'xml': widget.xml});
    } else if (ev == 'autosave' || ev == 'save') {
      final xml = msg['xml'];
      if (xml is String && !widget.readOnly) widget.onSave(xml);
      if (ev == 'save') _post({'action': 'status', 'modified': false});
    }
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
