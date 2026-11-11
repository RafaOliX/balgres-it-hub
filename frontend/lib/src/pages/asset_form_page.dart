import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../models/category.dart';
import '../models/it_asset.dart';
import '../ui/swiss.dart';
import '../widgets/form_fields.dart';
import '../widgets/search_select.dart';

class AssetFormPage extends ConsumerStatefulWidget {
  /// Si viene un activo, se usa como base (duplicar).
  final ItAsset? template;
  const AssetFormPage({super.key, this.template});
  @override
  ConsumerState<AssetFormPage> createState() => _AssetFormPageState();
}

class _AssetFormPageState extends ConsumerState<AssetFormPage> {
  final _form = GlobalKey<FormState>();
  final _tag = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _notes = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _copies = TextEditingController(text: '1');
  final Map<String, TextEditingController> _specCtrls = {};
  static const _uniqueSpecs = {'ip', 'mac', 'hostname'};

  Category? _selectedCategory;
  String _unit = 'Unidad';
  String _status = 'Operativo';
  int? _locationId;
  final List<XFile> _files = [];
  bool _saving = false;
  bool _cargandoTag = false;

  Timer? _autosaveTimer;
  bool _hasChanges = false;
  bool _autoSaved = false;
  bool _autoFailed = false;
  String? _draftTag;

  @override
  void initState() {
    super.initState();
    for (final c in [_brand, _model, _serial, _notes, _quantity]) {
      c.addListener(_markChanged);
    }
    _autosaveTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_hasChanges && !_saving && _tag.text.isNotEmpty && _selectedCategory != null &&
          (_brand.text.trim().isNotEmpty || _model.text.trim().isNotEmpty || _serial.text.trim().isNotEmpty)) {
        _saveDraftSilently();
      }
    });
    final t = widget.template;
    if (t != null) WidgetsBinding.instance.addPostFrameCallback((_) => _applyTemplate(t));
  }

  void _markChanged() => _hasChanges = true;

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------------------------------------------------------- copiar datos de otro equipo
  void _fill(ItAsset t) {
    setState(() {
      _brand.text = t.brand;
      _model.text = t.model;
      _notes.text = t.notes ?? '';
      _locationId = t.locationId;
      _status = t.status ?? 'Operativo';
      t.specs.forEach((k, v) {
        if (_uniqueSpecs.contains(k.toLowerCase())) return; // IP, MAC y hostname no se repiten
        final ctrl = _specCtrls.putIfAbsent(k, () => TextEditingController()..addListener(_markChanged));
        ctrl.text = v;
      });
      _hasChanges = true;
    });
  }

  Future<void> _applyTemplate(ItAsset t) async {
    try {
      final cats = await ref.read(categoriasListProvider.future);
      final cat = cats.where((c) => c.id == t.categoryId).firstOrNull;
      if (cat != null) await _onCategorySelected(cat);
    } catch (_) {}
    if (mounted) _fill(t);
  }

  ItAsset? _lastOf(Category cat, {String? brand, String? model}) {
    final items = ref.read(inventarioListProvider).valueOrNull ?? const <ItAsset>[];
    final l = items.where((a) {
      if (a.isDraft || a.categoryId != cat.id) return false;
      if (brand != null && a.brand.trim().toLowerCase() != brand.trim().toLowerCase()) return false;
      if (model != null && a.model.trim().toLowerCase() != model.trim().toLowerCase()) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return l.firstOrNull;
  }

  void _copyLast() {
    final cat = _selectedCategory;
    if (cat == null) return;
    final last = _lastOf(cat);
    if (last == null) {
      _snack('Aún no hay equipos registrados en esta categoría');
      return;
    }
    _fill(last);
    _snack('Datos copiados de ${last.assetTag}. Falta el S/N.');
  }

  /// Al elegir un modelo ya usado, completa solo lo que esté vacío.
  void _onModelPicked(String model) {
    final cat = _selectedCategory;
    if (cat == null) return;
    final ref0 = _lastOf(cat, brand: _brand.text, model: model);
    if (ref0 == null) return;
    setState(() {
      ref0.specs.forEach((k, v) {
        if (_uniqueSpecs.contains(k.toLowerCase())) return;
        final ctrl = _specCtrls[k];
        if (ctrl != null && ctrl.text.trim().isEmpty) ctrl.text = v;
      });
    });
  }

  // ---------------------------------------------------------------- guardado
  ItAssetCreate _buildCreate(bool draft, {String? tag, bool noSerial = false}) => ItAssetCreate(
        assetTag: tag ?? _tag.text.trim(), category: _selectedCategory!.name, categoryId: _selectedCategory!.id,
        brand: _brand.text.trim(), model: _model.text.trim(), serialNumber: noSerial ? '' : _serial.text.trim(),
        locationId: _locationId, status: _status, notes: _notes.text.trim(),
        quantity: int.tryParse(_quantity.text) ?? 1, unit: _unit, isDraft: draft,
        specs: collectSpecs(_specCtrls),
      );

  Map<String, dynamic> _buildPatch(bool draft) => {
        'brand': _brand.text.trim(), 'model': _model.text.trim(), 'serial_number': _serial.text.trim(),
        'status': _status, 'notes': _notes.text.trim(), 'quantity': int.tryParse(_quantity.text) ?? 1,
        'location_id': _locationId, 'is_draft': draft,
        'specs': collectSpecs(_specCtrls),
      };

  Future<void> _saveDraftSilently() async {
    _hasChanges = false;
    try {
      final api = ref.read(inventarioApiProvider);
      if (_draftTag == null) {
        final asset = await api.crear(_buildCreate(true));
        _draftTag = asset.assetTag;
      } else {
        await api.actualizar(_draftTag!, _buildPatch(true));
      }
      if (mounted) setState(() { _autoSaved = true; _autoFailed = false; });
    } catch (_) {
      _hasChanges = true; // reintenta en el próximo ciclo
      if (mounted) setState(() => _autoFailed = true);
    }
  }

  void _rebuildSpecs(Category cat) {
    final old = Map<String, TextEditingController>.from(_specCtrls);
    _specCtrls.clear();
    for (final f in cat.specFields) {
      _specCtrls[f] = old.remove(f) ?? (TextEditingController()..addListener(_markChanged));
    }
    for (final c in old.values) {
      c.dispose();
    }
  }

  Future<void> _onCategorySelected(Category? cat) async {
    if (cat == null) return;
    setState(() {
      _selectedCategory = cat;
      _unit = cat.unit;
      _cargandoTag = true;
      _rebuildSpecs(cat);
    });
    try {
      final nextTag = await ref.read(inventarioApiProvider).getSiguienteTag(cat.id);
      if (mounted) setState(() => _tag.text = nextTag);
      _hasChanges = true;
    } catch (_) {
      if (mounted) setState(() => _tag.text = '');
    } finally {
      if (mounted) setState(() => _cargandoTag = false);
    }
  }

  Future<void> _generarNuevoTag() async {
    if (_selectedCategory == null) return;
    setState(() => _cargandoTag = true);
    try {
      final nextTag = await ref.read(inventarioApiProvider).getSiguienteTag(_selectedCategory!.id);
      if (mounted) setState(() => _tag.text = nextTag);
    } catch (_) {} finally {
      if (mounted) setState(() => _cargandoTag = false);
    }
  }

  Future<void> _crearCategoriaRapida() async {
    final nameCtrl = TextEditingController();
    final prefixCtrl = TextEditingController();
    String unit = 'Unidad';
    bool reqSn = true;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Nueva categoría'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
              const SizedBox(height: 12),
              TextField(controller: prefixCtrl, decoration: const InputDecoration(labelText: 'Prefijo')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: unit, decoration: const InputDecoration(labelText: 'Unidad'),
                items: ['Unidad', 'Metro', 'Caja', 'Rollo'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setModalState(() => unit = v!),
              ),
              CheckboxListTile(title: const Text('¿Requiere S/N?'), value: reqSn, onChanged: (v) => setModalState(() => reqSn = v!)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty || prefixCtrl.text.isEmpty) return;
                try {
                  final newCat = await ref.read(inventarioApiProvider).crearCategoria(
                    Category(id: 0, name: nameCtrl.text, prefix: prefixCtrl.text, unit: unit, requiresSn: reqSn),
                  );
                  ref.invalidate(categoriasListProvider);
                  await ref.read(categoriasListProvider.future);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _onCategorySelected(newCat);
                } catch (e) {
                  _snack('Error: ${apiError(e)}');
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImages(ImageSource source) async {
    final picker = ImagePicker();
    if (source == ImageSource.camera) {
      final XFile? photo = await picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85);
      if (photo != null) setState(() => _files.add(photo));
    } else {
      final photos = await picker.pickMultiImage(maxWidth: 1600, imageQuality: 85);
      if (photos.isNotEmpty) setState(() => _files.addAll(photos));
    }
  }

  /// [another]: tras guardar, deja el formulario listo para el siguiente equipo.
  Future<void> _submit({bool another = false}) async {
    if (!_form.currentState!.validate() || _selectedCategory == null) return;
    final cat = _selectedCategory!;
    final copies = (int.tryParse(_copies.text.trim()) ?? 1).clamp(1, 50);
    final asDraft = copies > 1 && cat.requiresSn && _serial.text.trim().isEmpty;
    setState(() => _saving = true);
    try {
      final api = ref.read(inventarioApiProvider);
      final created = <String>[];
      if (_draftTag == null) {
        created.add((await api.crear(_buildCreate(asDraft), autoTag: true)).assetTag);
      } else {
        await api.actualizar(_draftTag!, _buildPatch(asDraft));
        created.add(_draftTag!);
      }
      for (var i = 1; i < copies; i++) {
        created.add((await api.crear(_buildCreate(asDraft, noSerial: true), autoTag: true)).assetTag);
      }
      if (_files.isNotEmpty) {
        for (final t in created) {
          await api.subirImagenes(t, _files);
        }
      }
      ref.invalidate(inventarioListProvider);

      final msg = copies > 1
          ? '${created.length} equipos creados (${created.first} … ${created.last})${asDraft ? '. Quedaron como borradores: completa el S/N de cada uno.' : ''}'
          : 'Guardado: ${created.first}';
      if (another) {
        _snack(msg);
        _resetForNext();
      } else {
        _snack(msg);
        if (mounted) context.pop();
      }
    } catch (e) {
      final msg = apiError(e);
      final isTagError = msg.contains('Tag');
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(isTagError ? Icons.warning_amber_rounded : Icons.error_outline, color: isTagError ? context.sw.warn : context.sw.bad, size: 40),
            title: Text(isTagError ? 'Tag duplicado' : 'No se pudo guardar'),
            content: Text(msg),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
              if (isTagError) FilledButton(onPressed: () { Navigator.pop(ctx); _generarNuevoTag(); }, child: const Text('Generar nuevo Tag')),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForNext() {
    setState(() {
      _draftTag = null;
      _autoSaved = false;
      _hasChanges = false;
      _serial.clear();
      _files.clear();
      _copies.text = '1';
      _specCtrls.forEach((k, c) {
        if (_uniqueSpecs.contains(k.toLowerCase())) c.clear();
      });
    });
    _generarNuevoTag();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    for (final c in [_tag, _brand, _model, _serial, _notes, _quantity, _copies, ..._specCtrls.values]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final categoriasAsync = ref.watch(categoriasListProvider);
    final hints = ref.watch(hintsProvider);
    final busy = _saving || _cargandoTag;

    return Scaffold(
      appBar: AppBar(title: Text(widget.template != null ? 'Duplicar activo' : 'Nuevo activo')),
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
                if (_autoFailed) Text('No se pudo guardar el borrador: revisa la conexión', style: TextStyle(color: c.bad, fontSize: 12))
                else if (_autoSaved) Text('Borrador guardado', style: TextStyle(color: c.ok, fontSize: 12)),
                const Spacer(),
                OutlinedButton(onPressed: busy ? null : () => _submit(another: true), child: const Text('Guardar y crear otro')),
                const SizedBox(width: 10),
                FilledButton(onPressed: busy ? null : () => _submit(), child: Text(_saving ? 'Guardando…' : 'Guardar y finalizar')),
              ]),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(24), children: [
              FormSection('Identificación', [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: categoriasAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Error: $e'),
                      data: (cats) => SearchSelect<Category>(
                        label: 'Categoría', required: true, allowClear: false, value: _selectedCategory, options: cats,
                        display: (x) => x.name, searchText: (x) => x.prefix, subtitle: (x) => 'Prefijo ${x.prefix} · ${x.unit}',
                        onChanged: _onCategorySelected,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(onPressed: _crearCategoriaRapida, icon: const Icon(Icons.add), tooltip: 'Crear categoría'),
                ]),
                if (_selectedCategory != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(onPressed: _copyLast, icon: const Icon(Icons.content_copy, size: 16), label: Text('Copiar datos del último de ${_selectedCategory!.name}')),
                  ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tag, readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Asset Tag (automático)',
                        suffixIcon: _cargandoTag ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : const Icon(Icons.lock, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(onPressed: _generarNuevoTag, icon: const Icon(Icons.refresh), tooltip: 'Regenerar tag'),
                ]),
                if (_selectedCategory?.requiresSn == true) ...[
                  const SizedBox(height: 16),
                  TextFormField(controller: _serial, decoration: const InputDecoration(labelText: 'N/S *')),
                ],
              ]),
              FormSection('Detalles del equipo', [
                Row(children: [
                  Expanded(child: SuggestField(controller: _brand, label: 'Marca', suggestions: () => hints.brands)),
                  const SizedBox(width: 16),
                  Expanded(child: SuggestField(controller: _model, label: 'Modelo', suggestions: () => hints.modelsFor(_brand.text), onPicked: _onModelPicked)),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: TextFormField(controller: _quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad'))),
                  const SizedBox(width: 16),
                  Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: 'Unidad'), child: Text(_unit))),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: 360,
                  child: TextFormField(
                    controller: _copies,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Crear varios iguales (cantidad de equipos)', helperText: 'Tags consecutivos. Si pide S/N, quedan como borradores.'),
                  ),
                ),
              ]),
              FormSection('Datos técnicos', [SpecsFields(ctrls: _specCtrls, hints: hints.specs)]),
              FormSection('Ubicación y estado', [
                LocationDropdown(value: _locationId, onChanged: (v) => setState(() { _locationId = v; _hasChanges = true; })),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _status, decoration: const InputDecoration(labelText: 'Estado'),
                  items: ['Operativo', 'En Revisión', 'Retirado'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setState(() { _status = v!; _hasChanges = true; }),
                ),
                const SizedBox(height: 16),
                TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas'), maxLines: 3),
                const SizedBox(height: 8),
                Text('El responsable se asigna desde el detalle del activo (pestaña Asignaciones).', style: TextStyle(color: c.muted, fontSize: 12)),
              ]),
              FormSection('Fotografía', [
                GestureDetector(
                  onTap: () => showModalBottomSheet(
                    context: context,
                    builder: (_) => SafeArea(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Tomar foto'), onTap: () { Navigator.pop(context); _pickImages(ImageSource.camera); }),
                        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir de galería'), onTap: () { Navigator.pop(context); _pickImages(ImageSource.gallery); }),
                      ]),
                    ),
                  ),
                  child: Container(
                    height: 110, width: double.infinity,
                    decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo_outlined, color: c.muted, size: 30), const SizedBox(height: 8), Text('Agregar fotos', style: TextStyle(color: c.muted))]),
                  ),
                ),
                if (_files.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal, itemCount: _files.length, separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => Stack(children: [
                        FutureBuilder(
                          future: _files[i].readAsBytes(),
                          builder: (_, snap) => snap.hasData
                              ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(snap.data!, width: 100, height: 100, fit: BoxFit.cover))
                              : Container(width: 100, height: 100, color: c.panel),
                        ),
                        Positioned(top: 4, right: 4, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 16), style: IconButton.styleFrom(backgroundColor: c.bad), onPressed: () => setState(() => _files.removeAt(i)))),
                      ]),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ),
    );
  }
}
