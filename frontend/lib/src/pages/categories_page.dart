import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/providers.dart';
import '../models/category.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

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
              onPressed: () {}, // Aquí podrías poner un modal para crear categoría desde aquí
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nueva'),
            ),
          )
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
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
                      children: children.map((child) => ListTile(
                        leading: const Icon(Icons.subdirectory_arrow_right, color: Colors.grey),
                        title: Text(child.name),
                        subtitle: Text('Prefijo: ${child.prefix} | Unidad: ${child.unit} | S/N: ${child.requiresSn ? "Sí" : "No"}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            try {
                              await ref.read(inventarioApiProvider).eliminarCategoria(child.id);
                              ref.invalidate(categoriasListProvider);
                            } catch (e) {
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                            }
                          },
                        ),
                      )).toList(),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          try {
                            await ref.read(inventarioApiProvider).eliminarCategoria(root.id);
                            ref.invalidate(categoriasListProvider);
                          } catch (e) {
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                          }
                        },
                      ),
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
