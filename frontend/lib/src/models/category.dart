class Category {
  final int id;
  final String name;
  final int? parentId;
  final String prefix;
  final String unit;
  final bool requiresSn;
  final List<String> specFields;

  const Category({
    required this.id, required this.name, this.parentId,
    required this.prefix, required this.unit, required this.requiresSn,
    this.specFields = const [],
  });

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: j['id'] as int,
    name: j['name'] as String,
    parentId: j['parent_id'] as int?,
    prefix: j['prefix'] as String,
    unit: j['unit'] as String,
    requiresSn: j['requires_sn'] as bool,
    specFields: ((j['spec_fields'] as List<dynamic>?) ?? []).map((e) => e.toString()).toList(),
  );

  Map<String, dynamic> toJson() => {
    'name': name, 'parent_id': parentId, 'prefix': prefix, 'unit': unit,
    'requires_sn': requiresSn, 'spec_fields': specFields,
  };
}
