class ItAssetHistory {
  final int id;
  final String fieldName;
  final String? oldValue;
  final String? newValue;
  final String changedBy;
  final DateTime changedAt;

  const ItAssetHistory({
    required this.id,
    required this.fieldName,
    this.oldValue,
    this.newValue,
    required this.changedBy,
    required this.changedAt,
  });

  factory ItAssetHistory.fromJson(Map<String, dynamic> j) => ItAssetHistory(
        id: j['id'] as int,
        fieldName: j['field_name'] as String,
        oldValue: j['old_value'] as String?,
        newValue: j['new_value'] as String?,
        changedBy: j['changed_by'] as String,
        changedAt: DateTime.parse(j['changed_at'] as String).toLocal(),
      );
}
