import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../data/providers.dart';
import '../models/it_asset.dart';

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
  
  String _category = 'Monitor';
  String _unit = 'Unidad';
  String _status = 'Operativo';
  final List<XFile> _files = [];
  bool _saving = false;
  bool _cargandoTag = false;
  String? _error;

  // Al cambiar categoría, pedimos el nuevo tag
  Future<void> _onCategoryChanged(String? newCategory) async {
    if (newCategory == null) return;
    setState(() { _category = newCategory; _cargandoTag = true; });
    try {
      final api = ref.read(inventarioApiProvider);
      final nextTag = await api.getSiguienteTag(newCategory);
      setState(() { _tag.text = nextTag; });
    } catch (e) {
      setState(() { _tag.text = ''; });
    } finally {
      setState(() { _cargandoTag = false; });
    }
  }

  @override
  void initState() {
    super.initState();
    // Cargar el primer tag al abrir la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) => _onCategoryChanged(_category));
  }

  Future<void> _pickImages(ImageSource source) async {
    final picker = ImagePicker();
    final picked = source == ImageSource.gallery
        ? await picker.pickMultiImage(maxWidth: 1600, imageQuality: 85)
        : [if (await picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85) != null) (await picker.pickImage(source: ImageSource.camera))!].whereType<XFile>().toList();
    if (picked.isEmpty) return;
    setState(() => _files.addAll(picked));
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      final api = ref.read(inventarioApiProvider);
      final asset = await api.crear(ItAssetCreate(
        assetTag: _tag.text.trim(), category: _category, brand: _brand.text.trim(),
        model: _model.text.trim(), serialNumber: _serial.text.trim(), location: _location.text.trim(),
        status: _status, notes: _notes.text.trim(), quantity: int.tryParse(_quantity.text) ?? 1, unit: _unit,
        assignedTo: _assignedTo.text.trim(), // Pásalo si lo añadiste al modelo
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
                child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_a_photo_outlined, color: Colors.grey), Text('Fotos'),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            
            // CATEGORÍA (Primero, para que genere el tag)
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Categoría *'),
              items: ['Monitor', 'Computadora', 'Impresora', 'Cable UTP', 'Cable VGA', 'Cable de Poder', 'Switch', 'Router', 'Otro']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: _onCategoryChanged,
            ),
            const SizedBox(height: 10),
            
            // TAG AUTOGENERADO
            TextFormField(
              controller: _tag,
              readOnly: true, // Bloqueado porque es automático
              decoration: InputDecoration(
                labelText: 'Asset Tag (Automático)',
                suffixIcon: _cargandoTag ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lock, size: 18),
              ),
            ),
            const SizedBox(height: 10),

            // DATOS BÁSICOS
            Row(children: [
              Expanded(child: TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Marca'))),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: _model, decoration: const InputDecoration(labelText: 'Modelo'))),
            ]),
            TextFormField(
              controller: _serial, 
              decoration: const InputDecoration(labelText: 'S/N (Opcional para cables)'),
            ),
            
            // CANTIDAD Y UNIDAD
            Row(children: [
              Expanded(child: TextFormField(controller: _quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad'))),
              const SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<String>(
                value: _unit, decoration: const InputDecoration(labelText: 'Unidad'),
                items: ['Unidad', 'Metro', 'Caja', 'Rollo'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setState(() => _unit = v!),
              )),
            ]),
            
            // ASIGNACIÓN
            TextFormField(
              controller: _assignedTo, 
              decoration: const InputDecoration(labelText: 'Asignado a (Responsable)'),
            ),
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
