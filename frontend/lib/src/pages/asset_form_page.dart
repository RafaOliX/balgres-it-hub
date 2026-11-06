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
    setState(() { _selectedCategory = cat; _unit = cat.unit; _cargandoTag = true; });
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

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE5E7EB))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6B7280), letterSpacing: 0.6)),
            const SizedBox(height: 16),
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
        title: const Text('Nuevo activo'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: Center( // Centrar el formulario
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800), // Ancho máximo cómodo
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                
                _section('Fotografía', [
                  GestureDetector(
                    onTap: () => _pickImages(ImageSource.gallery),
                    child: Container(
                      height: 100, width: double.infinity, decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo_outlined, color: Colors.grey), Text('Agregar fotos', style: TextStyle(color: Colors.grey))]),
                    ),
                  ),
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
                            value: _selectedCategory,
                            decoration: const InputDecoration(labelText: 'Categoría *', border: OutlineInputBorder()),
                            items: cats.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                            onChanged: _onCategorySelected,
                            validator: (v) => v == null ? 'Requerido' : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: _crearCategoriaRapida, icon: const Icon(Icons.add), tooltip: 'Crear nueva categoría',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _tag, readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Asset Tag (Automático)', border: const OutlineInputBorder(), filled: true, fillColor: Colors.grey[50],
                      suffixIcon: _cargandoTag ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : const Icon(Icons.lock, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(controller: _serial, decoration: const InputDecoration(labelText: 'N/S (Opcional)', border: OutlineInputBorder())),
                ]),

                _section('Detalles del Equipo', [
                  Row(children: [
                    Expanded(child: TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Marca', border: OutlineInputBorder()))),
                    const SizedBox(width: 12),
                    Expanded(child: TextFormField(controller: _model, decoration: const InputDecoration(labelText: 'Modelo', border: OutlineInputBorder()))),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextFormField(controller: _quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad', border: OutlineInputBorder()))),
                    const SizedBox(width: 12),
                    Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: 'Unidad', border: OutlineInputBorder()), child: Text(_unit))),
                  ]),
                ]),

                _section('Asignación y Ubicación', [
                  TextFormField(controller: _assignedTo, decoration: const InputDecoration(labelText: 'Asignado a (Responsable)', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'Ubicación Física', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _status, decoration: const InputDecoration(labelText: 'Estado', border: OutlineInputBorder()),
                    items: ['Operativo', 'En Revisión', 'Retirado'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => _status = v!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas', border: OutlineInputBorder()), maxLines: 2),
                ]),

                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: (_saving || _cargandoTag) ? null : _submit,
                    style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                    child: _saving 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Guardar Activo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
