import 'dart:async';

import 'package:balgres_it_contacts/balgres_it_contacts.dart' show apiError;
import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'drawio_stub.dart' if (dart.library.js_interop) 'drawio_web.dart';
import 'providers.dart';

/// Editor de un diagrama de la nota. Se guarda solo (autosave de draw.io, con pausa de 1,2 s).
class DiagramEditorPage extends ConsumerStatefulWidget {
  final int notaId;
  final int? diagramId;
  const DiagramEditorPage({super.key, required this.notaId, this.diagramId});
  @override
  ConsumerState<DiagramEditorPage> createState() => _DiagramEditorPageState();
}

class _DiagramEditorPageState extends ConsumerState<DiagramEditorPage> {
  late final NotasApi _api;
  final _title = TextEditingController(text: 'Diagrama');
  int? _did;
  String _xml = '';
  String? _pending;
  String? _pendingPreview;
  bool _loading = false, _busy = false;
  String _status = '';
  Timer? _debounce;

  bool get _canEdit => AuthSession.can('notas.editar');

  @override
  void initState() {
    super.initState();
    _api = ref.read(notasApiProvider);
    _did = widget.diagramId;
    if (_did != null) {
      _loading = true;
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_pending != null) _persist(); // no perder el último cambio al salir
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await _api.obtenerDiagrama(widget.notaId, _did!);
      if (!mounted) return;
      setState(() {
        _title.text = d.title;
        _xml = d.xml;
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: ${apiError(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Único _onXml. Los dos argumentos son requeridos; el título pasa `null`.
  void _onXml(String xml, String? preview) {
    if (!_canEdit) return;
    _xml = xml;
    _pending = xml;
    if (preview != null) _pendingPreview = preview;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), _persist);
  }

  Future<void> _persist() async {
    if (_busy) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 1), _persist);
      return;
    }

    final xml = _pending;
    if (xml == null) return;
    final preview = _pendingPreview;
    _pending = null;
    _pendingPreview = null;
    _busy = true;
    if (mounted) setState(() => _status = 'Guardando…');
    try {
      final title = _title.text.trim().isEmpty ? 'Diagrama' : _title.text.trim();
      if (_did == null) {
        _did = (await _api.crearDiagrama(widget.notaId, title, xml, preview: preview)).id;
      } else {
        await _api.actualizarDiagrama(widget.notaId, _did!, title, xml, preview: preview);
      }
      final t = TimeOfDay.now();
      if (mounted) setState(() => _status = 'Guardado ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
    } catch (e) {
      _pending ??= xml;
      _pendingPreview ??= preview;
      if (mounted) setState(() => _status = 'Error al guardar: ${apiError(e)}');
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
          width: 360,
          child: TextField(
            controller: _title,
            readOnly: !_canEdit,
            onSubmitted: (_) => _onXml(_xml, null),
            onEditingComplete: () => _onXml(_xml, null),
            decoration: const InputDecoration(hintText: 'Título del diagrama'),
          ),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(_status, style: TextStyle(fontSize: 12, color: c.muted)),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : DrawioFrame(xml: _xml, readOnly: !_canEdit, onSave: _onXml),
    );
  }
}