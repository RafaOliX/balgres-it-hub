class IpEntry {
  final int id;
  final String ip, origin;
  final String? label, kind, department, notes, assetTag, mac, subnet, lastSeen, hostname, segment;
  final String state; // registrada | sin_ip | invalida | conflicto | pendiente
  final bool? isUp;
  final bool isDraft;
  final double? latencyMs;
  final int? ttl;
  final List<int> openPorts;
  final String? dnsName, firstSeen, osHint, kindHint;
  const IpEntry({
    required this.id, required this.ip, required this.origin, this.label, this.kind, this.department,
    this.notes, this.assetTag, this.mac, this.subnet, this.lastSeen, this.isUp,
    this.hostname, this.segment, this.state = 'registrada', this.isDraft = false,
    this.latencyMs, this.ttl, this.openPorts = const [], this.dnsName, this.firstSeen, this.osHint, this.kindHint,
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
        hostname: j['hostname'] as String?,
        segment: j['segment'] as String?,
        state: (j['state'] as String?) ?? 'registrada',
        isDraft: j['is_draft'] as bool? ?? false,
        latencyMs: (j['latency_ms'] as num?)?.toDouble(),
        ttl: (j['ttl'] as num?)?.toInt(),
        openPorts: ((j['open_ports'] as List?) ?? const []).map((x) => (x as num).toInt()).toList(),
        dnsName: j['dns_name'] as String?,
        firstSeen: j['first_seen'] as String?,
        osHint: j['os_hint'] as String?,
        kindHint: j['kind_hint'] as String?,
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

/// Segmento /24 calculado a partir de las IPs registradas.
class Segment {
  final String cidr;
  final String? name;
  final int usadas, libres, enLinea, sinRespuesta, sinVerificar, borradores;
  const Segment({
    required this.cidr, this.name, required this.usadas, required this.libres,
    required this.enLinea, required this.sinRespuesta, required this.sinVerificar, required this.borradores,
  });
  factory Segment.fromJson(Map<String, dynamic> j) => Segment(
        cidr: j['cidr'] as String,
        name: j['name'] as String?,
        usadas: (j['usadas'] as num?)?.toInt() ?? 0,
        libres: (j['libres'] as num?)?.toInt() ?? 0,
        enLinea: (j['en_linea'] as num?)?.toInt() ?? 0,
        sinRespuesta: (j['sin_respuesta'] as num?)?.toInt() ?? 0,
        sinVerificar: (j['sin_verificar'] as num?)?.toInt() ?? 0,
        borradores: (j['borradores'] as num?)?.toInt() ?? 0,
      );
}

class DuplicateIp {
  final String ip;
  final List<Map<String, dynamic>> activos; // {tag, borrador, equipo}
  const DuplicateIp(this.ip, this.activos);
  factory DuplicateIp.fromJson(Map<String, dynamic> j) => DuplicateIp(
        j['ip'] as String,
        ((j['activos'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );
}
