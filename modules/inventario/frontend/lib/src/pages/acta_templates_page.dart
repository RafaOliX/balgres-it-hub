import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../models/catalogs.dart';
import '../ui/swiss.dart';

String _labelOf(List<(String, String)> list, String key) => list.where((e) => e.$1 == key).firstOrNull?.$2 ?? key;

/// Elige la plantilla con la que se generará el PDF. Devuelve null si se cancela.
Future<ActaTemplate?> showActaPicker(BuildContext context, {String title = 'Elegir plantilla de acta'}) {
  return showDialog<ActaTemplate>(
    context: context,
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final c = ctx.sw;
      final async = ref.watch(actaTemplatesProvider);
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: async.when(
            loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('Error: ${apiError(e)}'),
            data: (list) => list.isEmpty
                ? const Text('No hay plantillas. Crea una en "Gestionar plantillas".')
                : SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final t in list)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.description_outlined, color: c.accent),
                          title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${t.title} · ${t.assetColumns.length} columnas · ${t.employeeFields.length} datos del empleado',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.pop(ctx, t),
                        ),
                    ]),
                  ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Gestionar plantillas'),
            onPressed: () async {
              await Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ActaTemplatesPage()));
              ref.invalidate(actaTemplatesProvider);
            },
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ],
      );
    }),
  );
}

// ====================================================================== lista de plantillas
class ActaTemplatesPage extends ConsumerWidget {
  const ActaTemplatesPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [ActaTemplate? t]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ActaTemplateEditorPage(template: t)));
    ref.invalidate(actaTemplatesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sw;
    final async = ref.watch(actaTemplatesProvider);
    void snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plantillas de acta'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(onPressed: () => _edit(context, ref), icon: const Icon(Icons.add, size: 18), label: const Text('Nueva plantilla')),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: ${apiError(e)}')),
        data: (list) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(padding: const EdgeInsets.all(24), children: [
              Text('Define qué datos lleva cada documento. Con la misma plantilla puedes generar el acta con los equipos del empleado o una hoja en blanco para llenar a mano.',
                  style: TextStyle(color: c.muted)),
              const SizedBox(height: 18),
              if (list.isEmpty) const EmptyState(icon: Icons.description_outlined, title: 'Aún no hay plantillas'),
              for (final t in list)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(18),
                  decoration: cardDeco(context),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.description_outlined, color: c.accent),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                      Text(t.config['orientation'] == 'L' ? 'Horizontal' : 'Vertical', style: TextStyle(fontSize: 12, color: c.muted)),
                    ]),
                    const SizedBox(height: 8),
                    Text('Empleado: ${t.employeeFields.map((k) => _labelOf(kActaEmployeeFields, k)).join(', ').ifEmpty('—')}', style: TextStyle(fontSize: 13, color: c.muted)),
                    const SizedBox(height: 2),
                    Text('Columnas: ${t.assetColumns.map((k) => _labelOf(kActaAssetColumns, k)).join(', ')}', style: TextStyle(fontSize: 13, color: c.muted)),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(onPressed: () => _edit(context, ref, t), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Editar')),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.print_outlined, size: 18),
                        label: const Text('Hoja en blanco'),
                        onPressed: () async {
                          try {
                            await ref.read(inventarioApiProvider).descargarActaPlantilla(t.id, name: t.name);
                          } catch (e) {
                            snack('Error: ${apiError(e)}');
                          }
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text('Duplicar'),
                        onPressed: () async {
                          try {
                            await ref.read(inventarioApiProvider).crearActaTemplate('${t.name} (copia)', t.config);
                            ref.invalidate(actaTemplatesProvider);
                          } catch (e) {
                            snack('Error: ${apiError(e)}');
                          }
                        },
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: c.bad),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Eliminar'),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Eliminar plantilla'),
                              content: Text('¿Eliminar "${t.name}"?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          try {
                            await ref.read(inventarioApiProvider).eliminarActaTemplate(t.id);
                            ref.invalidate(actaTemplatesProvider);
                          } catch (e) {
                            snack('Error: ${apiError(e)}');
                          }
                        },
                      ),
                    ]),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String f) => isEmpty ? f : this;
}

// ====================================================================== editor
class ActaTemplateEditorPage extends ConsumerStatefulWidget {
  final ActaTemplate? template;
  const ActaTemplateEditorPage({super.key, this.template});
  @override
  ConsumerState<ActaTemplateEditorPage> createState() => _ActaTemplateEditorPageState();
}

class _ActaTemplateEditorPageState extends ConsumerState<ActaTemplateEditorPage> {
  late final TextEditingController _name, _title, _intro, _footer, _rows, _sigs;
  late List<String> _emp, _cols;
  late bool _land, _showDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    final cfg = t?.config ?? <String, dynamic>{};
    _name = TextEditingController(text: t?.name ?? '');
    _title = TextEditingController(text: (cfg['title'] as String?) ?? 'Acta de Entrega de Equipos TI');
    _intro = TextEditingController(text: (cfg['intro'] as String?) ?? 'Por medio de la presente se hace entrega de los equipos detallados a continuación a {empleado}.');
    _footer = TextEditingController(text: (cfg['footer'] as String?) ?? '');
    _rows = TextEditingController(text: '${cfg['blank_rows'] ?? 10}');
    _sigs = TextEditingController(text: ((cfg['signatures'] as List?) ?? const ['Firma Responsable TI', 'Firma de Recibido']).join('\n'));
    _emp = t != null ? [...t.employeeFields] : ['name', 'position', 'department', 'extension'];
    _cols = t != null ? [...t.assetColumns] : ['tag', 'equipo', 'serial', 'quantity'];
    _land = cfg['orientation'] == 'L';
    _showDate = (cfg['show_date'] as bool?) ?? true;
  }

  @override
  void dispose() {
    for (final c in [_name, _title, _intro, _footer, _rows, _sigs]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _config() => {
        'title': _title.text.trim(),
        'intro': _intro.text.trim(),
        'employee_fields': _emp,
        'asset_columns': _cols,
        'orientation': _land ? 'L' : 'P',
        'show_date': _showDate,
        'blank_rows': int.tryParse(_rows.text.trim()) ?? 10,
        'signatures': _sigs.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
        'footer': _footer.text.trim(),
      };

  Future<void> _save({bool preview = false}) async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ponle un nombre a la plantilla')));
      return;
    }
    if (_cols.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Elige al menos una columna de equipos')));
      return;
    }
    setState(() => _saving = true);
    try {
      final api = ref.read(inventarioApiProvider);
      final saved = widget.template == null
          ? await api.crearActaTemplate(_name.text.trim(), _config())
          : await api.actualizarActaTemplate(widget.template!.id, _name.text.trim(), _config());
      if (preview) {
        await api.descargarActaPlantilla(saved.id, name: saved.name);
        if (mounted) setState(() => _saving = false);
      } else if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${apiError(e)}')));
      }
    }
  }

  Widget _picker(List<(String, String)> catalog, List<String> selected) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in catalog)
          FilterChip(
            label: Text(f.$2),
            selected: selected.contains(f.$1),
            onSelected: (v) => setState(() => v ? selected.add(f.$1) : selected.remove(f.$1)),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      appBar: AppBar(title: Text(widget.template == null ? 'Nueva plantilla' : 'Editar plantilla')),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line)), boxShadow: softShadow(context)),
        child: SafeArea(
          top: false,
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Row(children: [
                OutlinedButton.icon(onPressed: _saving ? null : () => _save(preview: true), icon: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: const Text('Guardar y ver PDF')),
                const Spacer(),
                OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
                const SizedBox(width: 10),
                FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar')),
              ]),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(padding: const EdgeInsets.all(24), children: [
            SwissSection('General', [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre de la plantilla *')),
              const SizedBox(height: 16),
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Título del documento')),
              const SizedBox(height: 16),
              TextField(
                controller: _intro,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Texto introductorio', helperText: 'Puedes usar {empleado} y {fecha}. Déjalo vacío si no quieres texto.'),
              ),
              const SizedBox(height: 16),
              Row(children: [
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: false, label: Text('Vertical')), ButtonSegment(value: true, label: Text('Horizontal'))],
                  selected: {_land},
                  onSelectionChanged: (s) => setState(() => _land = s.first),
                ),
                const SizedBox(width: 20),
                Expanded(child: SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Mostrar fecha'), value: _showDate, onChanged: (v) => setState(() => _showDate = v))),
              ]),
            ]),
            SwissSection('Datos del empleado', [
              Text('Toca para activar o quitar. Aparecen en el orden en que los eliges.', style: TextStyle(color: c.muted, fontSize: 13)),
              const SizedBox(height: 12),
              _picker(kActaEmployeeFields, _emp),
              const SizedBox(height: 10),
              Text('Orden: ${_emp.map((k) => _labelOf(kActaEmployeeFields, k)).join(' → ').ifEmpty('(ninguno)')}', style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
            SwissSection('Columnas de la tabla de equipos', [
              _picker(kActaAssetColumns, _cols),
              const SizedBox(height: 10),
              Text('Orden: ${_cols.map((k) => _labelOf(kActaAssetColumns, k)).join(' → ').ifEmpty('(ninguna)')}', style: TextStyle(fontSize: 12, color: c.muted)),
              const SizedBox(height: 16),
              SizedBox(
                width: 260,
                child: TextField(controller: _rows, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Filas vacías (hoja a mano)', helperText: 'Entre 0 y 40')),
              ),
            ]),
            SwissSection('Firmas y pie', [
              TextField(
                controller: _sigs,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Firmas (una por línea, máximo 4)', alignLabelWithHint: true),
              ),
              const SizedBox(height: 16),
              TextField(controller: _footer, maxLines: 3, decoration: const InputDecoration(labelText: 'Texto al pie (opcional)', alignLabelWithHint: true)),
            ]),
          ]),
        ),
      ),
    );
  }
}
