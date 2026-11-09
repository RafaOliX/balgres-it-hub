import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InventoryFilter {
  final Set<String> statuses;
  final Set<int> categoryIds;
  final bool showDrafts;
  final String? groupBy; // 'category', 'status', 'location', null
  final String searchQuery;

  const InventoryFilter({
    this.statuses = const {},
    this.categoryIds = const {},
    this.showDrafts = false,
    this.groupBy,
    this.searchQuery = '',
  });

  InventoryFilter copyWith({
    Set<String>? statuses,
    Set<int>? categoryIds,
    bool? showDrafts,
    String? groupBy,
    String? searchQuery,
  }) {
    return InventoryFilter(
      statuses: statuses ?? this.statuses,
      categoryIds: categoryIds ?? this.categoryIds,
      showDrafts: showDrafts ?? this.showDrafts,
      groupBy: groupBy ?? this.groupBy,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  bool get isActive =>
      statuses.isNotEmpty ||
      categoryIds.isNotEmpty ||
      showDrafts ||
      groupBy != null ||
      searchQuery.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'statuses': statuses.toList(),
        'categoryIds': categoryIds.toList(),
        'showDrafts': showDrafts,
        'groupBy': groupBy,
        'searchQuery': searchQuery,
      };

  factory InventoryFilter.fromJson(Map<String, dynamic> json) {
    return InventoryFilter(
      statuses: Set<String>.from(json['statuses'] ?? []),
      categoryIds: Set<int>.from(json['categoryIds'] ?? []),
      showDrafts: json['showDrafts'] ?? false,
      groupBy: json['groupBy'],
      searchQuery: json['searchQuery'] ?? '',
    );
  }
}

class SavedFilter {
  final String name;
  final InventoryFilter filter;
  SavedFilter({required this.name, required this.filter});

  Map<String, dynamic> toJson() => {'name': name, 'filter': filter.toJson()};
  factory SavedFilter.fromJson(Map<String, dynamic> json) => SavedFilter(
        name: json['name'],
        filter: InventoryFilter.fromJson(json['filter']),
      );
}

// Proveedor del estado actual de los filtros
final inventoryFilterProvider = StateProvider<InventoryFilter>((ref) => const InventoryFilter());

// Proveedor para manejar los favoritos guardados (SharedPreferences)
class SavedFiltersNotifier extends StateNotifier<List<SavedFilter>> {
  SavedFiltersNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('saved_filters');
    if (data != null) {
      final List decoded = jsonDecode(data);
      state = decoded.map((e) => SavedFilter.fromJson(e)).toList();
    }
  }

  Future<void> add(String name, InventoryFilter filter) async {
    final newList = [...state, SavedFilter(name: name, filter: filter)];
    state = newList;
    await _save();
  }

  Future<void> remove(String name) async {
    state = state.where((f) => f.name != name).toList();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(state.map((e) => e.toJson()).toList());
    await prefs.setString('saved_filters', data);
  }
}

final savedFiltersProvider = StateNotifierProvider<SavedFiltersNotifier, List<SavedFilter>>((ref) => SavedFiltersNotifier());
