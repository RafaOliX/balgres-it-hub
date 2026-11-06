import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../data/providers.dart';
import '../models/it_asset.dart';
import '../models/category.dart';

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
  final _location = TextEditingController();
  final _assignedTo = TextEditingController();
  final _notes = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  
  Category? _selectedCategory;
  String _unit = 'Unidad';
  String _status = 'Operativo';
  final List<XFile> _files = [];
  bool _saving = false;
  bool _cargandoTag = false;
  
  Timer? _autosaveTimer;
  bool _hasChanges = false;
  bool _autoSaved = false;
  String? _draftTag; // Guarda el tag del borrador actual para hacer PATCH

  @override
  void initState() {
    super.initState();
    _tag.addListener(_markChanged);
    _brand.addListener(_markChanged);
    _model.addListener(_markChanged);
    _serial.addListener(_markChanged);
    _location.addListener(_markChanged);
    _assignedTo.addListener(_markChanged);
    _notes.addListener(_markChanged);
    _quantity.addListener(_markChanged);
    
    _autosaveTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_hasChanges && !_saving && _tag.text.isNotEmpty && _selectedCategory != null) {
        _saveDraftSilently();
      }
    });
  }

  void _markChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  Future<void> _saveDraftSilently() async {
    _hasChanges = false;
    try {
      final api = ref.read(inventarioApiProvider);
      if (_draftTag == null) {
        // Crear el borrador por primera vez
        final asset = await api.crear(ItAssetCreate(
          assetTag: _tag.text.trim(), category: _selectedCategory!.name, categoryId: _selectedCategory!.id,
          brand: _brand.text.trim(), model: _model.text.trim(), serialNumber: _serial.text.trim(),
          location: _location.text.trim(), status: _status, notes: _notes.text.trim(),
          quantity: int.tryParse(_quantity.text) ?? 1, unit: _unit, assignedTo: _assignedTo.text.trim(),
          isDraft: true,
        ));
        _draftTag = asset.assetTag;
      } else {
        // Actualizar el borrador existente
        await api.actualizar(_draftTag!, {
          'brand': _brand.text.trim(), 'model': _model.text.trim(), 'serial_number': _serial.text.trim(),
          'location': _location.text.trim(), 'notes': _notes.text.trim(),
          'quantity': int.tryParse(_quantity.text) ?? 1, 'assigned_to': _assignedTo.text.trim(),
          'is_draft': true,
        });
      }
      if (mounted) setState(() => _autoSaved = true);
    } catch (e) {
      // Ignorar errores de autoguardado silencioso
    }
  }

  Future<void> _onCategorySelected(Category? cat) async {
    if (cat == null) return;
    setState(() { _selectedCategory = cat; _unit = cat.unit; _cargandoTag = true; });
    try {
      final nextTag = await ref.read(inventarioApiProvider).getSiguienteTag(cat.id);
      setState(() => _tag.text = nextTag);
      _hasChanges = true;
    } catch (e) {
      setState(() => _tag.text = '');
    } finally {
      setState(() => _cargandoTag = false);
    }
  }

  Future<void> _generarNuevoTag() async {
    if (_selectedCategory == null) return;
    setState(() => _cargandoTag = true);
    try {
      final nextTag = await ref.read(inventarioApiProvider).getSiguienteTag(_selectedCategory!.id);
      setState(() => _tag.text = nextTag);
    } catch (e) {} finally { setState(() => _cargandoTag = false); }
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
                  final newCat = await ref.read(inventarioApiProvider).crearCategoria(Category(
                    id: 0, name: nameCtrl.text, prefix: prefixCtrl.text, unit: unit, requiresSn: reqSn,
                  ));
                  ref.invalidate(categoriasListProvider);
                  if (mounted) Navigator.pop(ctx);
                  _onCategorySelected(newCat);
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Crear'),
            )
          ],
        )
      )
    );
  }

  Future<void> _pickImages(ImageSource source) async {
    final picker = ImagePicker();
    if (source == ImageSource.camera) {
      final XFile? photo = await picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85);
      if (photo != null) setState(() => _files.add(photo));
    } else {
      final List<XFile> photos = await picker.pickMultiImage(maxWidth: 1600, imageQuality: 85);
      if (photos.isNotEmpty) setState(() => _files.addAll(photos));
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _selectedCategory == null) return;
    setState(() { _saving = true; });
    try {
      final api = ref.read(inventarioApiProvider);
      
      if (_draftTag == null) {
        // Si no se ha creado el borrador aún, lo creamos como final
        final asset = await api.crear(ItAssetCreate(
          assetTag: _tag.text.trim(), category: _selectedCategory!.name, categoryId: _selectedCategory!.id,
          brand: _brand.text.trim(), model: _model.text.trim(), serialNumber: _serial.text.trim(),
          location: _location.text.trim(), status: _status, notes: _notes.text.trim(),
          quantity: int.tryParse(_quantity.text) ?? 1, unit: _unit, assignedTo: _assignedTo.text.trim(),
          isDraft: false,
        ));
        if (_files.isNotEmpty) await api.subirImagenes(asset.assetTag, _files);
      } else {
        // Si ya era un borrador, lo actualizamos y le quitamos el is_draft
        await api.actualizar(_draftTag!, {
          'brand': _brand.text.trim(), 'model': _model.text.trim(), 'serial_number': _serial.text.trim(),
          'location': _location.text.trim(), 'status': _status, 'notes': _notes.text.trim(),
          'quantity': int.tryParse(_quantity.text) ?? 1, 'assigned_to': _assignedTo.text.trim(),
          'is_draft': false,
        });
        if (_files.isNotEmpty) await api.subirImagenes(_draftTag!, _files);
      }
      
      ref.invalidate(inventarioListProvider);
      if (mounted) context.pop();
    } catch (e) {
      String friendlyMsg = 'Error al guardar.';
      bool isTagError = false;
      
      if (e is DioException && e.response?.data is Map && e.response!.data['detail'] != null) {
        friendlyMsg = e.response!.data['detail'].toString();
        if (friendlyMsg.contains('Tag')) isTagError = true;
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(isTagError ? Icons.warning_amber_rounded : Icons.error_outline, color: isTagError ? Colors.orange : Colors.red, size: 40),
            title: Text(isTagError ? 'Tag duplicado' : 'Error de validación'),
            content: Text(friendlyMsg),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
              if (isTagError)
                FilledButton(
                  onPressed: () { Navigator.pop(ctx); _generarNuevoTag(); },
                  child: const Text('Generar nuevo Tag'),
                ),
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
    super.dispose();
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 24), elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE5E7EB))),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6B7280), letterSpacing: 0.8)),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriasAsync = ref.watch(categoriasListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Nuevo activo'), backgroundColor: Colors.white, elevation: 0.5,
        actions: [
          if (_autoSaved) const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: Text('Borrador guardado', style: TextStyle(color: Colors.green, fontSize: 12))),
          )
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _section('Fotografía', [
                  GestureDetector(
                    onTap: () => showModalBottomSheet(
                      context: context,
                      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Tomar foto'), onTap: () { Navigator.pop(context); _pickImages(ImageSource.camera); }),
                        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir de galería'), onTap: () { Navigator.pop(context); _pickImages(ImageSource.gallery); }),
                      ])),
                    ),
                    child: Container(
                      height: 120, width: double.infinity, decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
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
                          FutureBuilder(future: _files[i].readAsBytes(), builder: (_, snap) => snap.hasData ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(snap.data!, width: 100, height: 100, fit: BoxFit.cover)) : Container(width: 100, height: 100, color: Colors.grey[200])),
                          Positioned(top: 4, right: 4, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 16), style: IconButton.styleFrom(backgroundColor: Colors.red), onPressed: () => setState(() => _files.removeAt(i)))),
                        ]),
                      ),
                    ),
                  ]
                ]),

                _section('Identificación', [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: categoriasAsync.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (e, _) => Text('Error: $e'),
                          data: (cats) => DropdownButtonFormField<Category>(
                            value: _selectedCategory, decoration: const InputDecoration(labelText: 'Categoría *', border: OutlineInputBorder()),
                            items: cats.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                            onChanged: _onCategorySelected, validator: (v) => v == null ? 'Requerido' : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(onPressed: _crearCategoriaRapida, icon: const Icon(Icons.add), tooltip: 'Crear nueva'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
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
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(controller: _serial, decoration: const InputDecoration(labelText: 'N/S (Opcional)', border: OutlineInputBorder())),
                ]),

                _section('Detalles del Equipo', [
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

                _section('Asignación y Ubicación', [
                  TextFormField(controller: _assignedTo, decoration: const InputDecoration(labelText: 'Asignado a (Responsable)', border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'Ubicación Física', border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _status, decoration: const InputDecoration(labelText: 'Estado', border: OutlineInputBorder()),
                    items: ['Operativo', 'En Revisión', 'Retirado'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => _status = v!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas', border: OutlineInputBorder()), maxLines: 3),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
