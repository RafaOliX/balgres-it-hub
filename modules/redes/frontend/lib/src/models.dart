class IpEntry {
  final int id;
  final String ip, origin;
  final String? label, kind, department, notes, assetTag, mac, subnet, lastSeen;
  final bool? isUp;
  const IpEntry({
    required this.id, required this.ip, required this.origin, this.label, this.kind, this.department,
    this.notes, this.assetTag, this.mac, this.subnet, this.lastSeen, this.isUp,
  });
  factory IpEntry.fromJson(Map<String, dynamic> j) => IpEntry(
        id: j['id'] as int,
        ip: j['ip'] as String,
        origin: (j['origin'] as String?) ?? 'manual',
        label: j['label'] as String?,
        kind: j['kind'] as String?,
        department: j['department'] as String?,
        notes: j['notes'] as String?,
        assetTag: j['asset_tag'] as String?,
        mac: j['mac'] as String?,
        subnet: j['subnet'] as String?,
        lastSeen: j['last_seen'] as String?,
        isUp: j['is_up'] as bool?,
      );
}

class Subnet {
  final int id;
  final String name, cidr;
  final String? notes;
  const Subnet({required this.id, required this.name, required this.cidr, this.notes});
  factory Subnet.fromJson(Map<String, dynamic> j) =>
      Subnet(id: j['id'] as int, name: j['name'] as String, cidr: j['cidr'] as String, notes: j['notes'] as String?);
}
