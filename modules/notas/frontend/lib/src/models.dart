List<String> _assetTags(Map<String, dynamic> j) {
  final l = (j['asset_tags'] as List?)?.map((e) => e.toString()).toList();
  if (l != null) return l;
  final t = j['asset_tag'] as String?; // respuesta antigua
  return t == null ? const [] : [t];
}

class Nota {
  final int id;
  final String title;
  final String body; // vacío en el listado; viene completo en el detalle
  final String snippet;
  final List<String> tags;
  final List<String> assetTags;
  final int diagramCount;
  final String? updatedBy;
  final DateTime updatedAt;
  const Nota({
    required this.id, required this.title, this.body = '', this.snippet = '', this.tags = const [],
    this.assetTags = const [], this.diagramCount = 0, this.updatedBy, required this.updatedAt,
  });
  factory Nota.fromJson(Map<String, dynamic> j) => Nota(
        id: j['id'] as int,
        title: j['title'] as String,
        body: (j['body'] as String?) ?? '',
        snippet: (j['snippet'] as String?) ?? '',
        tags: ((j['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
        assetTags: _assetTags(j),
        diagramCount: (j['diagram_count'] as num?)?.toInt() ?? 0,
        updatedBy: j['updated_by'] as String?,
        updatedAt: DateTime.parse(j['updated_at'] as String).toLocal(),
      );
}

class NotaDiagrama {
  final int id;
  final String title, xml;
  final String? updatedBy;
  final DateTime updatedAt;
  const NotaDiagrama({required this.id, required this.title, this.xml = '', this.updatedBy, required this.updatedAt});
  factory NotaDiagrama.fromJson(Map<String, dynamic> j) => NotaDiagrama(
        id: j['id'] as int,
        title: (j['title'] as String?) ?? 'Diagrama',
        xml: (j['xml'] as String?) ?? '',
        updatedBy: j['updated_by'] as String?,
        updatedAt: DateTime.parse(j['updated_at'] as String).toLocal(),
      );
}

class TagCount {
  final String tag;
  final int count;
  const TagCount(this.tag, this.count);
  factory TagCount.fromJson(Map<String, dynamic> j) => TagCount(j['tag'] as String, (j['count'] as num).toInt());
}
