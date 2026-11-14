import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'models.dart';

class IpCol {
  final String id, label;
  final double width;
  const IpCol(this.id, this.label, this.width);
}

const kIpColumns = <IpCol>[
  IpCol('ip', 'IP', 140),
  IpCol('name', 'Nombre', 200),
  IpCol('kind', 'Tipo', 160),
  IpCol('state', 'Estado', 170),
  IpCol('ms', 'Latencia', 100),
  IpCol('os', 'Sistema', 130),
  IpCol('ports', 'Puertos', 140),
  IpCol('host', 'Hostname', 170),
  IpCol('mac', 'MAC', 150),
  IpCol('segment', 'Segmento', 130),
  IpCol('asset', 'Activo', 110),
  IpCol('seen', 'Visto', 150),
];

String ipStatusLabel(IpEntry e) => switch (e.state) {
      'sin_ip' => 'Sin IP',
      'invalida' => 'IP no válida',
      'conflicto' => 'IP en conflicto',
      'pendiente' => 'Pendiente de sincronizar',
      _ => (e.isUp == null ? 'Sin verificar' : (e.isUp! ? 'En línea' : 'Sin respuesta')) + (e.isDraft ? ' · borrador' : ''),
    };

Color _statusColor(SwissColors c, IpEntry e) =>
    e.state != 'registrada' ? c.warn : (e.isUp == null ? c.muted : (e.isUp! ? c.ok : c.bad));

String? _t(String? s) => (s == null || s.trim().isEmpty) ? null : normalizeText(s.trim());

/// Nulos y vacíos siempre al final, sea cual sea la dirección.
int _nl<T>(T? a, T? b, int Function(T, T) f, bool asc) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  final c = f(a, b);
  return asc ? c : -c;
}

List<int>? _octets(String s) {
  final p = s.trim().split('.');
  if (p.length != 4) return null;
  final n = [for (final x in p) int.tryParse(x)];
  return n.contains(null) ? null : [for (final x in n) x!];
}

/// Las IPs se comparan por octetos (.9 antes que .10); lo que no es IP va después.
int _cmpIp(String a, String b) {
  final pa = _octets(a), pb = _octets(b);
  if (pa == null && pb == null) return a.compareTo(b);
  if (pa == null) return 1;
  if (pb == null) return -1;
  for (var i = 0; i < 4; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return 0;
}

List<IpEntry> sortIps(List<IpEntry> list, String? col, bool asc) {
  if (col == null) return list;
  int txt(String? x, String? y) => _nl<String>(_t(x), _t(y), (p, q) => p.compareTo(q), asc);
  int cmp(IpEntry a, IpEntry b) {
    switch (col) {
      case 'ip':
        return _nl<String>(a.ip.isEmpty ? null : a.ip, b.ip.isEmpty ? null : b.ip, _cmpIp, asc);
      case 'name':
        return txt(a.label, b.label);
      case 'kind':
        return txt(a.kind ?? a.kindHint, b.kind ?? b.kindHint);
      case 'state':
        return txt(ipStatusLabel(a), ipStatusLabel(b));
      case 'ms':
        return _nl<double>(a.latencyMs, b.latencyMs, (p, q) => p.compareTo(q), asc);
      case 'os':
        return txt(a.osHint, b.osHint);
      case 'ports':
        return _nl<int>(a.openPorts.isEmpty ? null : a.openPorts.length, b.openPorts.isEmpty ? null : b.openPorts.length, (p, q) => p.compareTo(q), asc);
      case 'host':
        return txt(a.hostname ?? a.dnsName, b.hostname ?? b.dnsName);
      case 'mac':
        return txt(a.mac, b.mac);
      case 'segment':
        return _nl<String>(a.segment?.split('/').first, b.segment?.split('/').first, _cmpIp, asc);
      case 'asset':
        return txt(a.assetTag, b.assetTag);
      case 'seen':
        return _nl<String>(a.lastSeen, b.lastSeen, (p, q) => p.compareTo(q), asc);
      default:
        return 0;
    }
  }

  return [...list]..sort(cmp);
}

/// Tabla de escritorio: los encabezados ordenan (asc → desc → sin orden).
class IpTable extends StatelessWidget {
  final List<IpEntry> rows;
  final String? sort;
  final bool asc;
  final void Function(String id) onSort;
  final void Function(IpEntry) onEdit, onDelete;
  const IpTable({super.key, required this.rows, required this.sort, required this.asc, required this.onSort, required this.onEdit, required this.onDelete});

  Widget _cell(BuildContext context, IpCol col, IpEntry e) {
    final c = context.sw;
    Widget t(String? s, {bool bold = false}) {
      final empty = s == null || s.isEmpty;
      return Text(
        empty ? '—' : s,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: empty ? TextStyle(fontSize: 13, color: c.muted) : TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
      );
    }

    Widget child;
    switch (col.id) {
      case 'ip':
        child = t(e.ip.isEmpty ? 'Sin IP' : e.ip, bold: true);
      case 'name':
        child = t(e.label);
      case 'kind':
        child = t(e.kind ?? e.kindHint);
      case 'state':
        child = Row(children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: _statusColor(c, e), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Flexible(child: t(ipStatusLabel(e))),
        ]);
      case 'ms':
        child = t(e.latencyMs == null ? null : '${e.latencyMs!.toStringAsFixed(0)} ms');
      case 'os':
        child = t(e.osHint);
      case 'ports':
        child = t(e.openPorts.isEmpty ? null : e.openPorts.join(', '));
      case 'host':
        child = t(e.hostname ?? e.dnsName);
      case 'mac':
        child = t(e.mac);
      case 'segment':
        child = t(e.segment);
      case 'asset':
        child = t(e.assetTag);
      case 'seen':
        final d = e.lastSeen == null ? null : DateTime.tryParse(e.lastSeen!)?.toLocal();
        child = t(d?.toString().substring(0, 16));
      default:
        child = const SizedBox.shrink();
    }
    return SizedBox(width: col.width, child: Padding(padding: const EdgeInsets.only(right: 12), child: Align(alignment: Alignment.centerLeft, child: child)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final totalW = kIpColumns.fold<double>(0, (s, e) => s + e.width) + 96 + 24;

    return Container(
      decoration: cardDeco(context),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (ctx, cs) {
        final w = totalW > cs.maxWidth ? totalW : cs.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: w,
            height: cs.maxHeight,
            child: Column(children: [
              Container(
                height: 48,
                color: c.panel,
                child: Row(children: [
                  const SizedBox(width: 16),
                  for (final col in kIpColumns)
                    InkWell(
                      onTap: () => onSort(col.id),
                      child: SizedBox(
                        width: col.width,
                        height: 48,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Row(children: [
                            Flexible(child: SectionLabel(col.label)),
                            if (sort == col.id)
                              Padding(padding: const EdgeInsets.only(left: 4), child: Icon(asc ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: c.accent)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
              Divider(height: 1, color: c.line),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final e = rows[i];
                    final editable = e.assetTag == null && e.state == 'registrada';
                    return InkWell(
                      onTap: e.assetTag != null ? () => context.push('/inventario/detalle/${e.assetTag}') : null,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                        child: Row(children: [
                          const SizedBox(width: 16),
                          for (final col in kIpColumns) _cell(context, col, e),
                          SizedBox(
                            width: 96,
                            child: editable
                                ? Row(children: [
                                    IconButton(icon: const Icon(Icons.edit_outlined, size: 20), tooltip: e.origin == 'escaneo' ? 'Registrar (pasa a manual)' : 'Editar', onPressed: () => onEdit(e)),
                                    IconButton(icon: Icon(Icons.delete_outline, size: 20, color: c.bad), tooltip: 'Eliminar', onPressed: () => onDelete(e)),
                                  ])
                                : null,
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}
