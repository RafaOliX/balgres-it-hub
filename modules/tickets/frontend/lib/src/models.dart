const kStatuses = ['Abierto', 'En curso', 'En espera', 'Resuelto', 'Cerrado'];
const kPriorities = ['Baja', 'Media', 'Alta', 'Crítica'];
const kCategories = ['Hardware', 'Software', 'Red', 'Cuenta / acceso', 'Impresión', 'Correo', 'Otro'];
const kClosed = ['Resuelto', 'Cerrado'];

DateTime _dt(dynamic v) => DateTime.parse(v as String).toLocal();

class TicketComment {
  final int id;
  final String kind, body, author;
  final DateTime createdAt;
  const TicketComment({required this.id, required this.kind, required this.body, required this.author, required this.createdAt});
  bool get isEvent => kind == 'evento';
  factory TicketComment.fromJson(Map<String, dynamic> j) => TicketComment(
        id: j['id'] as int, kind: j['kind'] as String, body: j['body'] as String, author: j['author'] as String, createdAt: _dt(j['created_at']));
}

class TicketArchivo {
  final int id, size;
  final String name;
  final String? createdBy;
  final DateTime createdAt;
  const TicketArchivo({required this.id, required this.name, required this.size, this.createdBy, required this.createdAt});
  factory TicketArchivo.fromJson(Map<String, dynamic> j) => TicketArchivo(
        id: j['id'] as int, name: j['original_name'] as String, size: (j['size'] as num?)?.toInt() ?? 0,
        createdBy: j['created_by'] as String?, createdAt: _dt(j['created_at']));
}

class TicketUser {
  final String username;
  final String? fullName;
  const TicketUser(this.username, this.fullName);
  String get display => (fullName ?? '').trim().isEmpty ? username : '$fullName (@$username)';
  factory TicketUser.fromJson(Map<String, dynamic> j) => TicketUser(j['username'] as String, j['full_name'] as String?);
}

class Ticket {
  final int id;
  final String title, description, status, priority, createdBy;
  final String? category, requesterName, assetTag, assignee;
  final int? requesterId;
  final DateTime? dueDate, resolvedAt;
  final DateTime createdAt, updatedAt;
  final bool overdue;
  final int commentCount, fileCount;
  final List<TicketComment> comments;
  final List<TicketArchivo> archivos;

  const Ticket({
    required this.id, required this.title, this.description = '', required this.status, required this.priority,
    this.category, this.requesterId, this.requesterName, this.assetTag, this.assignee, this.dueDate,
    required this.createdBy, required this.createdAt, required this.updatedAt, this.resolvedAt,
    this.overdue = false, this.commentCount = 0, this.fileCount = 0, this.comments = const [], this.archivos = const [],
  });

  String get code => 'T-${id.toString().padLeft(4, '0')}';
  bool get isClosed => kClosed.contains(status);

  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
        id: j['id'] as int,
        title: j['title'] as String,
        description: (j['description'] as String?) ?? '',
        status: j['status'] as String,
        priority: j['priority'] as String,
        category: j['category'] as String?,
        requesterId: j['requester_id'] as int?,
        requesterName: j['requester_name'] as String?,
        assetTag: j['asset_tag'] as String?,
        assignee: j['assignee'] as String?,
        dueDate: j['due_date'] == null ? null : DateTime.parse(j['due_date'] as String),
        createdBy: (j['created_by'] as String?) ?? '',
        createdAt: _dt(j['created_at']),
        updatedAt: _dt(j['updated_at']),
        resolvedAt: j['resolved_at'] == null ? null : _dt(j['resolved_at']),
        overdue: j['vencido'] as bool? ?? false,
        commentCount: (j['comment_count'] as num?)?.toInt() ?? 0,
        fileCount: (j['file_count'] as num?)?.toInt() ?? 0,
        comments: ((j['comments'] as List?) ?? const []).map((e) => TicketComment.fromJson(e as Map<String, dynamic>)).toList(),
        archivos: ((j['archivos'] as List?) ?? const []).map((e) => TicketArchivo.fromJson(e as Map<String, dynamic>)).toList(),
      );

  /// Cuerpo completo para PUT; [o] sobreescribe campos.
  Map<String, dynamic> toBody([Map<String, dynamic> o = const {}]) => {
        'title': title, 'description': description, 'status': status, 'priority': priority, 'category': category,
        'requester_id': requesterId, 'requester_name': requesterName, 'asset_tag': assetTag, 'assignee': assignee,
        'due_date': dueDate?.toIso8601String().substring(0, 10),
        ...o,
      };
}
