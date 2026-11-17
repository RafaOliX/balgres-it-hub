import 'dart:convert';
import 'dart:typed_data';

List<String> _assetTags(Map<String, dynamic> j) {
  final l = (j['asset_tags'] as List?)?.map((e) => e.toString()).toList();
  if (l != null) return l;
  final t = j['asset_tag'] as String?; // respuesta antigua
  return t == null ? const [] : [t];
}

DateTime _d(dynamic v) => v == null ? DateTime.now() : DateTime.parse(v as String).toLocal();

class Nota {
  final int id;
  final String title;
  final String body; // vacío en el listado; viene completo en el detalle
  final String snippet;
  final List<String> tags;
  final List<String> assetTags;
  final int diagramCount, fileCount;
  final String createdBy, updatedBy;
  final DateTime createdAt, updatedAt;
  const Nota({
    required this.id, required this.title, this.body = '', this.snippet = '', this.tags = const [],
    this.assetTags = const [], this.diagramCount = 0, this.fileCount = 0, this.createdBy = '', this.updatedBy = '',
    required this.createdAt, required this.updatedAt,
  });
  factory Nota.fromJson(Map<String, dynamic> j) => Nota(
        id: j['id'] as int,
        title: j['title'] as String,
        body: (j['body'] as String?) ?? '',
        snippet: (j['snippet'] as String?) ?? '',
        tags: ((j['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
        assetTags: _assetTags(j),
        diagramCount: (j['diagram_count'] as num?)?.toInt() ?? 0,
        fileCount: (j['file_count'] as num?)?.toInt() ?? 0,
        createdBy: (j['created_by'] as String?) ?? '',
        updatedBy: (j['updated_by'] as String?) ?? '',
        createdAt: _d(j['created_at']),
        updatedAt: _d(j['updated_at']),
      );
}

class NotaDiagrama {
  final int id;
  final String title, xml;
  final String? updatedBy;
  final Uint8List? preview; // PNG decodificado una sola vez
  final DateTime updatedAt;
  const NotaDiagrama({required this.id, required this.title, this.xml = '', this.updatedBy, this.preview, required this.updatedAt});

  static Uint8List? _decode(String? d) {
    if (d == null) return null;
    final i = d.indexOf(',');
    if (i < 0) return null;
    try {
      return base64Decode(d.substring(i + 1));
    } catch (_) {
      return null;
    }
  }

  factory NotaDiagrama.fromJson(Map<String, dynamic> j) => NotaDiagrama(
        id: j['id'] as int,
        title: (j['title'] as String?) ?? 'Diagrama',
        xml: (j['xml'] as String?) ?? '',
        updatedBy: j['updated_by'] as String?,
        preview: _decode(j['preview'] as String?),
        updatedAt: _d(j['updated_at']),
      );
}

class NotaArchivo {
  final int id, size;
  final String name;
  final String? contentType, createdBy;
  final DateTime createdAt;
  const NotaArchivo({required this.id, required this.name, required this.size, this.contentType, this.createdBy, required this.createdAt});
  factory NotaArchivo.fromJson(Map<String, dynamic> j) => NotaArchivo(
        id: j['id'] as int,
        name: j['original_name'] as String,
        size: (j['size'] as num?)?.toInt() ?? 0,
        contentType: j['content_type'] as String?,
        createdBy: j['created_by'] as String?,
        createdAt: _d(j['created_at']),
      );
}

class NotaRevision {
  final int id, version;
  final String action, changedBy;
  final String? detail, title, body;
  final bool hasSnapshot;
  final List<String> tags, assetTags;
  final DateTime changedAt;
  const NotaRevision({
    required this.id, required this.version, required this.action, required this.changedBy, this.detail,
    this.hasSnapshot = false, this.title, this.body, this.tags = const [], this.assetTags = const [], required this.changedAt,
  });
  factory NotaRevision.fromJson(Map<String, dynamic> j) => NotaRevision(
        id: j['id'] as int,
        version: (j['version'] as num).toInt(),
        action: j['action'] as String,
        changedBy: (j['changed_by'] as String?) ?? '',
        detail: j['detail'] as String?,
        hasSnapshot: j['has_snapshot'] as bool? ?? false,
        title: j['title'] as String?,
        body: j['body'] as String?,
        tags: ((j['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
        assetTags: ((j['asset_tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
        changedAt: _d(j['changed_at']),
      );
}

class TagCount {
  final String tag;
  final int count;
  const TagCount(this.tag, this.count);
  factory TagCount.fromJson(Map<String, dynamic> j) => TagCount(j['tag'] as String, (j['count'] as num).toInt());
}
