import 'package:balgres_it_contacts/balgres_it_contacts.dart' show apiError;
import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models.dart';
import 'providers.dart';
import 'ip_table.dart';
import 'segments_panel.dart';

const _kKinds = ['Router', 'Access Point', 'DVR', 'Cámara IP', 'Marcaje', 'Servidor', 'Computadora', 'Impresora', 'Switch'];

String _when(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  return d == null ? 'nunca' : d.toString().substring(0, 16);
}

void _snack(BuildContext context, String m) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

/// Alta / edición de una IP manual. [ip] precarga el campo (viene del escáner).
Future<void> showIpDialog(BuildContext context, WidgetRef ref, {IpEntry? entry, String? ip}) async {
  final ipC = TextEditingController(text: entry?.ip ?? ip ?? '');
  final label = TextEditingController(text: entry?.label ?? '');
  final kind = TextEditingController(text: entry?.kind ?? '');
  final dept = TextEditingController(text: entry?.department ?? '');
  final notes = TextEditingController(text: entry?.notes ?? '');
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(entry == null ? 'Registrar IP' : 'Editar IP'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ipC, autofocus: entry == null, decoration: const InputDecoration(labelText: 'Dirección IP *', hintText: '192.0.60.45')),
            const SizedBox(height: 12),
            TextField(controller: label, decoration: const InputDecoration(labelText: 'Nombre / equipo', hintText: 'DVR despacho')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: SuggestField(controller: kind, label: 'Tipo', suggestions: () => _kKinds)),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: dept, decoration: const InputDecoration(labelText: 'Departamento'))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas (sin usuarios ni claves)')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () async {
            if (ipC.text.trim().isEmpty) return;
            final body = {
              'ip': ipC.text.trim(), 'label': label.text.trim(), 'kind': kind.text.trim(),
              'department': dept.text.trim(), 'notes': notes.text.trim(),
            };
            try {
              final api = ref.read(redesApiProvider);
              if (entry == null) {
                await api.crearIp(body);
              } else {
                await api.actualizarIp(entry.id, body);
              }
              ref.invalidate(ipsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(apiError(e))));
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}

enum _Filter { all, up, down, unknown, manual, attention, drafts }

class RedesPage extends ConsumerStatefulWidget {
  const RedesPage({super.key});
  @override
  ConsumerState<RedesPage> createState() => _RedesPageState();
}

class _RedesPageState extends ConsumerState<RedesPage> {
  String _q = '';
  _Filter _filter = _Filter.all;
  String? _segment;
  String? _sort;
  bool _asc = true;
  bool _busy = false;

  Future<void> _verificar() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(redesApiProvider).verificarRegistradas();
      ref.invalidate(ipsProvider);
      _snack(context, '${r['activas']} de ${r['total']} IPs responden');
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan([String? presetCidr]) async {
    final subs = ref.read(subnetsProvider).valueOrNull ?? const <Subnet>[];
    final ctrl = TextEditingController();
    final cidr = presetCidr ?? await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Escanear subred'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Red (CIDR)', hintText: '192.0.60.0/24')),
            if (subs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in subs) ActionChip(label: Text('${s.name} · ${s.cidr}'), onPressed: () => ctrl.text = s.cidr),
              ]),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Escanear')),
        ],
      ),
    );
    if (cidr == null || cidr.isEmpty || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 20), Expanded(child: Text('Escaneando $cidr…'))]),
      ),
    );
    Map<String, dynamic> r;
    try {
      r = await ref.read(redesApiProvider).escanear(cidr);
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _snack(context, 'Error: ${apiError(e)}');
      return;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ref.invalidate(ipsProvider);

    final caidas = (r['registradas_caidas'] as List?) ?? const [];
    final nuevas = List<String>.from((r['vivas_sin_registrar'] as List?) ?? const []);
    final hechas = <String>{};
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: Text('Resultado · ${r['cidr']}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['vivas']} responden de ${r['escaneadas']} direcciones.'),
              const SizedBox(height: 14),
              const SectionLabel('Registradas que no responden'),
              const SizedBox(height: 6),
              if (caidas.isEmpty) const Text('Ninguna.'),
              for (final c in caidas) Text('${c['ip']}  ${c['nombre'] ?? ''}'),
              const SizedBox(height: 14),
              const SectionLabel('Responden pero no están registradas · toca para registrar'),
              const SizedBox(height: 6),
              if (nuevas.isEmpty) const Text('Ninguna.'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final ip in nuevas.take(60))
                  ActionChip(
                    avatar: hechas.contains(ip) ? const Icon(Icons.check, size: 16) : null,
                    label: Text(ip),
                    onPressed: hechas.contains(ip)
                        ? null
                        : () async {
                            try {
                              await ref.read(redesApiProvider).crearIp({'ip': ip, 'label': 'Detectada por escaneo'});
                              ref.invalidate(ipsProvider);
                              setD(() => hechas.add(ip));
                            } catch (e) {
                              _snack(ctx, apiError(e));
                            }
                          },
                  ),
              ]),
              if (nuevas.length > 60) Padding(padding: const EdgeInsets.only(top: 8), child: Text('… y ${nuevas.length - 60} más')),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
      )),
    );
  }

  Future<void> _subnets() async {
    final name = TextEditingController();
    final cidr = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final subs = ref.watch(subnetsProvider).valueOrNull ?? const <Subnet>[];
        return AlertDialog(
          title: const Text('Subredes'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (subs.isEmpty) const Text('Aún no hay subredes.'),
                for (final s in subs)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(s.cidr),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Eliminar',
                      onPressed: () async {
                        try {
                          await ref.read(redesApiProvider).eliminarSubnet(s.id);
                          ref.invalidate(subnetsProvider);
                          ref.invalidate(ipsProvider);
                        } catch (e) {
                          _snack(ctx, apiError(e));
                        }
                      },
                    ),
                  ),
                const Divider(height: 28),
                Row(children: [
                  Expanded(child: TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Comedor'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: cidr, decoration: const InputDecoration(labelText: 'Red (CIDR)', hintText: '192.0.60.0/24'))),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      if (name.text.trim().isEmpty || cidr.text.trim().isEmpty) return;
                      try {
                        await ref.read(redesApiProvider).crearSubnet(name.text.trim(), cidr.text.trim());
                        name.clear();
                        cidr.clear();
                        ref.invalidate(subnetsProvider);
                        ref.invalidate(ipsProvider);
                      } catch (e) {
                        _snack(ctx, apiError(e));
                      }
                    },
                    child: const Text('Agregar'),
                  ),
                ]),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
        );
      }),
    );
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(redesApiProvider).sincronizar();
      ref.invalidate(ipsProvider);
      final conf = (r['conflictos'] as List?) ?? const [];
      _snack(context, '${r['registradas']} IPs sincronizadas${(r['no_validas'] ?? 0) > 0 ? ' · ${r['no_validas']} no válidas' : ''}${conf.isEmpty ? '' : ' · ${conf.length} en conflicto'}');
      if (conf.isNotEmpty && mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('IPs en conflicto'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final c in conf) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${c['tag']} · ${c['ip']}\n${c['detalle']}')),
                ]),
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
          ),
        );
      }
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dups() async {
    try {
      final list = await ref.read(redesApiProvider).getDuplicadas();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(list.isEmpty ? 'Sin IPs duplicadas' : '${list.length} IP(s) duplicadas'),
          content: SizedBox(
            width: 520,
            child: list.isEmpty
                ? const Text('Ningún activo comparte IP con otro.')
                : SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final d in list) ...[
                        Text(d.ip, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          for (final a in d.activos)
                            ActionChip(
                              label: Text('${a['tag']}${a['borrador'] == true ? ' (borrador)' : ''}'),
                              onPressed: () {
                                Navigator.pop(ctx);
                                context.push('/inventario/detalle/${a['tag']}');
                              },
                            ),
                        ]),
                        const SizedBox(height: 14),
                      ],
                    ]),
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
        ),
      );
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  void _toggleSort(String id) => setState(() {
        if (_sort != id) {
          _sort = id;
          _asc = true;
        } else if (_asc) {
          _asc = false;
        } else {
          _sort = null;
          _asc = true;
        }
      });

  /// En móvil no hay encabezado: el orden se elige aquí.
  Widget _sortMenu() => PopupMenuButton<String>(
        tooltip: 'Ordenar',
        icon: Icon(_sort == null ? Icons.sort : (_asc ? Icons.arrow_upward : Icons.arrow_downward)),
        onSelected: (id) {
          if (id.isEmpty) {
            setState(() {
              _sort = null;
              _asc = true;
            });
          } else {
            _toggleSort(id);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: '', child: Text('Sin orden')),
          for (final col in kIpColumns) PopupMenuItem(value: col.id, child: Text('${col.label}${_sort == col.id ? (_asc ? ' ↑' : ' ↓') : ''}')),
        ],
      );

  /// Escanea uno a uno los segmentos conocidos y guarda las vivas sin registrar como "escaneo".
  Future<void> _scanAll() async {
    final segs = ref.read(segmentsProvider).valueOrNull ?? const <Segment>[];
    if (segs.isEmpty) {
      _snack(context, 'Aún no hay segmentos. Sincroniza o registra IPs primero.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Escanear ${segs.length} segmento(s)'),
        content: const Text('Cada segmento tarda unos 15-30 s. Las IPs que respondan y no estén registradas se guardarán como "detectadas". Puedes detenerlo en cualquier momento.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Escanear')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final progress = ValueNotifier<String>('Preparando…');
    var stop = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: ValueListenableBuilder<String>(
          valueListenable: progress,
          builder: (_, v, __) => Row(children: [const CircularProgressIndicator(), const SizedBox(width: 20), Expanded(child: Text(v))]),
        ),
        actions: [TextButton(onPressed: () => stop = true, child: const Text('Detener'))],
      ),
    );

    var vivas = 0, nuevas = 0, hechos = 0;
    String? err;
    for (final s in segs) {
      if (stop) break;
      progress.value = 'Escaneando ${s.name ?? s.cidr} (${hechos + 1}/${segs.length})…';
      try {
        final r = await ref.read(redesApiProvider).escanear(s.cidr, register: true);
        vivas += (r['vivas'] as num?)?.toInt() ?? 0;
        nuevas += (r['nuevas_registradas'] as num?)?.toInt() ?? 0;
      } catch (e) {
        err = apiError(e);
        break;
      }
      hechos++;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ref.invalidate(ipsProvider);
    _snack(context, '$hechos de ${segs.length} segmentos · $vivas responden · $nuevas nuevas guardadas${err == null ? '' : ' · Error: $err'}');
  }

  Future<void> _delete(IpEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar IP'),
        content: Text('¿Quitar ${e.ip} del registro?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(redesApiProvider).eliminarIp(e.id);
      ref.invalidate(ipsProvider);
    } catch (err) {
      _snack(context, apiError(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final async = ref.watch(ipsProvider);
    final mobile = MediaQuery.sizeOf(context).width < 900;
    final all = async.valueOrNull ?? const <IpEntry>[];

    final terms = normalizeText(_q.trim()).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final list = all.where((e) {
      if (_segment != null && e.segment != _segment) return false;
      switch (_filter) {
        case _Filter.up:
          if (e.isUp != true) return false;
        case _Filter.down:
          if (e.isUp != false) return false;
        case _Filter.unknown:
          if (e.isUp != null) return false;
        case _Filter.manual:
          if (e.assetTag != null) return false;
        case _Filter.attention:
          if (e.state == 'registrada') return false;
        case _Filter.drafts:
          if (!e.isDraft) return false;
        case _Filter.all:
          break;
      }
      if (terms.isEmpty) return true;
      final hay = normalizeText([e.ip, e.label, e.kind, e.department, e.assetTag, e.mac, e.subnet].whereType<String>().join(' '));
      return terms.every(hay.contains);
    }).toList();

    final sorted = sortIps(list, _sort, _asc);
    final up = all.where((e) => e.isUp == true).length;
    final down = all.where((e) => e.isUp == false).length;
    const labels = {
      _Filter.all: 'Todas', _Filter.up: 'En línea', _Filter.down: 'Sin respuesta',
      _Filter.unknown: 'Sin verificar', _Filter.manual: 'Sin activo',
      _Filter.attention: 'Sin IP / no válida / conflicto', _Filter.drafts: 'Reservadas (borrador)',
    };

    return Padding(
      padding: EdgeInsets.all(mobile ? 12 : 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Redes', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.0)),
              const SizedBox(height: 6),
              Text('Control de direcciones IP', style: TextStyle(fontSize: 13, color: c.muted)),
            ]),
          ),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Recargar', onPressed: () => ref.invalidate(ipsProvider)),
          IconButton(icon: const Icon(Icons.sync), tooltip: 'Sincronizar con inventario', onPressed: _busy ? null : _sync),
          IconButton(icon: const Icon(Icons.travel_explore), tooltip: 'Escanear todos los segmentos', onPressed: _busy ? null : _scanAll),
          IconButton(icon: const Icon(Icons.content_copy_outlined), tooltip: 'IPs duplicadas', onPressed: _dups),
          IconButton(icon: const Icon(Icons.hub_outlined), tooltip: 'Subredes', onPressed: _subnets),
          const SizedBox(width: 4),
          FilledButton.icon(onPressed: () => showIpDialog(context, ref), icon: const Icon(Icons.add, size: 18), label: Text(mobile ? 'IP' : 'Registrar IP')),
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 14, runSpacing: 14, children: [
          SizedBox(width: 190, child: KpiTile('IPs registradas', '${all.length}', icon: Icons.lan_outlined)),
          SizedBox(width: 190, child: KpiTile('En línea', '$up', icon: Icons.check_circle_outline, color: c.ok)),
          SizedBox(width: 190, child: KpiTile('Sin respuesta', '$down', icon: Icons.error_outline, color: down > 0 ? c.bad : c.muted)),
        ]),
        const SizedBox(height: 18),
        SegmentsPanel(selected: _segment, onSelect: (s) => setState(() => _segment = s), onScan: _scan),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(hintText: 'Buscar por IP, nombre, tag, MAC, departamento…', prefixIcon: Icon(Icons.search, size: 20)),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _verificar,
            icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.network_ping, size: 18),
            label: Text(mobile ? 'Ping' : 'Verificar registradas'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _scan, icon: const Icon(Icons.radar, size: 18), label: Text(mobile ? 'Escanear' : 'Escanear subred')),
        ]),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in _Filter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(labels[f]!), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
              ),
            if (mobile) _sortMenu(),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: async.isLoading && all.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : async.hasError && all.isEmpty
                  ? Center(child: Text('Error: ${apiError(async.error!)}'))
                  : list.isEmpty
                      ? EmptyState(
                          icon: Icons.lan_outlined,
                          title: all.isEmpty ? 'Aún no hay IPs registradas' : 'Sin resultados',
                          subtitle: all.isEmpty ? 'Registra una o crea activos con el campo técnico IP.' : 'Prueba con otra búsqueda o filtro.',
                          action: 'Registrar IP',
                          onAction: () => showIpDialog(context, ref),
                        )
                      : (mobile
                          ? ListView.builder(
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: sorted.length,
                              itemBuilder: (_, i) => _IpCard(entry: sorted[i], onEdit: (e) => showIpDialog(context, ref, entry: e), onDelete: _delete),
                            )
                          : IpTable(
                              rows: sorted,
                              sort: _sort,
                              asc: _asc,
                              onSort: _toggleSort,
                              onEdit: (e) => showIpDialog(context, ref, entry: e),
                              onDelete: _delete,
                            )),
        ),
      ]),
    );
  }
}

class _IpCard extends StatelessWidget {
  final IpEntry entry;
  final void Function(IpEntry) onEdit, onDelete;
  const _IpCard({required this.entry, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final e = entry;
    final virtual = e.state != 'registrada';
    final col = virtual ? c.warn : (e.isUp == null ? c.muted : (e.isUp! ? c.ok : c.bad));
    final status = switch (e.state) {
      'sin_ip' => 'Sin IP',
      'invalida' => 'IP no válida',
      'conflicto' => 'IP en conflicto',
      'pendiente' => 'Pendiente de sincronizar',
      _ => e.isUp == null ? 'Sin verificar' : (e.isUp! ? 'En línea' : 'Sin respuesta'),
    };
    final sub = [e.label, e.kind ?? e.kindHint, e.department].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final fromAsset = e.assetTag != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: cardDeco(context, radius: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: fromAsset ? () => context.push('/inventario/detalle/${e.assetTag}') : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(e.ip.isEmpty ? 'Sin IP' : e.ip, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    if (e.origin == 'escaneo')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: c.accent2.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                        child: Text('Detectada', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.accent2)),
                      ),
                    if (e.isDraft)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: c.warn.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                        child: Text(e.state == 'registrada' ? 'Reservada (borrador)' : 'Borrador', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.warn)),
                      ),
                    if (fromAsset)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text(e.assetTag!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.accent)),
                      ),
                  ]),
                  if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      status,
                      if (e.latencyMs != null) '${e.latencyMs!.toStringAsFixed(0)} ms',
                      if (e.osHint != null) e.osHint!,
                      if (e.openPorts.isNotEmpty) 'puertos ${e.openPorts.join(',')}',
                      if ((e.hostname ?? e.dnsName) != null) (e.hostname ?? e.dnsName)!,
                      if (e.mac != null) 'MAC ${e.mac}',
                      if (e.subnet != null) e.subnet!,
                      if (!virtual) 'visto: ${_when(e.lastSeen)}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ]),
              ),
              if (!fromAsset) ...[
                IconButton(icon: const Icon(Icons.edit_outlined, size: 20), tooltip: 'Editar', onPressed: () => onEdit(e)),
                IconButton(icon: Icon(Icons.delete_outline, size: 20, color: c.bad), tooltip: 'Eliminar', onPressed: () => onDelete(e)),
              ] else
                Icon(Icons.chevron_right, color: c.edge),
            ]),
          ),
        ),
      ),
    );
  }
}
