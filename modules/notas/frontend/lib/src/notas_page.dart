import 'dart:async';

import 'package:balgres_it_contacts/balgres_it_contacts.dart' show apiError;
import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'diagram_editor_page.dart';
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
              Text('Documentación, activos involucrados y diagramas del equipo de TI', style: TextStyle(fontSize: 13, color: c.muted)),
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
    final extra = nota.assetTags.length - 3;
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
                if (nota.diagramCount > 0) ...[
                  Icon(Icons.account_tree_outlined, size: 16, color: c.muted),
                  const SizedBox(width: 4),
                  Text('${nota.diagramCount}', style: TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w700)),
                ],
              ]),
              if (nota.snippet.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(nota.snippet, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted)),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final t in nota.assetTags.take(3))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                    child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.accent)),
                  ),
                if (extra > 0) Text('+$extra', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.accent)),
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
  final _body = TextEditingController();
  int? _id;
  List<String> _assets = [];
  bool _loading = false, _saving = false;
  String? _error;
  List<Map<String, dynamic>> _planos = const [];
  List<NotaDiagrama> _diagramas = const [];

  bool get _canEdit => AuthSession.can('notas.editar');
  bool get _canDelete => AuthSession.can('notas.eliminar');

  @override
  void initState() {
    super.initState();
    _id = widget.id;
    if (_id != null) {
      _loading = true;
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _tags, _body]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final n = await ref.read(notasApiProvider).obtener(_id!);
      if (!mounted) return;
      setState(() {
        _title.text = n.title;
        _tags.text = n.tags.join(', ');
        _assets = [...n.assetTags];
        _body.text = n.body;
      });
      await _loadExtras();
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadExtras() async {
    final id = _id;
    if (id == null) return;
    final api = ref.read(notasApiProvider);
    final pl = await api.planosVinculados(id);
    var dg = const <NotaDiagrama>[];
    try {
      dg = await api.listarDiagramas(id);
    } catch (_) {}
    if (mounted) setState(() {
      _planos = pl;
      _diagramas = dg;
    });
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
      'asset_tags': _assets,
    };
    try {
      final api = ref.read(notasApiProvider);
      if (_id == null) {
        final n = await api.crear(body);
        ref.invalidate(notasProvider);
        ref.invalidate(notasTagsProvider);
        if (mounted) setState(() {
          _id = n.id;
          _saving = false;
        });
        _snack(context, 'Nota guardada. Ya puedes agregar diagramas.');
        await _loadExtras();
      } else {
        await api.actualizar(_id!, body);
        ref.invalidate(notasProvider);
        ref.invalidate(notasTagsProvider);
        if (mounted) Navigator.of(context).pop();
      }
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
        content: Text('¿Eliminar "${_title.text}" con sus diagramas? No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: context.sw.bad, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(notasApiProvider).eliminar(_id!);
      ref.invalidate(notasProvider);
      ref.invalidate(notasTagsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  Future<void> _openDiagram([NotaDiagrama? d]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DiagramEditorPage(notaId: _id!, diagramId: d?.id)));
    if (!mounted) return;
    ref.invalidate(notasProvider);
    await _loadExtras();
  }

  Future<void> _deleteDiagram(NotaDiagrama d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar diagrama'),
        content: Text('¿Eliminar "${d.title}"? No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: context.sw.bad, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(notasApiProvider).eliminarDiagrama(_id!, d.id);
      ref.invalidate(notasProvider);
      await _loadExtras();
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      appBar: AppBar(
        title: Text(_id == null ? 'Nueva nota' : (_canEdit ? 'Editar nota' : 'Nota')),
        actions: [
          if (_id != null && _canDelete) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar', onPressed: _delete),
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
                  TextField(controller: _tags, readOnly: !_canEdit, decoration: const InputDecoration(labelText: 'Etiquetas', helperText: 'Separadas por coma: cctv, redes, rack')),
                  const SizedBox(height: 24),
                  SwissSection('Activos involucrados', [
                    AssetLinksField(
                      label: 'Equipos y dispositivos de esta nota',
                      tags: _assets,
                      enabled: _canEdit,
                      onChanged: (l) => setState(() => _assets = l),
                      onOpen: (t) => context.push('/inventario/detalle/$t'),
                    ),
                  ]),
                  TextField(
                    controller: _body,
                    readOnly: !_canEdit,
                    minLines: 14,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(labelText: 'Contenido', alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 24),
                  SwissSection(
                    'Diagramas',
                    [
                      if (_id == null) Text('Guarda la nota para poder agregar diagramas.', style: TextStyle(color: c.muted, fontSize: 13)),
                      if (_id != null && _diagramas.isEmpty) Text('Aún no hay diagramas.', style: TextStyle(color: c.muted, fontSize: 13)),
                      if (_diagramas.isNotEmpty)
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final d in _diagramas)
                            InputChip(
                              avatar: const Icon(Icons.account_tree_outlined, size: 16),
                              label: Text(d.title),
                              onPressed: () => _openDiagram(d),
                              onDeleted: _canDelete ? () => _deleteDiagram(d) : null,
                            ),
                        ]),
                    ],
                    trailing: (_id != null && _canEdit)
                        ? TextButton.icon(onPressed: () => _openDiagram(), icon: const Icon(Icons.add, size: 18), label: const Text('Nuevo diagrama'))
                        : null,
                  ),
                  if (_planos.isNotEmpty) ...[
                    const SectionLabel('Planos vinculados'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final p in _planos)
                        ActionChip(
                          avatar: const Icon(Icons.map_outlined, size: 16),
                          label: Text(((p['pins'] as List?) ?? const []).isEmpty ? '${p['name']}' : '${p['name']} · ${(p['pins'] as List).join(', ')}'),
                          onPressed: () => context.push('/planos/${p['id']}'),
                        ),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  Text('No guardes contraseñas aquí ni en los diagramas: cualquiera con permiso notas.ver puede leerlas.', style: TextStyle(fontSize: 12, color: c.muted)),
                ]),
              ),
            ),
    );
  }
}
