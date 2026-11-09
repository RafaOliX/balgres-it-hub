import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../models/category.dart';
import '../models/it_asset.dart';
import '../widgets/form_fields.dart';

class AssetFormPage extends ConsumerStatefulWidget {
  const AssetFormPage({super.key});
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
  final _cost = TextEditingController();
  final _supplier = TextEditingController();
  final _invoice = TextEditingController();
  final Map<String, TextEditingController> _specCtrls = {};

  Category? _selectedCategory;
  String _unit = 'Unidad';
  String _status = 'Operativo';
  int? _locationId;
  DateTime? _purchaseDate, _warrantyUntil;
  final List<XFile> _files = [];
  bool _saving = false;
  bool _cargandoTag = false;

  Timer? _autosaveTimer;
  bool _hasChanges = false;
  bool _autoSaved = false;
  String? _draftTag;

  @override
  void initState() {
    super.initState();
    for (final c in [_brand, _model, _serial, _notes, _quantity, _cost, _supplier, _invoice]) {
      c.addListener(_markChanged);
    }
    _autosaveTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_hasChanges && !_saving && _tag.text.isNotEmpty && _selectedCategory != null) _saveDraftSilently();
    });
  }

  void _markChanged() => _hasChanges = true;

  ItAssetCreate _buildCreate(bool draft) => ItAssetCreate(
        assetTag: _tag.text.trim(), category: _selectedCategory!.name, categoryId: _selectedCategory!.id,
        brand: _brand.text.trim(), model: _model.text.trim(), serialNumber: _serial.text.trim(),
        locationId: _locationId, status: _status, notes: _notes.text.trim(),
        quantity: int.tryParse(_quantity.text) ?? 1, unit: _unit, isDraft: draft,
        purchaseDate: _purchaseDate, cost: parseCost(_cost.text), supplier: _supplier.text.trim(),
        invoiceNumber: _invoice.text.trim(), warrantyUntil: _warrantyUntil, specs: collectSpecs(_specCtrls),
      );

  Map<String, dynamic> _buildPatch(bool draft) => {
        'brand': _brand.text.trim(), 'model': _model.text.trim(), 'serial_number': _serial.text.trim(),
        'status': _status, 'notes': _notes.text.trim(), 'quantity': int.tryParse(_quantity.text) ?? 1,
        'location_id': _locationId, 'is_draft': draft,
        'purchase_date': dateToApi(_purchaseDate), 'cost': parseCost(_cost.text), 'supplier': _supplier.text.trim(),
        'invoice_number': _invoice.text.trim(), 'warranty_until': dateToApi(_warrantyUntil), 'specs': collectSpecs(_specCtrls),
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
      if (mounted) setState(() => _autoSaved = true);
    } catch (_) {
      // el autoguardado es silencioso
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
          title: const Text('Nueva Categoría'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: prefixCtrl, decoration: const InputDecoration(labelText: 'Prefijo', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: unit, decoration: const InputDecoration(labelText: 'Unidad', border: OutlineInputBorder()),
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
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${apiError(e)}')));
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

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _selectedCategory == null) return;
    setState(() => _saving = true);
    try {
      final api = ref.read(inventarioApiProvider);
      if (_draftTag == null) {
        final asset = await api.crear(_buildCreate(false));
        if (_files.isNotEmpty) await api.subirImagenes(asset.assetTag, _files);
      } else {
        await api.actualizar(_draftTag!, _buildPatch(false));
        if (_files.isNotEmpty) await api.subirImagenes(_draftTag!, _files);
      }
      ref.invalidate(inventarioListProvider);
      if (mounted) context.pop();
    } catch (e) {
      final msg = apiError(e);
      final isTagError = msg.contains('Tag');
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(isTagError ? Icons.warning_amber_rounded : Icons.error_outline, color: isTagError ? Colors.orange : Colors.red, size: 40),
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

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    for (final c in [_tag, _brand, _model, _serial, _notes, _quantity, _cost, _supplier, _invoice, ..._specCtrls.values]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriasAsync = ref.watch(categoriasListProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Nuevo activo'), backgroundColor: Colors.white, elevation: 0.5,
        actions: [if (_autoSaved) const Padding(padding: EdgeInsets.only(right: 16), child: Center(child: Text('Borrador guardado', style: TextStyle(color: Colors.green, fontSize: 12))))],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(24), children: [
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
                    height: 120, width: double.infinity,
                    decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo_outlined, color: Colors.grey, size: 32), SizedBox(height: 8), Text('Agregar fotos', style: TextStyle(color: Colors.grey))]),
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
                              : Container(width: 100, height: 100, color: Colors.grey[200]),
                        ),
                        Positioned(top: 4, right: 4, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 16), style: IconButton.styleFrom(backgroundColor: Colors.red), onPressed: () => setState(() => _files.removeAt(i)))),
                      ]),
                    ),
                  ),
                ],
              ]),
              FormSection('Identificación', [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: categoriasAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Error: $e'),
                      data: (cats) => DropdownButtonFormField<int>(
                        value: _selectedCategory?.id, isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Categoría *', border: OutlineInputBorder()),
                        items: cats.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                        onChanged: (id) => _onCategorySelected(cats.where((c) => c.id == id).firstOrNull),
                        validator: (v) => v == null ? 'Requerido' : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(onPressed: _crearCategoriaRapida, icon: const Icon(Icons.add), tooltip: 'Crear nueva'),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tag, readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Asset Tag (Automático)', border: const OutlineInputBorder(), filled: true, fillColor: Colors.grey[50],
                        suffixIcon: _cargandoTag ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : const Icon(Icons.lock, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(onPressed: _generarNuevoTag, icon: const Icon(Icons.refresh), tooltip: 'Regenerar Tag'),
                ]),
                if (_selectedCategory?.requiresSn == true) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _serial,
                    decoration: const InputDecoration(labelText: 'N/S *', border: OutlineInputBorder()),
                  ),
                ],
              ]),
              FormSection('Detalles del equipo', [
                Row(children: [
                  Expanded(child: TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Marca', border: OutlineInputBorder()))),
                  const SizedBox(width: 16),
                  Expanded(child: TextFormField(controller: _model, decoration: const InputDecoration(labelText: 'Modelo', border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: TextFormField(controller: _quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad', border: OutlineInputBorder()))),
                  const SizedBox(width: 16),
                  Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: 'Unidad', border: OutlineInputBorder()), child: Text(_unit))),
                ]),
              ]),
              FormSection('Datos técnicos', [SpecsFields(ctrls: _specCtrls)]),
              FormSection('Compra y garantía', [
                PurchaseFields(
                  purchaseDate: _purchaseDate, warrantyUntil: _warrantyUntil,
                  onPurchase: (d) => setState(() { _purchaseDate = d; _hasChanges = true; }),
                  onWarranty: (d) => setState(() { _warrantyUntil = d; _hasChanges = true; }),
                  cost: _cost, supplier: _supplier, invoice: _invoice,
                ),
              ]),
              FormSection('Ubicación y estado', [
                LocationDropdown(value: _locationId, onChanged: (v) => setState(() { _locationId = v; _hasChanges = true; })),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _status, decoration: const InputDecoration(labelText: 'Estado', border: OutlineInputBorder()),
                  items: ['Operativo', 'En Revisión', 'Retirado'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setState(() { _status = v!; _hasChanges = true; }),
                ),
                const SizedBox(height: 16),
                TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas', border: OutlineInputBorder()), maxLines: 3),
                const SizedBox(height: 8),
                const Text('El responsable se asigna desde el detalle del activo (pestaña Asignaciones).', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: (_saving || _cargandoTag) ? null : _submit,
                  child: _saving ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Guardar y Finalizar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ),
      ),
    );
  }
}
