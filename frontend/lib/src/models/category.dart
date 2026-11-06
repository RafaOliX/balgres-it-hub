class Category {
  final int id;
  final String name;
  final int? parentId;
  final String prefix;
  final String unit;
  final bool requiresSn;

  const Category({
    required this.id, required this.name, this.parentId,
    required this.prefix, required this.unit, required this.requiresSn,
  });

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: j['id'] as int,
    name: j['name'] as String,
    parentId: j['parent_id'] as int?,
    prefix: j['prefix'] as String,
    unit: j['unit'] as String,
    requiresSn: j['requires_sn'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'name': name, 'parent_id': parentId, 'prefix': prefix, 'unit': unit, 'requires_sn': requiresSn,
  };
}
