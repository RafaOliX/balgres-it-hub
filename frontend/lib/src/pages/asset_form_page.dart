import 'dart:typed_data';

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
  final _notes = TextEditingController();
  String _status = 'Operativo';

  Uint8List? _imageBytes;
  String? _imageName;
  String? _imageMime;

  bool _saving = false;
  String? _error;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageName = picked.name.isEmpty ? 'foto.jpg' : picked.name;
      _imageMime = picked.mimeType ??
          (picked.path.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg');
    });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(inventarioApiProvider);
      final asset = await api.crear(ItAssetCreate(
        assetTag: _tag.text.trim(),
        category: _category.text.trim(),
        brand: _brand.text.trim(),
        model: _model.text.trim(),
        serialNumber: _serial.text.trim(),
        location: _location.text.trim(),
        status: _status,
        notes: _notes.text.trim(),
      ));

      if (_imageBytes != null && _imageName != null && _imageMime != null) {
        try {
          await api.subirImagen(asset.assetTag, _imageBytes!, _imageName!, _imageMime!);
        } catch (e) {
          // El activo ya fue creado; sólo falló la imagen
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Activo creado, pero falló la imagen: $e')),
            );
          }
        }
      }

      ref.invalidate(inventarioListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Activo ${asset.assetTag} creado')),
        );
        context.pop();
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _imagePicker() {
    final hasImage = _imageBytes != null;
    return GestureDetector(
      onTap: () => _showImageSourceSheet(),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
            style: BorderStyle.solid,
          ),
        ),
        child: hasImage
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_imageBytes!, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 18),
                        onPressed: () => setState(() {
                          _imageBytes = null;
                          _imageName = null;
                          _imageMime = null;
                        }),
                      ),
                    ),
                  ),
                ],
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, size: 36, color: Color(0xFF6B7280)),
                  SizedBox(height: 6),
                  Text('Agregar foto',
                      style: TextStyle(
                          fontSize: 13, color: Color(0xFF6B7280))),
                  SizedBox(height: 2),
                  Text('Cámara o galería',
                      style: TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF))),
                ],
              ),
      ),
    );
  }

  void _showImageSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Tomar foto'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de galería'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_imageBytes != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Quitar foto',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _imageBytes = null;
                    _imageName = null;
                    _imageMime = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Nuevo activo'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red)),
              ),
            _imagePicker(),
            const SizedBox(height: 20),
            _SectionLabel('Identificación'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _tag,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Asset Tag *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _serial,
              decoration: const InputDecoration(labelText: 'Número de serie *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 20),
            _SectionLabel('Equipo'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'Categoría *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: TextFormField(
                        controller: _brand,
                        decoration: const InputDecoration(labelText: 'Marca'))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextFormField(
                        controller: _model,
                        decoration: const InputDecoration(labelText: 'Modelo'))),
              ],
            ),
            const SizedBox(height: 20),
            _SectionLabel('Ubicación y estado'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Ubicación'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: const [
                DropdownMenuItem(value: 'Operativo', child: Text('Operativo')),
                DropdownMenuItem(value: 'En Revisión', child: Text('En Revisión')),
                DropdownMenuItem(value: 'Retirado', child: Text('Retirado')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'Operativo'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notas'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Guardando…' : 'Guardar activo'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF6B7280),
        letterSpacing: 0.6,
      ),
    );
  }
}
