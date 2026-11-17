import 'package:balgres_it_contacts/balgres_it_contacts.dart' show apiError;
import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models.dart';
import 'providers.dart';
import 'tickets_page.dart';

const _maxFileMb = 50; // debe coincidir con TICKETS_MAX_MB del backend

String _when(DateTime d) => d.toString().substring(0, 16);
String _size(int b) => b < 1024 ? '$b B' : (b < 1048576 ? '${(b / 1024).toStringAsFixed(0)} KB' : '${(b / 1048576).toStringAsFixed(1)} MB');

class TicketDetailPage extends ConsumerStatefulWidget {
  final int id;
  const TicketDetailPage({super.key, required this.id});
  @override
  ConsumerState<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends ConsumerState<TicketDetailPage> {
  Ticket? _t;
  bool _loading = true, _sending = false;
  String? _error;
  final _comment = TextEditingController();

  bool get _canEdit => AuthSession.can('tickets.editar');
  bool get _canDelete => AuthSession.can('tickets.eliminar');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _refreshLists() {
    ref.invalidate(ticketsProvider);
    ref.invalidate(ticketsResumenProvider);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final t = await ref.read(ticketsApiProvider).obtener(widget.id);
      if (mounted) setState(() {
        _t = t;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _patch(Map<String, dynamic> o) async {
    try {
      final t = await ref.read(ticketsApiProvider).actualizar(widget.id, _t!.toBody(o));
      if (mounted) setState(() => _t = t);
      _refreshLists();
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _assign() async {
    List<TicketUser> users;
    try {
      users = await ref.read(ticketsUsersProvider.future);
    } catch (e) {
      _snack('Error: ${apiError(e)}');
      return;
    }
    if (!mounted) return;
    TicketUser? sel = users.where((u) => u.username == _t!.assignee).firstOrNull;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => AlertDialog(
          title: const Text('Asignar responsable'),
          content: SizedBox(width: 400, child: SearchSelect<TicketUser>(label: 'Responsable', value: sel, options: users, display: (u) => u.display, onChanged: (u) => setM(() => sel = u))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok == true) await _patch({'assignee': sel?.username});
  }

  Future<void> _edit() async {
    final id = await showTicketDialog(context, ref, editId: widget.id);
    if (id != null) await _load(silent: true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar ticket'),
        content: Text('¿Eliminar ${_t!.code} con sus comentarios y archivos? No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: ctx.sw.bad, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(ticketsApiProvider).eliminar(widget.id);
      _refreshLists();
      if (mounted) context.pop();
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _send() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(ticketsApiProvider).comentar(widget.id, text);
      _comment.clear();
      await _load(silent: true);
      _refreshLists();
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(TicketComment c) async {
    try {
      await ref.read(ticketsApiProvider).borrarComentario(widget.id, c.id);
      await _load(silent: true);
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _upload() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true, type: FileType.any);
    if (r == null || r.files.isEmpty) return;
    final big = r.files.where((f) => f.size > _maxFileMb * 1024 * 1024).map((f) => f.name).toList();
    if (big.isNotEmpty) {
      _snack('Superan $_maxFileMb MB: ${big.join(', ')}');
      return;
    }
    try {
      await ref.read(ticketsApiProvider).subirArchivos(widget.id, r.files.where((f) => f.bytes != null).toList());
      await _load(silent: true);
      _refreshLists();
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _download(TicketArchivo a) async {
    try {
      await ref.read(ticketsApiProvider).descargarArchivo(widget.id, a);
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _deleteFile(TicketArchivo a) async {
    try {
      await ref.read(ticketsApiProvider).eliminarArchivo(widget.id, a.id);
      await _load(silent: true);
      _refreshLists();
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final t = _t;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: Text(t?.code ?? 'Ticket'),
        actions: [
          if (t != null && _canEdit) IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: _edit),
          if (t != null && _canDelete) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar', onPressed: _delete),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || t == null
              ? Center(child: Text(_error ?? 'Ticket no encontrado'))
              : ListView(padding: EdgeInsets.all(wide ? 32 : 16), children: [
                  Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: _content(c, t, wide))),
                ]),
    );
  }

  Widget _content(SwissColors c, Ticket t, bool wide) {
    final left = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (t.description.trim().isNotEmpty) SwissSection('Descripción', [SelectableText(t.description, style: const TextStyle(fontSize: 14, height: 1.5))]),
      SwissSection('Seguimiento', [
        for (final x in t.comments)
          if (x.isEvent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Icon(Icons.history, size: 14, color: c.muted),
                const SizedBox(width: 8),
                Expanded(child: Text('${x.body} · ${x.author} · ${_when(x.createdAt)}', style: TextStyle(fontSize: 12, color: c.muted))),
              ]),
            )
          else
            Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(x.author, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_when(x.createdAt), style: TextStyle(fontSize: 11, color: c.muted))),
                  if (_canDelete) InkWell(onTap: () => _deleteComment(x), child: Icon(Icons.delete_outline, size: 16, color: c.bad)),
                ]),
                const SizedBox(height: 6),
                SelectableText(x.body, style: const TextStyle(fontSize: 14, height: 1.45)),
              ]),
            ),
        if (_canEdit) ...[
          const SizedBox(height: 10),
          TextField(controller: _comment, minLines: 2, maxLines: 6, decoration: const InputDecoration(hintText: 'Escribe un comentario…')),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(onPressed: _sending ? null : _send, icon: const Icon(Icons.send, size: 16), label: Text(_sending ? 'Enviando…' : 'Comentar')),
          ),
        ],
      ]),
      SwissSection(
        'Archivos (${t.archivos.length})',
        [
          if (t.archivos.isEmpty) Text('Sin archivos adjuntos.', style: TextStyle(color: c.muted)),
          for (final a in t.archivos)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.attach_file, color: c.accent),
              title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${_size(a.size)} · ${a.createdBy ?? ''} · ${_when(a.createdAt)}'),
              onTap: () => _download(a),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.download_outlined, size: 20), tooltip: 'Descargar', onPressed: () => _download(a)),
                if (_canDelete) IconButton(icon: Icon(Icons.delete_outline, size: 20, color: c.bad), tooltip: 'Eliminar', onPressed: () => _deleteFile(a)),
              ]),
            ),
        ],
        trailing: _canEdit ? TextButton.icon(onPressed: _upload, icon: const Icon(Icons.upload_file, size: 18), label: const Text('Adjuntar')) : null,
      ),
    ]);

    final right = SwissSection('Detalles', [
      Kv.widget(
        'Estado',
        Align(
          alignment: Alignment.centerLeft,
          child: _canEdit
              ? PopupMenuButton<String>(
                  tooltip: 'Cambiar estado',
                  onSelected: (s) => _patch({'status': s}),
                  itemBuilder: (_) => [for (final s in kStatuses) PopupMenuItem(value: s, child: Text(s))],
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Pill(t.status, statusColor(c, t.status)), const Icon(Icons.arrow_drop_down, size: 18)]),
                )
              : Pill(t.status, statusColor(c, t.status)),
        ),
      ),
      Kv.widget(
        'Prioridad',
        Align(
          alignment: Alignment.centerLeft,
          child: _canEdit
              ? PopupMenuButton<String>(
                  tooltip: 'Cambiar prioridad',
                  onSelected: (s) => _patch({'priority': s}),
                  itemBuilder: (_) => [for (final s in kPriorities) PopupMenuItem(value: s, child: Text(s))],
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Pill(t.priority, priorityColor(c, t.priority), icon: Icons.flag), const Icon(Icons.arrow_drop_down, size: 18)]),
                )
              : Pill(t.priority, priorityColor(c, t.priority), icon: Icons.flag),
        ),
      ),
      Kv.widget(
        'Responsable',
        Row(children: [
          Expanded(child: Text(t.assignee ?? 'Sin asignar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: t.assignee == null ? c.warn : c.ink))),
          if (_canEdit) TextButton(onPressed: _assign, child: Text(t.assignee == null ? 'Asignar' : 'Cambiar')),
        ]),
      ),
      Kv.widget(
        'Solicitante',
        t.requesterId == null
            ? Text(t.requesterName ?? '—', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))
            : InkWell(
                onTap: () => context.push('/empleados/${t.requesterId}'),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(t.requesterName ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.accent)),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new, size: 14, color: c.accent),
                ]),
              ),
      ),
      Kv.widget(
        'Activo',
        t.assetTag == null
            ? const Text('—', style: TextStyle(fontSize: 14))
            : InkWell(
                onTap: () => context.push('/inventario/detalle/${t.assetTag}'),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(t.assetTag!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.accent)),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new, size: 14, color: c.accent),
                ]),
              ),
      ),
      Kv('Categoría', t.category),
      Kv.widget(
        'Vence',
        Row(children: [
          Text(t.dueDate == null ? '—' : t.dueDate!.toIso8601String().substring(0, 10), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: t.overdue ? c.bad : c.ink)),
          if (t.overdue) ...[const SizedBox(width: 8), Pill('Vencido', c.bad, icon: Icons.alarm)],
        ]),
      ),
      Kv('Creado por', '${t.createdBy} · ${_when(t.createdAt)}'),
      Kv('Actualizado', _when(t.updatedAt)),
      if (t.resolvedAt != null) Kv('Resuelto', _when(t.resolvedAt!)),
    ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Text(t.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
      ),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 6, child: left),
          const SizedBox(width: 28),
          Expanded(flex: 4, child: right),
        ])
      else ...[right, left],
    ]);
  }
}
