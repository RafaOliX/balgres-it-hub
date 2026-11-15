class Nota {
  final int id;
  final String title;
  final String body; // vacío en el listado; viene completo en el detalle
  final String snippet;
  final List<String> tags;
  final String? assetTag, updatedBy;
  final DateTime updatedAt;
  const Nota({
    required this.id, required this.title, this.body = '', this.snippet = '', this.tags = const [],
    this.assetTag, this.updatedBy, required this.updatedAt,
  });
  factory Nota.fromJson(Map<String, dynamic> j) => Nota(
        id: j['id'] as int,
        title: j['title'] as String,
        body: (j['body'] as String?) ?? '',
        snippet: (j['snippet'] as String?) ?? '',
        tags: ((j['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
        assetTag: j['asset_tag'] as String?,
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
