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
  final _category = TextEditingController(text: 'Monitor');
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _location = TextEditingController();
  final _assignedTo = TextEditingController();
  final _notes = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  
  String _unit = 'Unidad';
  String _status = 'Operativo';
  final List<XFile> _files = [];
  bool _saving = false;
  bool _cargandoTag = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generarTag(_category.text));
  }

  // Al cambiar o escribir la categoría, generamos el Tag
  Future<void> _generarTag(String category) async {
    if (category.trim().isEmpty) return;
    setState(() { _cargandoTag = true; });
    try {
      final api = ref.read(inventarioApiProvider);
      final nextTag = await api.getSiguienteTag(category);
      setState(() { _tag.text = nextTag; });
    } catch (e) {
      // Si falla, ponemos un tag genérico
      setState(() { _tag.text = 'ACT-001'; });
    } finally {
      setState(() { _cargandoTag = false; });
    }
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
        assetTag: _tag.text.trim(), category: _category.text.trim(), brand: _brand.text.trim(),
        model: _model.text.trim(), serialNumber: _serial.text.trim(), location: _location.text.trim(),
        status: _status, notes: _notes.text.trim(), quantity: int.tryParse(_quantity.text) ?? 1, unit: _unit,
        assignedTo: _assignedTo.text.trim(),
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

  // Lista de sugerencias para el autocompletado
  static const List<String> _categoriasSugeridas = [
    'Monitor', 'Computadora', 'Impresora', 'Laptop', 'Switch', 'Router',
    'Cable UTP', 'Cable VGA', 'Cable de Poder', 'Cable HDMI', 'Disco Duro', 'Memoria RAM'
  ];

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
            
            // AUTOCOMPLETE PARA CATEGORÍA
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _category.text),
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text == '') return const Iterable<String>.empty();
                return _categoriasSugeridas.where((String option) {
                  return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                });
              },
              onSelected: (String selection) {
                _category.text = selection;
                _generarTag(selection);
              },
              fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                // Sincronizamos el controlador interno con el nuestro
                textEditingController.addListener(() {
                  if (_category.text != textEditingController.text) {
                    _category.text = textEditingController.text;
                  }
                });
                return TextFormField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Categoría *', 
                    hintText: 'Ej: Monitor, Cable UTP, etc.',
                    suffixIcon: Icon(Icons.arrow_drop_down)
                  ),
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                  onFieldSubmitted: (v) {
                    _category.text = v;
                    _generarTag(v);
                  },
                );
              },
            ),
            const SizedBox(height: 10),
            
            // TAG GENERADO (EDITABLE)
            TextFormField(
              controller: _tag,
              decoration: InputDecoration(
                labelText: 'Asset Tag (Sugerido)',
                helperText: 'Puedes cambiarlo si lo deseas',
                suffixIcon: _cargandoTag 
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) 
                  : IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: () => _generarTag(_category.text),
                      tooltip: 'Regenerar Tag',
                    ),
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
              decoration: const InputDecoration(labelText: 'S/N (Opcional)'),
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
