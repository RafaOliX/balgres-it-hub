import 'dart:async';

import 'package:balgres_it_contacts/balgres_it_contacts.dart' show apiError;
import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models.dart';
import 'providers.dart';

String _when(DateTime d) => d.toString().substring(0, 16);

void _snack(BuildContext context, String m) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

// ====================================================================== lista
class NotasPage extends ConsumerStatefulWidget {
  const NotasPage({super.key});
  @override
  ConsumerState<NotasPage> createState() => _NotasPageState();
}

class _NotasPageState extends ConsumerState<NotasPage> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) ref.read(notasQueryProvider.notifier).state = v.trim();
    });
  }

  Future<void> _open([Nota? n]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => NotaEditorPage(id: n?.id)));
    if (!mounted) return;
    ref.invalidate(notasProvider);
    ref.invalidate(notasTagsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final async = ref.watch(notasProvider);
    final tags = ref.watch(notasTagsProvider).valueOrNull ?? const <TagCount>[];
    final tag = ref.watch(notasTagProvider);
    final mobile = MediaQuery.sizeOf(context).width < 900;
    final list = async.valueOrNull ?? const <Nota>[];
    final canEdit = AuthSession.can('notas.editar');

    return Padding(
      padding: EdgeInsets.all(mobile ? 12 : 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Notas', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.0)),
              const SizedBox(height: 6),
              Text('Documentación y apuntes del equipo de TI', style: TextStyle(fontSize: 13, color: c.muted)),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: () {
              ref.invalidate(notasProvider);
              ref.invalidate(notasTagsProvider);
            },
          ),
          if (canEdit) ...[
            const SizedBox(width: 4),
            FilledButton.icon(onPressed: () => _open(), icon: const Icon(Icons.add, size: 18), label: Text(mobile ? 'Nueva' : 'Nueva nota')),
          ],
        ]),
        const SizedBox(height: 18),
        TextField(
          onChanged: _onQuery,
          decoration: const InputDecoration(hintText: 'Buscar en título, texto o tag de activo…', prefixIcon: Icon(Icons.search, size: 20)),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: const Text('Todas'), selected: tag == null, onSelected: (_) => ref.read(notasTagProvider.notifier).state = null),
              ),
              for (final t in tags)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${t.tag} · ${t.count}'),
                    selected: tag == t.tag,
                    onSelected: (v) => ref.read(notasTagProvider.notifier).state = v ? t.tag : null,
                  ),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: async.isLoading && list.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : async.hasError && list.isEmpty
                  ? Center(child: Text('Error: ${apiError(async.error!)}'))
                  : list.isEmpty
                      ? EmptyState(
                          icon: Icons.sticky_note_2_outlined,
                          title: 'Sin notas',
                          subtitle: 'Crea la primera o prueba con otra búsqueda.',
                          action: canEdit ? 'Nueva nota' : null,
                          onAction: canEdit ? () => _open() : null,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _NotaCard(nota: list[i], onTap: () => _open(list[i])),
                        ),
        ),
      ]),
    );
  }
}

class _NotaCard extends StatelessWidget {
  final Nota nota;
  final VoidCallback onTap;
  const _NotaCard({required this.nota, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: cardDeco(context, radius: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(nota.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                if (nota.assetTag != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                    child: Text(nota.assetTag!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.accent)),
                  ),
              ]),
              if (nota.snippet.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(nota.snippet, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted)),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final t in nota.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.line)),
                    child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                Text('${_when(nota.updatedAt)} · ${nota.updatedBy ?? ''}', style: TextStyle(fontSize: 11, color: c.muted)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ====================================================================== editor / visor
class NotaEditorPage extends ConsumerStatefulWidget {
  final int? id;
  const NotaEditorPage({super.key, this.id});
  @override
  ConsumerState<NotaEditorPage> createState() => _NotaEditorPageState();
}

class _NotaEditorPageState extends ConsumerState<NotaEditorPage> {
  final _title = TextEditingController();
  final _tags = TextEditingController();
  final _asset = TextEditingController();
  final _body = TextEditingController();
  bool _loading = false, _saving = false;
  String? _error;

  bool get _canEdit => AuthSession.can('notas.editar');

  @override
  void initState() {
    super.initState();
    if (widget.id != null) {
      _loading = true;
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _tags, _asset, _body]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final n = await ref.read(notasApiProvider).obtener(widget.id!);
      if (!mounted) return;
      setState(() {
        _title.text = n.title;
        _tags.text = n.tags.join(', ');
        _asset.text = n.assetTag ?? '';
        _body.text = n.body;
      });
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      _snack(context, 'Ponle un título a la nota');
      return;
    }
    setState(() => _saving = true);
    final body = {
      'title': _title.text.trim(),
      'body': _body.text,
      'tags': _tags.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      'asset_tag': _asset.text.trim(),
    };
    try {
      final api = ref.read(notasApiProvider);
      if (widget.id == null) {
        await api.crear(body);
      } else {
        await api.actualizar(widget.id!, body);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar nota'),
        content: Text('¿Eliminar "${_title.text}"? No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: context.sw.bad, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(notasApiProvider).eliminar(widget.id!);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final tag = _asset.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'Nueva nota' : (_canEdit ? 'Editar nota' : 'Nota')),
        actions: [
          if (widget.id != null && AuthSession.can('notas.eliminar'))
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar', onPressed: _delete),
          if (_canEdit)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined, size: 18), label: Text(_saving ? 'Guardando…' : 'Guardar')),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(padding: const EdgeInsets.all(24), children: [
                  if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(_error!, style: TextStyle(color: c.bad, fontWeight: FontWeight.w600))),
                  TextField(controller: _title, readOnly: !_canEdit, decoration: const InputDecoration(labelText: 'Título *')),
                  const SizedBox(height: 16),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 3,
                      child: TextField(controller: _tags, readOnly: !_canEdit, decoration: const InputDecoration(labelText: 'Etiquetas', helperText: 'Separadas por coma: cctv, redes, rack')),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _asset,
                        readOnly: !_canEdit,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'Tag de activo (opcional)', helperText: 'Ej: NVR-001'),
                      ),
                    ),
                  ]),
                  if (tag.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => context.push('/inventario/detalle/$tag'),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text('Ver activo $tag'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _body,
                    readOnly: !_canEdit,
                    minLines: 18,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(labelText: 'Contenido', alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 8),
                  Text('No guardes contraseñas aquí: cualquiera con permiso notas.ver puede leerlas.', style: TextStyle(fontSize: 12, color: c.muted)),
                ]),
              ),
            ),
    );
  }
}
