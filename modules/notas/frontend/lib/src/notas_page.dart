import 'dart:async';
import 'dart:typed_data';

import 'package:balgres_it_contacts/balgres_it_contacts.dart' show apiError;
import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:markdown/markdown.dart' as md;

import 'diagram_editor_page.dart';
import 'models.dart';
import 'providers.dart';
import 'tags_field.dart';

const _maxFileMb = 50; // debe coincidir con NOTAS_MAX_MB del backend

String _when(DateTime d) => d.toString().substring(0, 16);

void _snack(BuildContext context, String m) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

String _size(int b) => b < 1024 ? '$b B' : (b < 1048576 ? '${(b / 1024).toStringAsFixed(0)} KB' : '${(b / 1048576).toStringAsFixed(1)} MB');

IconData _fileIcon(String name) {
  final e = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'}.contains(e)) return Icons.image_outlined;
  if (e == 'pdf') return Icons.picture_as_pdf_outlined;
  if (const {'xls', 'xlsx', 'csv', 'ods'}.contains(e)) return Icons.table_chart_outlined;
  if (const {'doc', 'docx', 'odt', 'txt', 'md', 'rtf'}.contains(e)) return Icons.description_outlined;
  if (const {'zip', 'rar', '7z', 'tar', 'gz'}.contains(e)) return Icons.folder_zip_outlined;
  if (const {'mp4', 'mov', 'avi', 'mkv'}.contains(e)) return Icons.movie_outlined;
  if (const {'mp3', 'wav', 'ogg'}.contains(e)) return Icons.audio_file_outlined;
  if (const {'cfg', 'conf', 'log', 'json', 'xml', 'yaml', 'yml', 'sh', 'py', 'sql'}.contains(e)) return Icons.code;
  return Icons.insert_drive_file_outlined;
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
              Text('Documentación, archivos, activos y diagramas del equipo de TI', style: TextStyle(fontSize: 13, color: c.muted)),
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
    Widget count(IconData i, int n) => Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 15, color: c.muted),
            const SizedBox(width: 3),
            Text('$n', style: TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w700)),
          ]),
        );
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
                if (nota.diagramCount > 0) count(Icons.account_tree_outlined, nota.diagramCount),
                if (nota.fileCount > 0) count(Icons.attach_file, nota.fileCount),
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
              ]),
              const SizedBox(height: 6),
              Text(
                'Creada por ${nota.createdBy} · ${_when(nota.createdAt)}   ·   Editada por ${nota.updatedBy} · ${_when(nota.updatedAt)}',
                style: TextStyle(fontSize: 11, color: c.muted),
              ),
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

class _NotaEditorPageState extends ConsumerState<NotaEditorPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _bodyFocus = FocusNode();
  int? _id;
  Nota? _info;
  List<String> _tags = [];
  List<String> _assets = [];
  bool _loading = false, _saving = false, _dirty = false, _ready = true;
  int _mode = 0; // 0 editar, 1 vista previa, 2 dividido
  String? _error;
  List<Map<String, dynamic>> _planos = const [];
  List<NotaDiagrama> _diagramas = const [];
  List<NotaArchivo> _archivos = const [];
  List<NotaRevision> _hist = const [];

  bool get _canEdit => AuthSession.can('notas.editar');
  bool get _canDelete => AuthSession.can('notas.eliminar');

  @override
  void initState() {
    super.initState();
    _id = widget.id;
    _title.addListener(_changed);
    _body.addListener(_changed);
    if (_id != null) {
      _loading = true;
      _load();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _bodyFocus.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_ready || !mounted) return;
    if (!_dirty) {
      setState(() => _dirty = true);
    } else if (_mode != 0) {
      setState(() {});
    }
  }

  void _fill(Nota n) {
    _ready = false;
    _title.text = n.title;
    _body.text = n.body;
    _tags = [...n.tags];
    _assets = [...n.assetTags];
    _info = n;
    _dirty = false;
    _ready = true;
  }

  Future<void> _load() async {
    try {
      final n = await ref.read(notasApiProvider).obtener(_id!);
      if (!mounted) return;
      setState(() => _fill(n));
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
    var ar = const <NotaArchivo>[];
    var hs = const <NotaRevision>[];
    try {
      dg = await api.listarDiagramas(id);
    } catch (_) {}
    try {
      ar = await api.listarArchivos(id);
    } catch (_) {}
    try {
      hs = await api.historial(id);
    } catch (_) {}
    try {
      _info = await api.obtener(id).then((n) => Nota(
            id: n.id, title: n.title, body: n.body, tags: n.tags, assetTags: n.assetTags, createdBy: n.createdBy,
            updatedBy: n.updatedBy, createdAt: n.createdAt, updatedAt: n.updatedAt));
    } catch (_) {}
    if (mounted) setState(() {
      _planos = pl;
      _diagramas = dg;
      _archivos = ar;
      _hist = hs;
    });
  }

  /// Devuelve true si guardó.
  Future<bool> _save() async {
    if (!_canEdit) return false;
    if (_title.text.trim().isEmpty) {
      _snack(context, 'Ponle un título a la nota');
      return false;
    }
    setState(() => _saving = true);
    final body = {'title': _title.text.trim(), 'body': _body.text, 'tags': _tags, 'asset_tags': _assets};
    try {
      final api = ref.read(notasApiProvider);
      if (_id == null) {
        final n = await api.crear(body);
        _id = n.id;
      } else {
        await api.actualizar(_id!, body);
      }
      ref.invalidate(notasProvider);
      ref.invalidate(notasTagsProvider);
      if (mounted) setState(() => _dirty = false);
      await _loadExtras();
      _snack(context, 'Nota guardada');
      return true;
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmLeave() async {
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.edit_note, color: context.sw.accent, size: 36),
        title: const Text('Tienes cambios sin guardar'),
        content: const Text('¿Qué quieres hacer con los cambios de esta nota?'),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(style: TextButton.styleFrom(foregroundColor: context.sw.bad), onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Salir sin guardar')),
          Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'stay'), child: const Text('Seguir editando')),
            const SizedBox(width: 8),
            if (_canEdit) FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Guardar y salir')),
          ]),
        ],
      ),
    );
    if (!mounted) return;
    if (r == 'discard') {
      Navigator.of(context).pop();
    } else if (r == 'save' && await _save() && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar nota'),
        content: Text('¿Eliminar "${_title.text}" con sus diagramas, archivos e historial? No se puede deshacer.'),
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
      if (mounted) {
        _dirty = false;
        Navigator.of(context).pop();
      }
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  // ---------------------------------------------------------------- barra de formato (Markdown)
  void _wrapSel(String l, String r, {String hint = ''}) {
    final v = _body.value;
    final s = v.selection;
    final start = s.isValid ? s.start : v.text.length;
    final end = s.isValid ? s.end : start;
    final sel = v.text.substring(start, end);
    final mid = sel.isEmpty ? hint : sel;
    _body.value = TextEditingValue(
      text: v.text.replaceRange(start, end, '$l$mid$r'),
      selection: TextSelection(baseOffset: start + l.length, extentOffset: start + l.length + mid.length),
    );
    _bodyFocus.requestFocus();
  }

  void _linePrefix(String p) {
    final v = _body.value;
    final t = v.text;
    final s = v.selection;
    final start = s.isValid ? s.start : t.length;
    final end = s.isValid ? s.end : start;
    final ls = start == 0 ? 0 : t.lastIndexOf('\n', start - 1) + 1;
    final le = t.indexOf('\n', end) < 0 ? t.length : t.indexOf('\n', end);
    final block = t.substring(ls, le).split('\n').map((l) => '$p$l').join('\n');
    _body.value = TextEditingValue(text: t.replaceRange(ls, le, block), selection: TextSelection.collapsed(offset: ls + block.length));
    _bodyFocus.requestFocus();
  }

  void _insert(String s) {
    final v = _body.value;
    final at = v.selection.isValid ? v.selection.end : v.text.length;
    _body.value = TextEditingValue(text: v.text.replaceRange(at, at, s), selection: TextSelection.collapsed(offset: at + s.length));
    _bodyFocus.requestFocus();
  }

  Widget _fmt(IconData i, String tip, VoidCallback f) => IconButton(icon: Icon(i, size: 19), tooltip: tip, onPressed: f, visualDensity: VisualDensity.compact);

  Widget _toolbar(SwissColors c) => Container(
        decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            if (_canEdit && _mode != 1) ...[
              _fmt(Icons.format_bold, 'Negrita', () => _wrapSel('**', '**', hint: 'texto')),
              _fmt(Icons.format_italic, 'Cursiva', () => _wrapSel('_', '_', hint: 'texto')),
              _fmt(Icons.title, 'Título', () => _linePrefix('## ')),
              _fmt(Icons.format_list_bulleted, 'Lista', () => _linePrefix('- ')),
              _fmt(Icons.format_list_numbered, 'Lista numerada', () => _linePrefix('1. ')),
              _fmt(Icons.checklist, 'Lista de tareas', () => _linePrefix('- [ ] ')),
              _fmt(Icons.format_quote, 'Cita', () => _linePrefix('> ')),
              _fmt(Icons.code, 'Código', () => _wrapSel('`', '`', hint: 'código')),
              _fmt(Icons.terminal, 'Bloque de código', () => _insert('\n```\ncomando\n```\n')),
              _fmt(Icons.link, 'Enlace', () => _wrapSel('[', '](https://)', hint: 'texto')),
              _fmt(Icons.table_chart_outlined, 'Tabla', () => _insert('\n| Columna 1 | Columna 2 |\n|---|---|\n| dato | dato |\n')),
              _fmt(Icons.horizontal_rule, 'Separador', () => _insert('\n\n---\n\n')),
            ],
            const SizedBox(width: 8),
          ]),
        ),
      );

  Widget _preview() => Markdown(
        data: _body.text.trim().isEmpty ? '_La nota no tiene contenido._' : _body.text,
        selectable: true,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        padding: const EdgeInsets.all(16),
        onTapLink: (text, href, title) {
          if (href == null) return;
          Clipboard.setData(ClipboardData(text: href));
          _snack(context, 'Enlace copiado: $href');
        },
      );

  Widget _editor(SwissColors c) => TextField(
        controller: _body,
        focusNode: _bodyFocus,
        readOnly: !_canEdit,
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.45),
        decoration: const InputDecoration(hintText: 'Escribe o pega aquí. Admite Markdown: títulos, listas, tablas, código…'),
      );

  // ---------------------------------------------------------------- pestaña contenido
  Widget _contenidoTab(SwissColors c) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final mode = (_mode == 2 && !wide) ? 0 : _mode;
    Widget body;
    if (mode == 0) {
      body = _editor(c);
    } else if (mode == 1) {
      body = Container(decoration: cardDeco(context, radius: 12), child: _preview());
    } else {
      body = Row(children: [
        Expanded(child: _editor(c)),
        const SizedBox(width: 12),
        Expanded(child: Container(decoration: cardDeco(context, radius: 12), child: _preview())),
      ]);
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          Expanded(child: _toolbar(c)),
          const SizedBox(width: 10),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: 0, icon: Icon(Icons.edit_outlined, size: 16), label: Text('Editar')),
              const ButtonSegment(value: 1, icon: Icon(Icons.visibility_outlined, size: 16), label: Text('Vista')),
              if (wide) const ButtonSegment(value: 2, icon: Icon(Icons.vertical_split_outlined, size: 16), label: Text('Dividida')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Expanded(child: body),
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Activos involucrados (${_assets.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AssetLinksField(
              label: 'Equipos y dispositivos de esta nota',
              tags: _assets,
              enabled: _canEdit,
              onChanged: (l) => setState(() {
                _assets = l;
                _dirty = true;
              }),
              onOpen: (t) => context.push('/inventario/detalle/$t'),
            ),
            if (_planos.isNotEmpty) ...[
              const SizedBox(height: 12),
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
          ],
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------- pestaña diagramas
  Future<void> _openDiagram([NotaDiagrama? d]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DiagramEditorPage(notaId: _id!, diagramId: d?.id)));
    if (!mounted) return;
    ref.invalidate(notasProvider);
    await _loadExtras();
  }

  Future<void> _deleteDiagram(NotaDiagrama d) async {
    final ok = await _confirm('Eliminar diagrama', '¿Eliminar "${d.title}"? No se puede deshacer.');
    if (!ok) return;
    try {
      await ref.read(notasApiProvider).eliminarDiagrama(_id!, d.id);
      ref.invalidate(notasProvider);
      await _loadExtras();
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  Future<bool> _confirm(String title, String msg) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(msg),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: context.sw.bad, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
          ],
        ),
      ) ??
      false;

  Widget _diagramasTab(SwissColors c) {
    if (_id == null) return _needSave('diagramas');
    Widget card(NotaDiagrama d) {
      final Uint8List? img = d.preview;
      return SizedBox(
        width: 290,
        child: Container(
          decoration: cardDeco(context, radius: 14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openDiagram(d),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Container(
                  color: Colors.white,
                  child: img != null ? Image.memory(img, fit: BoxFit.contain, gaplessPlayback: true) : Center(child: Icon(Icons.account_tree_outlined, size: 42, color: c.edge)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      Text('${d.updatedBy ?? ''} · ${_when(d.updatedAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.muted)),
                    ]),
                  ),
                  if (_canDelete) IconButton(icon: Icon(Icons.delete_outline, size: 20, color: c.bad), tooltip: 'Eliminar', onPressed: () => _deleteDiagram(d)),
                ]),
              ),
            ]),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      child: Wrap(spacing: 14, runSpacing: 14, children: [
        for (final d in _diagramas) card(d),
        if (_canEdit)
          SizedBox(
            width: 290,
            height: 214,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () => _openDiagram(),
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add, size: 32), SizedBox(height: 6), Text('Nuevo diagrama')]),
            ),
          ),
        if (_diagramas.isEmpty && !_canEdit) Text('Esta nota no tiene diagramas.', style: TextStyle(color: c.muted)),
      ]),
    );
  }

  Widget _needSave(String what) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text('Guarda la nota para poder agregar $what.', style: TextStyle(color: context.sw.muted))),
      );

  // ---------------------------------------------------------------- pestaña archivos
  Future<void> _subir() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true, type: FileType.any);
    if (r == null || r.files.isEmpty || !mounted) return;
    final big = r.files.where((f) => f.size > _maxFileMb * 1024 * 1024).map((f) => f.name).toList();
    if (big.isNotEmpty) {
      _snack(context, 'Superan $_maxFileMb MB: ${big.join(', ')}');
      return;
    }
    final ok = r.files.where((f) => f.bytes != null).toList();
    if (ok.isEmpty) {
      _snack(context, 'No se pudo leer el archivo seleccionado');
      return;
    }
    try {
      await ref.read(notasApiProvider).subirArchivos(_id!, ok);
      ref.invalidate(notasProvider);
      await _loadExtras();
      _snack(context, '${ok.length} archivo(s) adjuntado(s)');
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  Future<void> _bajar(NotaArchivo a) async {
    try {
      await ref.read(notasApiProvider).descargarArchivo(_id!, a);
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  Future<void> _borrarArchivo(NotaArchivo a) async {
    if (!await _confirm('Eliminar archivo', '¿Eliminar "${a.name}"? No se puede deshacer.')) return;
    try {
      await ref.read(notasApiProvider).eliminarArchivo(_id!, a.id);
      ref.invalidate(notasProvider);
      await _loadExtras();
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  Widget _archivosTab(SwissColors c) {
    if (_id == null) return _needSave('archivos');
    return ListView(padding: const EdgeInsets.only(top: 12, bottom: 24), children: [
      Row(children: [
        Expanded(child: Text('Cualquier tipo de archivo, hasta $_maxFileMb MB cada uno. No subas credenciales: lo descarga cualquiera con permiso notas.ver.', style: TextStyle(fontSize: 12, color: c.muted))),
        if (_canEdit) FilledButton.icon(onPressed: _subir, icon: const Icon(Icons.upload_file, size: 18), label: const Text('Adjuntar')),
      ]),
      const SizedBox(height: 12),
      if (_archivos.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Sin archivos adjuntos.', style: TextStyle(color: c.muted)))),
      for (final a in _archivos)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: cardDeco(context, radius: 12),
          child: ListTile(
            leading: Icon(_fileIcon(a.name), color: c.accent),
            title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${_size(a.size)} · ${a.createdBy ?? ''} · ${_when(a.createdAt)}', style: const TextStyle(fontSize: 12)),
            onTap: () => _bajar(a),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.download_outlined, size: 20), tooltip: 'Descargar', onPressed: () => _bajar(a)),
              if (_canDelete) IconButton(icon: Icon(Icons.delete_outline, size: 20, color: c.bad), tooltip: 'Eliminar', onPressed: () => _borrarArchivo(a)),
            ]),
          ),
        ),
    ]);
  }

  // ---------------------------------------------------------------- pestaña historial
  Future<void> _verVersion(NotaRevision r) async {
    try {
      final v = await ref.read(notasApiProvider).version(_id!, r.id);
      if (!mounted) return;
      final restore = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Versión ${v.version} · ${v.title ?? ''}'),
          content: SizedBox(
            width: 720,
            height: 480,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${v.changedBy} · ${_when(v.changedAt)}${v.tags.isEmpty ? '' : ' · ${v.tags.join(', ')}'}', style: TextStyle(fontSize: 12, color: ctx.sw.muted)),
              const Divider(height: 20),
              Expanded(child: Markdown(data: (v.body ?? '').isEmpty ? '_Sin contenido._' : v.body!, selectable: true, extensionSet: md.ExtensionSet.gitHubFlavored, padding: EdgeInsets.zero)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cerrar')),
            if (_canEdit) FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurar esta versión')),
          ],
        ),
      );
      if (restore == true) await _restaurar(r);
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  Future<void> _restaurar(NotaRevision r) async {
    if (_dirty && !await _confirm('Cambios sin guardar', 'Tienes cambios sin guardar que se perderán al restaurar. ¿Continuar?')) return;
    try {
      final n = await ref.read(notasApiProvider).restaurar(_id!, r.id);
      ref.invalidate(notasProvider);
      ref.invalidate(notasTagsProvider);
      if (mounted) setState(() => _fill(n));
      await _loadExtras();
      _tabs.animateTo(0);
      _snack(context, 'Versión ${r.version} restaurada');
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  Widget _historialTab(SwissColors c) {
    if (_id == null) return _needSave('historial');
    final i = _info;
    return ListView(padding: const EdgeInsets.only(top: 12, bottom: 24), children: [
      if (i != null)
        SwissSection('Resumen', [
          Kv('Creada por', '${i.createdBy}'),
          Kv('Fecha de creación', _when(i.createdAt)),
          Kv('Última edición por', '${i.updatedBy}'),
          Kv('Fecha de última edición', _when(i.updatedAt)),
          Kv('Registros', '${_hist.length}'),
        ]),
      for (final r in _hist)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: cardDeco(context, radius: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: (r.hasSnapshot ? c.accent : c.muted).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text('v${r.version}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: r.hasSnapshot ? c.accent : c.muted)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.action, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                if ((r.detail ?? '').isNotEmpty) Text(r.detail!, style: TextStyle(fontSize: 13, color: c.muted)),
                Text('${r.changedBy} · ${_when(r.changedAt)}', style: TextStyle(fontSize: 11, color: c.muted)),
              ]),
            ),
            if (r.hasSnapshot) TextButton(onPressed: () => _verVersion(r), child: const Text('Ver')),
            if (r.hasSnapshot && _canEdit) TextButton(onPressed: () => _restaurar(r), child: const Text('Restaurar')),
          ]),
        ),
    ]);
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final known = {for (final t in ref.watch(notasTagsProvider).valueOrNull ?? const <TagCount>[]) t.tag: t.count};
    final i = _info;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save()},
        child: Scaffold(
          appBar: AppBar(
            title: Text(_id == null ? 'Nueva nota' : (_canEdit ? 'Editar nota' : 'Nota')),
            actions: [
              if (_dirty) Center(child: Padding(padding: const EdgeInsets.only(right: 12), child: Text('● Sin guardar', style: TextStyle(color: c.warn, fontWeight: FontWeight.w700, fontSize: 12)))),
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
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: c.bad, fontWeight: FontWeight.w600))),
                        TextField(
                          controller: _title,
                          readOnly: !_canEdit,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                          decoration: const InputDecoration(hintText: 'Título de la nota *'),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          i == null ? 'Nota nueva' : 'Creada por ${i.createdBy} · ${_when(i.createdAt)}   |   Última edición por ${i.updatedBy} · ${_when(i.updatedAt)}',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                        const SizedBox(height: 10),
                        TagsField(
                          tags: _tags,
                          known: known,
                          enabled: _canEdit,
                          onChanged: (l) => setState(() {
                            _tags = l;
                            _dirty = true;
                          }),
                        ),
                        const SizedBox(height: 4),
                        TabBar(
                          controller: _tabs,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          tabs: [
                            const Tab(text: 'Contenido'),
                            Tab(text: 'Diagramas (${_diagramas.length})'),
                            Tab(text: 'Archivos (${_archivos.length})'),
                            Tab(text: 'Historial (${_hist.length})'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabs,
                            physics: const NeverScrollableScrollPhysics(), // no choca con el arrastre del editor
                            children: [_contenidoTab(c), _diagramasTab(c), _archivosTab(c), _historialTab(c)],
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
