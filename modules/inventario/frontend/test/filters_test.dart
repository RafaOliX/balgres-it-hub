import 'package:balgres_it_inventario/src/data/filters.dart';
import 'package:balgres_it_inventario/src/models/it_asset.dart';
import 'package:balgres_it_inventario/src/ui/swiss.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ItAsset mk(
  String tag, {
  String category = 'Monitor',
  int? categoryId = 1,
  String brand = 'Dell',
  String model = 'P2419H',
  String? sn,
  String? location,
  String? assignedTo,
  String? status = 'Operativo',
  bool draft = false,
  Map<String, String> specs = const {},
  DateTime? created,
}) =>
    ItAsset(
      id: tag.hashCode, assetTag: tag, category: category, categoryId: categoryId,
      brand: brand, model: model, serialNumber: sn, location: location, assignedTo: assignedTo,
      status: status, isDraft: draft, specs: specs,
      createdAt: created ?? DateTime(2026, 1, 1),
    );

List<String> tags(List<ItAsset> l) => l.map((a) => a.assetTag).toList();

void main() {
  group('texto', () {
    test('normalizeText quita tildes y mayúsculas', () {
      expect(normalizeText('ÁRBOL Ñandú'), 'arbol nandu');
    });

    test('naturalCompare ordena PC-2 antes que PC-10', () {
      final l = ['PC-10', 'PC-2', 'PC-1']..sort(naturalCompare);
      expect(l, ['PC-1', 'PC-2', 'PC-10']);
    });
  });

  group('búsqueda', () {
    final items = [
      mk('MON-1', brand: 'Dell', location: 'Sistemas'),
      mk('MON-2', brand: 'LG', location: 'Sistemas'),
      mk('PC-1', category: 'Computadora', brand: 'Dell', location: 'Bodega', specs: {'IP': '10.0.0.5'}),
    ];

    test('exige todas las palabras, sin importar tildes ni mayúsculas', () {
      expect(tags(applyFilter(items, const InventoryFilter(query: 'DELL sistemas'))), ['MON-1']);
    });

    test('encuentra por datos técnicos (IP)', () {
      expect(tags(applyFilter(items, const InventoryFilter(query: '10.0.0.5'))), ['PC-1']);
    });

    test('los borradores solo aparecen al buscar o con el filtro de borradores', () {
      final l = [mk('PC-9', draft: true), mk('PC-1')];
      expect(tags(applyFilter(l, const InventoryFilter())), ['PC-1']);
      expect(tags(applyFilter(l, const InventoryFilter(query: 'pc-9'))), ['PC-9']);
      expect(tags(applyFilter(l, const InventoryFilter(showDrafts: true))), ['PC-9']);
    });
  });

  group('filtros', () {
    test('responsable asignado / sin asignar', () {
      final l = [mk('A-1', assignedTo: 'Ana'), mk('A-2')];
      expect(tags(applyFilter(l, const InventoryFilter(assign: AssignFilter.assigned))), ['A-1']);
      expect(tags(applyFilter(l, const InventoryFilter(assign: AssignFilter.unassigned))), ['A-2']);
    });

    test('ubicación "Sin ubicación" filtra los que no tienen', () {
      final l = [mk('A-1', location: 'Sistemas'), mk('A-2')];
      expect(tags(applyFilter(l, const InventoryFilter(locations: {kNoLocation}))), ['A-2']);
    });

    test('ignoreStatus no aplica estado (sirve para los contadores)', () {
      final l = [mk('A-1', status: 'Retirado'), mk('A-2')];
      final f = const InventoryFilter(statuses: {'Operativo'});
      expect(tags(applyFilter(l, f)), ['A-2']);
      expect(tags(applyFilter(l, f, ignoreStatus: true)).toSet(), {'A-1', 'A-2'});
    });

    test('orden por tag es natural', () {
      final l = [mk('PC-10'), mk('PC-2')];
      expect(tags(applyFilter(l, const InventoryFilter(sort: 'tag'))), ['PC-2', 'PC-10']);
    });
  });

  group('agrupar y serializar', () {
    test('"Sin ubicación" queda al final', () {
      final g = groupAssets([mk('A-1'), mk('A-2', location: 'Zeta'), mk('A-3', location: 'Alfa')], 'location');
      expect(g.keys.toList(), ['Alfa', 'Zeta', kNoLocation]);
    });

    test('copyWith(clearGroupBy) quita el agrupado', () {
      final f = const InventoryFilter(groupBy: 'status').copyWith(clearGroupBy: true);
      expect(f.groupBy, isNull);
    });

    test('toJson/fromJson conserva el filtro', () {
      const f = InventoryFilter(
        query: 'dell', statuses: {'Operativo'}, categoryIds: {1, 2}, locations: {'Sistemas'},
        assign: AssignFilter.unassigned, sort: 'tag', groupBy: 'category',
      );
      final r = InventoryFilter.fromJson(f.toJson());
      expect(r.toJson(), f.toJson());
    });
  });

  group('tema', () {
    test('el acento se aplica al esquema y a la extensión', () {
      const accent = Color(0xFF0F766E);
      final light = buildSwissTheme(Brightness.light, accent);
      expect(light.colorScheme.primary, accent);
      expect(light.extension<SwissColors>()!.accent, accent);
      final dark = buildSwissTheme(Brightness.dark, accent);
      expect(dark.colorScheme.primary, isNot(accent)); // se aclara en oscuro
    });
  });
}
