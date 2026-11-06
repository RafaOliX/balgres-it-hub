import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/providers.dart';
import '../models/category.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  Future<void> _showCategoryModal(BuildContext context, WidgetRef ref, {Category? category}) async {
    final nameCtrl = TextEditingController(text: category?.name ?? '');
    final prefixCtrl = TextEditingController(text: category?.prefix ?? '');
    String unit = category?.unit ?? 'Unidad';
    bool reqSn = category?.requiresSn ?? true;
    int? parentId = category?.parentId;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final catsAsync = ref.watch(categoriasListProvider);
          return AlertDialog(
            title: Text(category == null ? 'Nueva Categoría' : 'Editar Categoría'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre (Ej: Cable HDMI)')),
                  TextField(controller: prefixCtrl, decoration: const InputDecoration(labelText: 'Prefijo (Ej: HDMI)')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: unit, decoration: const InputDecoration(labelText: 'Unidad por defecto'),
                    items: ['Unidad', 'Metro', 'Caja', 'Rollo'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setModalState(() => unit = v!),
                  ),
                  const SizedBox(height: 10),
                  catsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Error: $e'),
                    data: (cats) => DropdownButtonFormField<int?>(
                      value: parentId,
                      decoration: const InputDecoration(labelText: 'Categoría Padre (Opcional)'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Ninguna (Es Principal)')),
                        ...cats.where((c) => c.id != category?.id).map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                      ],
                      onChanged: (v) => setModalState(() => parentId = v),
                    ),
                  ),
                  CheckboxListTile(
                    title: const Text('¿Requiere S/N?'), value: reqSn,
                    onChanged: (v) => setModalState(() => reqSn = v!),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty || prefixCtrl.text.isEmpty) return;
                  final newCat = Category(
                    id: category?.id ?? 0, name: nameCtrl.text, prefix: prefixCtrl.text, 
                    unit: unit, requiresSn: reqSn, parentId: parentId
                  );
                  try {
                    if (category == null) {
                      await ref.read(inventarioApiProvider).crearCategoria(newCat);
                    } else {
                      await ref.read(inventarioApiProvider).actualizarCategoria(category.id, newCat);
                    }
                    ref.invalidate(categoriasListProvider);
                    if (context.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
                child: Text(category == null ? 'Crear' : 'Guardar'),
              )
            ],
          );
        }
      )
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCats = ref.watch(categoriasListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Categorías y Subcategorías'),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/inventario')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: () => _showCategoryModal(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nueva'),
            ),
          )
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: asyncCats.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (cats) {
              final roots = cats.where((c) => c.parentId == null).toList();
              
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: roots.length,
                itemBuilder: (_, i) {
                  final root = roots[i];
                  final children = cats.where((c) => c.parentId == root.id).toList();
                  
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE5E7EB))),
                    child: ExpansionTile(
                      leading: const Icon(Icons.folder_outlined, color: Colors.blue),
                      title: Text(root.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Prefijo: ${root.prefix} | Unidad: ${root.unit} | S/N: ${root.requiresSn ? "Sí" : "No"}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            tooltip: 'Editar',
                            onPressed: () => _showCategoryModal(context, ref, category: root),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            tooltip: 'Eliminar',
                            onPressed: () async {
                              try {
                                await ref.read(inventarioApiProvider).eliminarCategoria(root.id);
                                ref.invalidate(categoriasListProvider);
                              } catch (e) {
                                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                              }
                            },
                          ),
                        ],
                      ),
                      children: children.map((child) => ListTile(
                        leading: const Icon(Icons.subdirectory_arrow_right, color: Colors.grey),
                        title: Text(child.name),
                        subtitle: Text('Prefijo: ${child.prefix} | Unidad: ${child.unit} | S/N: ${child.requiresSn ? "Sí" : "No"}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                              onPressed: () => _showCategoryModal(context, ref, category: child),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                              onPressed: () async {
                                try {
                                  await ref.read(inventarioApiProvider).eliminarCategoria(child.id);
                                  ref.invalidate(categoriasListProvider);
                                } catch (e) {
                                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                }
                              },
                            ),
                          ],
                        ),
                      )).toList(),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
