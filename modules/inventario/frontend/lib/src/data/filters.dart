import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:balgres_it_ui/text.dart';

export 'package:balgres_it_ui/text.dart' show normalizeText;

import '../models/it_asset.dart';

const kNoLocation = 'Sin ubicación';

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

// ------------------------------------------------------------------ filtro
enum AssignFilter { all, assigned, unassigned }

const assignLabels = {
  AssignFilter.all: 'Todos',
  AssignFilter.assigned: 'Asignados',
  AssignFilter.unassigned: 'Sin asignar',
};

const sortLabels = {
  'recent': 'Más recientes',
  'tag': 'Tag',
  'brand': 'Marca / modelo',
  'status': 'Estado',
};

const groupLabels = {
  'category': 'Categoría',
  'status': 'Estado',
  'location': 'Ubicación',
  'assigned': 'Responsable',
};

class InventoryFilter {
  final String query;
  final Set<String> statuses;
  final Set<int> categoryIds;
  final Set<String> locations;
  final AssignFilter assign;
  final bool showDrafts;
  final String sort;
  final String? groupBy;
  final String? sortCol; // id de columna de la tabla (ver table_prefs.dart); manda sobre [sort]
  final bool sortAsc;

  const InventoryFilter({
    this.query = '',
    this.statuses = const {},
    this.categoryIds = const {},
    this.locations = const {},
    this.assign = AssignFilter.all,
    this.showDrafts = false,
    this.sort = 'recent',
    this.groupBy,
    this.sortCol,
    this.sortAsc = true,
  });

  InventoryFilter copyWith({
    String? query,
    Set<String>? statuses,
    Set<int>? categoryIds,
    Set<String>? locations,
    AssignFilter? assign,
    bool? showDrafts,
    String? sort,
    String? groupBy,
    bool clearGroupBy = false,
    String? sortCol,
    bool? sortAsc,
    bool clearSortCol = false,
  }) =>
      InventoryFilter(
        query: query ?? this.query,
        statuses: statuses ?? this.statuses,
        categoryIds: categoryIds ?? this.categoryIds,
        locations: locations ?? this.locations,
        assign: assign ?? this.assign,
        showDrafts: showDrafts ?? this.showDrafts,
        sort: sort ?? this.sort,
        groupBy: clearGroupBy ? null : (groupBy ?? this.groupBy),
        sortCol: clearSortCol ? null : (sortCol ?? this.sortCol),
        sortAsc: sortAsc ?? this.sortAsc,
      );

  /// Cantidad de dimensiones de filtro activas (sin contar búsqueda, orden ni agrupado).
  int get panelCount =>
      (statuses.isNotEmpty ? 1 : 0) +
      (showDrafts ? 1 : 0) +
      (categoryIds.isNotEmpty ? 1 : 0) +
      (locations.isNotEmpty ? 1 : 0) +
      (assign != AssignFilter.all ? 1 : 0);

  bool get isDefault => query.trim().isEmpty && panelCount == 0 && sort == 'recent' && groupBy == null && sortCol == null;

  String get summary {
    final p = <String>[
      if (query.trim().isNotEmpty) '"${query.trim()}"',
      if (showDrafts) 'Borradores',
      ...statuses,
      if (categoryIds.isNotEmpty) '${categoryIds.length} categoría(s)',
      if (locations.isNotEmpty) '${locations.length} ubicación(es)',
      if (assign != AssignFilter.all) assignLabels[assign]!,
      if (groupBy != null) 'Agrupado: ${groupLabels[groupBy] ?? groupBy}',
    ];
    return p.isEmpty ? 'Sin filtros' : p.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'query': query,
        'statuses': statuses.toList(),
        'categoryIds': categoryIds.toList(),
        'locations': locations.toList(),
        'assign': assign.name,
        'showDrafts': showDrafts,
        'sort': sort,
        'groupBy': groupBy,
        'sortCol': sortCol,
        'sortAsc': sortAsc,
      };

  factory InventoryFilter.fromJson(Map<String, dynamic> j) => InventoryFilter(
        query: (j['query'] as String?) ?? '',
        statuses: Set<String>.from((j['statuses'] as List?) ?? const []),
        categoryIds: Set<int>.from((j['categoryIds'] as List?) ?? const []),
        locations: Set<String>.from((j['locations'] as List?) ?? const []),
        assign: _enumByName(AssignFilter.values, j['assign'], AssignFilter.all),
        showDrafts: (j['showDrafts'] as bool?) ?? false,
        sort: (j['sort'] as String?) ?? 'recent',
        groupBy: j['groupBy'] as String?,
        sortCol: j['sortCol'] as String?,
        sortAsc: (j['sortAsc'] as bool?) ?? true,
      );
}

// ------------------------------------------------------------------ aplicar
int naturalCompare(String a, String b) {
  final re = RegExp(r'^(.*?)(\d+)$');
  final ma = re.firstMatch(a), mb = re.firstMatch(b);
  if (ma != null && mb != null) {
    final c = ma.group(1)!.compareTo(mb.group(1)!);
    if (c != 0) return c;
    return (int.tryParse(ma.group(2)!) ?? 0).compareTo(int.tryParse(mb.group(2)!) ?? 0);
  }
  return a.compareTo(b);
}

/// Texto de una columna de la tabla (mismos ids que table_prefs.dart); null si no aplica.
String? sortValue(ItAsset a, String col) {
  if (col.startsWith('spec:')) return a.specs[col.substring(5)];
  return switch (col) {
    'asset' => a.assetTag,
    'equipo' => '${a.brand} ${a.model}',
    'category' => a.category,
    'brand' => a.brand,
    'model' => a.model,
    'serial' => a.serialNumber,
    'location' => a.location,
    'assigned' => a.assignedTo,
    'status' => a.isDraft ? 'Borrador' : a.status,
    'notes' => a.notes,
    _ => null,
  };
}

List<int>? _ipParts(String s) {
  final p = s.trim().split('.');
  if (p.length != 4) return null;
  final n = [for (final x in p) int.tryParse(x)];
  return n.contains(null) ? null : [for (final x in n) x!];
}

bool _blankCol(ItAsset a, String col) {
  if (col == 'quantity' || col == 'created') return false;
  return (sortValue(a, col) ?? '').trim().isEmpty;
}

/// Compara por columna: cantidad y fecha como número, IPs por octetos, tags en orden natural.
int compareByColumn(ItAsset a, ItAsset b, String col) {
  if (col == 'quantity') return a.quantity.compareTo(b.quantity);
  if (col == 'created') return a.createdAt.compareTo(b.createdAt);
  final x = (sortValue(a, col) ?? '').trim(), y = (sortValue(b, col) ?? '').trim();
  final ia = _ipParts(x), ib = _ipParts(y);
  if (ia != null && ib != null) {
    for (var i = 0; i < 4; i++) {
      final c = ia[i].compareTo(ib[i]);
      if (c != 0) return c;
    }
    return 0;
  }
  if (col == 'asset') return naturalCompare(x, y);
  return normalizeText(x).compareTo(normalizeText(y));
}

/// Ciclo del encabezado: ascendente → descendente → sin orden por columna.
InventoryFilter nextColumnSort(InventoryFilter f, String id) {
  if (f.sortCol != id) return f.copyWith(sortCol: id, sortAsc: true);
  if (f.sortAsc) return f.copyWith(sortAsc: false);
  return f.copyWith(clearSortCol: true, sortAsc: true);
}

/// Filtra y ordena. Con [ignoreStatus] omite estado/borradores (sirve para los contadores de los chips).
List<ItAsset> applyFilter(List<ItAsset> items, InventoryFilter f, {bool ignoreStatus = false}) {
  final terms = normalizeText(f.query.trim()).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  final out = items.where((a) {
    if (!ignoreStatus) {
      if (f.showDrafts) {
        if (!a.isDraft) return false;
      } else {
        // al buscar, los borradores también aparecen (por si escaneas uno)
        if (a.isDraft && terms.isEmpty) return false;
        if (f.statuses.isNotEmpty && !f.statuses.contains(a.status)) return false;
      }
    }
    if (f.categoryIds.isNotEmpty && !f.categoryIds.contains(a.categoryId)) return false;
    if (f.locations.isNotEmpty && !f.locations.contains(a.location ?? kNoLocation)) return false;

    final asignado = a.assignedTo != null && a.assignedTo!.trim().isNotEmpty;
    if (f.assign == AssignFilter.assigned && !asignado) return false;
    if (f.assign == AssignFilter.unassigned && asignado) return false;

    if (terms.isNotEmpty) {
      final hay = normalizeText([
        a.assetTag, a.category, a.brand, a.model, a.serialNumber, a.location,
        a.assignedTo, a.notes, ...a.specs.values,
      ].whereType<String>().join(' '));
      if (!terms.every(hay.contains)) return false;
    }
    return true;
  }).toList();

  final sc = f.sortCol;
  if (sc != null) {
    out.sort((a, b) {
      final ea = _blankCol(a, sc), eb = _blankCol(b, sc);
      if (ea != eb) return ea ? 1 : -1; // vacíos siempre al final
      final c = compareByColumn(a, b, sc);
      return f.sortAsc ? c : -c;
    });
    return out;
  }
  switch (f.sort) {
    case 'tag':
      out.sort((a, b) => naturalCompare(a.assetTag, b.assetTag));
    case 'brand':
      out.sort((a, b) => normalizeText('${a.brand} ${a.model}').compareTo(normalizeText('${b.brand} ${b.model}')));
    case 'status':
      out.sort((a, b) => (a.status ?? '').compareTo(b.status ?? ''));
    default:
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  return out;
}

String groupKey(ItAsset a, String by) => switch (by) {
      'category' => a.category,
      'status' => a.isDraft ? 'Borrador' : (a.status ?? 'Sin estado'),
      'location' => a.location ?? kNoLocation,
      'assigned' => (a.assignedTo == null || a.assignedTo!.trim().isEmpty) ? 'Sin asignar' : a.assignedTo!,
      _ => '',
    };

/// Si [by] es null devuelve un solo grupo con clave ''.
Map<String, List<ItAsset>> groupAssets(List<ItAsset> items, String? by) {
  if (by == null) return {'': items};
  final m = <String, List<ItAsset>>{};
  for (final a in items) {
    m.putIfAbsent(groupKey(a, by), () => []).add(a);
  }
  final keys = m.keys.toList()
    ..sort((a, b) {
      final sa = a.startsWith('Sin '), sb = b.startsWith('Sin ');
      if (sa != sb) return sa ? 1 : -1;
      return normalizeText(a).compareTo(normalizeText(b));
    });
  return {for (final k in keys) k: m[k]!};
}

// ------------------------------------------------------------------ estado
final inventoryFilterProvider = StateProvider<InventoryFilter>((ref) => const InventoryFilter());

class SavedFilter {
  final String name;
  final InventoryFilter filter;
  SavedFilter({required this.name, required this.filter});

  Map<String, dynamic> toJson() => {'name': name, 'filter': filter.toJson()};
  factory SavedFilter.fromJson(Map<String, dynamic> j) =>
      SavedFilter(name: j['name'] as String, filter: InventoryFilter.fromJson(j['filter'] as Map<String, dynamic>));
}

class SavedFiltersNotifier extends StateNotifier<List<SavedFilter>> {
  SavedFiltersNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('saved_filters');
      if (data == null) return;
      final decoded = jsonDecode(data) as List;
      state = decoded.map((e) => SavedFilter.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      state = const [];
    }
  }

  Future<void> add(String name, InventoryFilter filter) async {
    state = [...state.where((f) => f.name != name), SavedFilter(name: name, filter: filter)];
    await _save();
  }

  Future<void> remove(String name) async {
    state = state.where((f) => f.name != name).toList();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_filters', jsonEncode(state.map((e) => e.toJson()).toList()));
  }
}

final savedFiltersProvider =
    StateNotifierProvider<SavedFiltersNotifier, List<SavedFilter>>((ref) => SavedFiltersNotifier());
