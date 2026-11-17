import 'dart:async';

import 'package:balgres_it_contacts/balgres_it_contacts.dart' show Employee, apiError, empleadosProvider;
import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models.dart';
import 'providers.dart';

void _snack(BuildContext context, String m) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

String _when(DateTime d) => d.toString().substring(0, 16);

Color statusColor(SwissColors c, String s) => switch (s) {
      'Abierto' => c.accent2,
      'En curso' => c.accent,
      'En espera' => c.warn,
      'Resuelto' => c.ok,
      _ => c.muted,
    };

Color priorityColor(SwissColors c, String p) => switch (p) {
      'Crítica' => c.bad,
      'Alta' => c.warn,
      'Media' => c.accent2,
      _ => c.muted,
    };

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)] else ...[
            Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}

// ====================================================================== alta / edición
/// Devuelve el ticket guardado, o null si se cancela.
Future<int?> showTicketDialog(BuildContext context, WidgetRef ref, {int? editId, String? initialAsset}) async {
  final api = ref.read(ticketsApiProvider);
  Ticket? t;
  if (editId != null) {
    try {
      t = await api.obtener(editId);
    } catch (e) {
      _snack(context, apiError(e));
      return null;
    }
  }
  var emps = const <Employee>[];
  var users = const <TicketUser>[];
  try {
    emps = (await ref.read(empleadosProvider.future)).where((e) => e.active).toList();
  } catch (_) {}
  try {
    users = await ref.read(ticketsUsersProvider.future);
  } catch (_) {} // sin permiso de ver usuarios: el responsable queda como texto actual
  if (!context.mounted) return null;

  final title = TextEditingController(text: t?.title ?? '');
  final desc = TextEditingController(text: t?.description ?? '');
  final cat = TextEditingController(text: t?.category ?? '');
  var priority = t?.priority ?? 'Media';
  var status = t?.status ?? 'Abierto';
  Employee? emp = emps.where((e) => e.id == t?.requesterId).firstOrNull;
  var empId = t?.requesterId;
  var empName = t?.requesterName;
  var assets = <String>[if ((t?.assetTag ?? initialAsset) != null) (t?.assetTag ?? initialAsset)!];
  TicketUser? asg = users.where((u) => u.username == t?.assignee).firstOrNull;
  var asgName = t?.assignee;
  DateTime? due = t?.dueDate;
  String? err;

  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setM) => AlertDialog(
        title: Text(t == null ? 'Nuevo ticket' : 'Editar ${t.code}'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (err != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(err!, style: TextStyle(color: ctx.sw.bad, fontWeight: FontWeight.w600))),
              TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'Asunto *', hintText: 'No imprime en contabilidad')),
              const SizedBox(height: 12),
              TextField(controller: desc, minLines: 3, maxLines: 8, decoration: const InputDecoration(labelText: 'Descripción', alignLabelWithHint: true)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: priority,
                    decoration: const InputDecoration(labelText: 'Prioridad'),
                    items: [for (final p in kPriorities) DropdownMenuItem(value: p, child: Text(p))],
                    onChanged: (v) => setM(() => priority = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: status,
                    decoration: const InputDecoration(labelText: 'Estado'),
                    items: [for (final s in kStatuses) DropdownMenuItem(value: s, child: Text(s))],
                    onChanged: (v) => setM(() => status = v!),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: SuggestField(controller: cat, label: 'Categoría', suggestions: () => kCategories)),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final d = await showDatePicker(context: ctx, initialDate: due ?? DateTime.now().add(const Duration(days: 2)), firstDate: DateTime(2020), lastDate: DateTime(2100));
                      if (d != null) setM(() => due = d);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Fecha límite',
                        suffixIcon: due == null ? const Icon(Icons.event, size: 18) : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setM(() => due = null)),
                      ),
                      child: Text(due == null ? '—' : due!.toIso8601String().substring(0, 10)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              SearchSelect<Employee>(
                label: 'Solicitante',
                value: emp,
                options: emps,
                display: (e) => e.name,
                searchText: (e) => '${e.department ?? ''} ${e.position ?? ''} ${e.extension ?? ''}',
                subtitle: (e) => [e.position, e.department].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                onChanged: (e) => setM(() {
                  emp = e;
                  empId = e?.id;
                  empName = e?.name;
                }),
              ),
              if (emp == null && empName != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Solicitante actual: $empName', style: TextStyle(fontSize: 12, color: ctx.sw.muted))),
              const SizedBox(height: 12),
              if (users.isNotEmpty)
                SearchSelect<TicketUser>(
                  label: 'Responsable',
                  value: asg,
                  options: users,
                  display: (u) => u.display,
                  onChanged: (u) => setM(() {
                    asg = u;
                    asgName = u?.username;
                  }),
                )
              else if (asgName != null)
                Text('Responsable: $asgName', style: TextStyle(fontSize: 13, color: ctx.sw.muted)),
              const SizedBox(height: 12),
              AssetLinksField(label: 'Activo relacionado', tags: assets, multi: false, onChanged: (l) => setM(() => assets = l)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty) {
                setM(() => err = 'El asunto es obligatorio');
                return;
              }
              final body = {
                'title': title.text.trim(), 'description': desc.text.trim(), 'status': status, 'priority': priority,
                'category': cat.text.trim(), 'requester_id': empId, 'requester_name': empName,
                'asset_tag': assets.isEmpty ? null : assets.first, 'assignee': asgName,
                'due_date': due?.toIso8601String().substring(0, 10),
              };
              try {
                final saved = t == null ? await api.crear(body) : await api.actualizar(t.id, body);
                ref.invalidate(ticketsProvider);
                ref.invalidate(ticketsResumenProvider);
                if (ctx.mounted) Navigator.pop(ctx, saved.id);
              } catch (e) {
                setM(() => err = apiError(e));
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

// ====================================================================== lista
class TicketsPage extends ConsumerStatefulWidget {
  const TicketsPage({super.key});
  @override
  ConsumerState<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends ConsumerState<TicketsPage> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) ref.read(ticketsQueryProvider.notifier).state = v.trim();
    });
  }

  Future<void> _open(int id) async {
    await context.push('/tickets/$id');
    ref.invalidate(ticketsProvider);
    ref.invalidate(ticketsResumenProvider);
  }

  Future<void> _new() async {
    final id = await showTicketDialog(context, ref);
    if (id != null && mounted) _open(id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final async = ref.watch(ticketsProvider);
    final res = ref.watch(ticketsResumenProvider).valueOrNull ?? const <String, dynamic>{};
    final status = ref.watch(ticketsStatusProvider);
    final prio = ref.watch(ticketsPriorityProvider);
    final mine = ref.watch(ticketsMineProvider);
    final mobile = MediaQuery.sizeOf(context).width < 900;
    final list = async.valueOrNull ?? const <Ticket>[];
    final canEdit = AuthSession.can('tickets.editar');
    int n(String k) => (res[k] as num?)?.toInt() ?? 0;

    return Padding(
      padding: EdgeInsets.all(mobile ? 12 : 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tickets', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.0)),
              const SizedBox(height: 6),
              Text('Solicitudes de soporte con responsable, activo y seguimiento', style: TextStyle(fontSize: 13, color: c.muted)),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: () {
              ref.invalidate(ticketsProvider);
              ref.invalidate(ticketsResumenProvider);
            },
          ),
          if (canEdit) ...[
            const SizedBox(width: 4),
            FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add, size: 18), label: Text(mobile ? 'Nuevo' : 'Nuevo ticket')),
          ],
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 14, runSpacing: 14, children: [
          SizedBox(width: 180, child: KpiTile('Abiertos', '${n('abiertos')}', icon: Icons.confirmation_number_outlined)),
          SizedBox(width: 180, child: KpiTile('Sin asignar', '${n('sin_asignar')}', icon: Icons.person_off_outlined, color: c.warn)),
          SizedBox(width: 180, child: KpiTile('Vencidos', '${n('vencidos')}', icon: Icons.alarm, color: n('vencidos') > 0 ? c.bad : c.muted)),
          SizedBox(width: 180, child: KpiTile('Críticos', '${n('criticos')}', icon: Icons.priority_high, color: n('criticos') > 0 ? c.bad : c.muted)),
        ]),
        const SizedBox(height: 16),
        TextField(
          onChanged: _onQuery,
          decoration: const InputDecoration(hintText: 'Buscar por número (T-0012), asunto, solicitante, activo, responsable…', prefixIcon: Icon(Icons.search, size: 20)),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final s in ['abiertos', ...kStatuses, 'todos'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(s == 'abiertos' ? 'Abiertos' : (s == 'todos' ? 'Todos' : s)),
                  selected: status == s,
                  onSelected: (_) => ref.read(ticketsStatusProvider.notifier).state = s,
                ),
              ),
            const SizedBox(width: 8),
            for (final p in kPriorities)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(label: Text(p), selected: prio == p, onSelected: (v) => ref.read(ticketsPriorityProvider.notifier).state = v ? p : null),
              ),
            const SizedBox(width: 8),
            FilterChip(label: Text('Mis tickets · ${n('mios')}'), selected: mine, onSelected: (v) => ref.read(ticketsMineProvider.notifier).state = v),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: async.isLoading && list.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : async.hasError && list.isEmpty
                  ? Center(child: Text('Error: ${apiError(async.error!)}'))
                  : list.isEmpty
                      ? EmptyState(
                          icon: Icons.confirmation_number_outlined,
                          title: 'Sin tickets',
                          subtitle: 'Prueba con otro filtro o crea uno nuevo.',
                          action: canEdit ? 'Nuevo ticket' : null,
                          onAction: canEdit ? _new : null,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _TicketCard(t: list[i], onTap: () => _open(list[i].id)),
                        ),
        ),
      ]),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final Ticket t;
  final VoidCallback onTap;
  const _TicketCard({required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final meta = [
      if (t.requesterName != null) 'Solicita: ${t.requesterName}',
      if (t.assetTag != null) t.assetTag!,
      if (t.category != null) t.category!,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: cardDeco(context, radius: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(width: 5, height: 52, decoration: BoxDecoration(color: priorityColor(c, t.priority), borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(t.code, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.muted)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.isClosed ? c.muted : c.ink))),
                  ]),
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Pill(t.status, statusColor(c, t.status)),
                    Pill(t.priority, priorityColor(c, t.priority), icon: Icons.flag),
                    if (t.overdue) Pill('Vencido', c.bad, icon: Icons.alarm),
                    if (meta.isNotEmpty) Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
                  ]),
                  const SizedBox(height: 4),
                  Text('${t.assignee == null ? 'Sin asignar' : 'Responsable: ${t.assignee}'} · actualizado ${_when(t.updatedAt)}', style: TextStyle(fontSize: 11, color: c.muted)),
                ]),
              ),
              if (t.commentCount > 0) ...[Icon(Icons.chat_bubble_outline, size: 15, color: c.muted), const SizedBox(width: 3), Text('${t.commentCount}', style: TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w700)), const SizedBox(width: 8)],
              if (t.fileCount > 0) ...[Icon(Icons.attach_file, size: 15, color: c.muted), const SizedBox(width: 2), Text('${t.fileCount}', style: TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w700))],
              Icon(Icons.chevron_right, color: c.edge),
            ]),
          ),
        ),
      ),
    );
  }
}
