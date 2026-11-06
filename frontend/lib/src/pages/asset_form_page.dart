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
  String? _error;

  Future<void> _onCategorySelected(Category? cat) async {
    if (cat == null) return;
    setState(() { 
      _selectedCategory = cat; 
      _unit = cat.unit; 
      _cargandoTag = true; 
    });
    try {
      final nextTag = await ref.read(inventarioApiProvider).getSiguienteTag(cat.id);
      setState(() => _tag.text = nextTag);
    } catch (e) {
      setState(() => _tag.text = '');
    } finally {
      setState(() => _cargandoTag = false);
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre (Ej: Cable HDMI)')),
              TextField(controller: prefixCtrl, decoration: const InputDecoration(labelText: 'Prefijo (Ej: HDMI)')),
              DropdownButtonFormField<String>(
                value: unit, decoration: const InputDecoration(labelText: 'Unidad'),
                items: ['Unidad', 'Metro', 'Caja', 'Rollo'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setModalState(() => unit = v!),
              ),
              CheckboxListTile(
                title: const Text('¿Requiere S/N?'), value: reqSn,
                onChanged: (v) => setModalState(() => reqSn = v!),
              )
            ],
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
                  _onCategorySelected(newCat); // Auto-seleccionar la nueva
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
    final picked = source == ImageSource.gallery ? await picker.pickMultiImage(maxWidth: 1600, imageQuality: 85) : [if (await picker.pickImage(source: ImageSource.camera) != null) (await picker.pickImage(source: ImageSource.camera))!].whereType<XFile>().toList();
    if (picked.isEmpty) return;
    setState(() => _files.addAll(picked));
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _selectedCategory == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      final api = ref.read(inventarioApiProvider);
      final asset = await api.crear(ItAssetCreate(
        assetTag: _tag.text.trim(), category: _selectedCategory!.name, categoryId: _selectedCategory!.id,
        brand: _brand.text.trim(), model: _model.text.trim(), serialNumber: _serial.text.trim(),
        location: _location.text.trim(), status: _status, notes: _notes.text.trim(),
        quantity: int.tryParse(_quantity.text) ?? 1, unit: _unit, assignedTo: _assignedTo.text.trim(),
      ));
      if (_files.isNotEmpty) await api.subirImagenes(asset.assetTag, _files);
      ref.invalidate(inventarioListProvider);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriasAsync = ref.watch(categoriasListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo activo')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            GestureDetector(
              onTap: () => _pickImages(ImageSource.gallery),
              child: Container(
                height: 100, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo_outlined, color: Colors.grey), Text('Fotos')]),
              ),
            ),
            const SizedBox(height: 16),
            
            // SELECTOR DE CATEGORÍA CON BOTÓN DE CREAR
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: categoriasAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Error: $e'),
                    data: (cats) => DropdownButtonFormField<Category>(
                      value: _selectedCategory,
                      decoration: const InputDecoration(labelText: 'Categoría *'),
                      items: cats.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                      onChanged: _onCategorySelected,
                      validator: (v) => v == null ? 'Requerido' : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _crearCategoriaRapida,
                  icon: const Icon(Icons.add),
                  tooltip: 'Crear nueva categoría',
                ),
              ],
            ),
            const SizedBox(height: 10),
            
            TextFormField(
              controller: _tag, readOnly: true,
              decoration: InputDecoration(
                labelText: 'Asset Tag (Automático)',
                suffixIcon: _cargandoTag ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : const Icon(Icons.lock, size: 18),
              ),
            ),
            const SizedBox(height: 10),

            Row(children: [
              Expanded(child: TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Marca'))),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: _model, decoration: const InputDecoration(labelText: 'Modelo'))),
            ]),
            
            // S/N dinámico (solo si la categoría lo requiere)
            if (_selectedCategory?.requiresSn ?? true)
              TextFormField(controller: _serial, decoration: const InputDecoration(labelText: 'S/N (Opcional)')),
            
            Row(children: [
              Expanded(child: TextFormField(controller: _quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad'))),
              const SizedBox(width: 10),
              Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: 'Unidad'), child: Text(_unit))), // Unidad bloqueada por la categoría
            ]),
            
            TextFormField(controller: _assignedTo, decoration: const InputDecoration(labelText: 'Asignado a (Responsable)')),
            TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'Ubicación Física')),
            DropdownButtonFormField<String>(
              value: _status, decoration: const InputDecoration(labelText: 'Estado'),
              items: ['Operativo', 'En Revisión', 'Retirado'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => _status = v!),
            ),
            TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas'), maxLines: 2),
            
            const SizedBox(height: 24),
            FilledButton(
              onPressed: (_saving || _cargandoTag) ? null : _submit, 
              child: Text(_saving ? 'Guardando...' : 'Guardar activo')
            ),
          ],
        ),
      ),
    );
  }
}
