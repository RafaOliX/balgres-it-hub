import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/it_asset.dart';

const kNoLocation = 'Sin ubicación';

// ------------------------------------------------------------------ texto
const _from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
const _to = 'aaaaaeeeeiiiiooooouuuunc';
final _accentMap = <String, String>{
  for (var i = 0; i < _from.length; i++) _from[i]: _to[i],
};

/// Minúsculas y sin tildes, para búsquedas tolerantes.
String normalizeText(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(_accentMap[ch] ?? ch);
  }
  return b.toString();
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

// ------------------------------------------------------------------ filtro
enum AssignFilter { all, assigned, unassigned }

enum WarrantyFilter { all, expired, soon, none }

const assignLabels = {
  AssignFilter.all: 'Todos',
  AssignFilter.assigned: 'Asignados',
  AssignFilter.unassigned: 'Sin asignar',
};

const warrantyLabels = {
  WarrantyFilter.all: 'Todas',
  WarrantyFilter.expired: 'Vencida',
  WarrantyFilter.soon: 'Vence en 60 días',
  WarrantyFilter.none: 'Sin garantía registrada',
};

const sortLabels = {
  'recent': 'Más recientes',
  'tag': 'Tag',
  'brand': 'Marca / modelo',
  'status': 'Estado',
  'warranty': 'Garantía (vence antes)',
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
  final WarrantyFilter warranty;
  final bool showDrafts;
  final String sort;
  final String? groupBy;

  const InventoryFilter({
    this.query = '',
    this.statuses = const {},
    this.categoryIds = const {},
    this.locations = const {},
    this.assign = AssignFilter.all,
    this.warranty = WarrantyFilter.all,
    this.showDrafts = false,
    this.sort = 'recent',
    this.groupBy,
  });

  InventoryFilter copyWith({
    String? query,
    Set<String>? statuses,
    Set<int>? categoryIds,
    Set<String>? locations,
    AssignFilter? assign,
    WarrantyFilter? warranty,
    bool? showDrafts,
    String? sort,
    String? groupBy,
    bool clearGroupBy = false,
  }) =>
      InventoryFilter(
        query: query ?? this.query,
        statuses: statuses ?? this.statuses,
        categoryIds: categoryIds ?? this.categoryIds,
        locations: locations ?? this.locations,
        assign: assign ?? this.assign,
        warranty: warranty ?? this.warranty,
        showDrafts: showDrafts ?? this.showDrafts,
        sort: sort ?? this.sort,
        groupBy: clearGroupBy ? null : (groupBy ?? this.groupBy),
      );

  /// Cantidad de dimensiones de filtro activas (sin contar búsqueda, orden ni agrupado).
  int get panelCount =>
      (statuses.isNotEmpty ? 1 : 0) +
      (showDrafts ? 1 : 0) +
      (categoryIds.isNotEmpty ? 1 : 0) +
      (locations.isNotEmpty ? 1 : 0) +
      (assign != AssignFilter.all ? 1 : 0) +
      (warranty != WarrantyFilter.all ? 1 : 0);

  bool get isDefault => query.trim().isEmpty && panelCount == 0 && sort == 'recent' && groupBy == null;

  String get summary {
    final p = <String>[
      if (query.trim().isNotEmpty) '"${query.trim()}"',
      if (showDrafts) 'Borradores',
      ...statuses,
      if (categoryIds.isNotEmpty) '${categoryIds.length} categoría(s)',
      if (locations.isNotEmpty) '${locations.length} ubicación(es)',
      if (assign != AssignFilter.all) assignLabels[assign]!,
      if (warranty != WarrantyFilter.all) 'Garantía: ${warrantyLabels[warranty]}',
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
        'warranty': warranty.name,
        'showDrafts': showDrafts,
        'sort': sort,
        'groupBy': groupBy,
      };

  factory InventoryFilter.fromJson(Map<String, dynamic> j) => InventoryFilter(
        query: (j['query'] as String?) ?? '',
        statuses: Set<String>.from((j['statuses'] as List?) ?? const []),
        categoryIds: Set<int>.from((j['categoryIds'] as List?) ?? const []),
        locations: Set<String>.from((j['locations'] as List?) ?? const []),
        assign: _enumByName(AssignFilter.values, j['assign'], AssignFilter.all),
        warranty: _enumByName(WarrantyFilter.values, j['warranty'], WarrantyFilter.all),
        showDrafts: (j['showDrafts'] as bool?) ?? false,
        sort: (j['sort'] as String?) ?? 'recent',
        groupBy: j['groupBy'] as String?,
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

/// Filtra y ordena. Con [ignoreStatus] omite estado/borradores (sirve para los contadores de los chips).
List<ItAsset> applyFilter(List<ItAsset> items, InventoryFilter f, {bool ignoreStatus = false}) {
  final terms = normalizeText(f.query.trim()).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

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

    final w = a.warrantyUntil;
    switch (f.warranty) {
      case WarrantyFilter.all:
        break;
      case WarrantyFilter.expired:
        if (w == null || !w.isBefore(today)) return false;
      case WarrantyFilter.soon:
        if (w == null) return false;
        final d = w.difference(today).inDays;
        if (d < 0 || d > 60) return false;
      case WarrantyFilter.none:
        if (w != null) return false;
    }

    if (terms.isNotEmpty) {
      final hay = normalizeText([
        a.assetTag, a.category, a.brand, a.model, a.serialNumber, a.location,
        a.assignedTo, a.notes, a.supplier, a.invoiceNumber, ...a.specs.values,
      ].whereType<String>().join(' '));
      if (!terms.every(hay.contains)) return false;
    }
    return true;
  }).toList();

  switch (f.sort) {
    case 'tag':
      out.sort((a, b) => naturalCompare(a.assetTag, b.assetTag));
    case 'brand':
      out.sort((a, b) => normalizeText('${a.brand} ${a.model}').compareTo(normalizeText('${b.brand} ${b.model}')));
    case 'status':
      out.sort((a, b) => (a.status ?? '').compareTo(b.status ?? ''));
    case 'warranty':
      out.sort((a, b) {
        final x = a.warrantyUntil, y = b.warrantyUntil;
        if (x == null && y == null) return 0;
        if (x == null) return 1;
        if (y == null) return -1;
        return x.compareTo(y);
      });
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
