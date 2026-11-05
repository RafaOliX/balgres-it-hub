import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageHeader(
            title: 'Dashboard',
            subtitle: 'Resumen del departamento de IT',
          ),
          const SizedBox(height: 24),
          const _StatsRow(),
          const SizedBox(height: 32),
          const Text('Módulos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _ModuleGrid(items: [
            _ModuleItem(
              icon: Icons.inventory_2_outlined,
              color: AppColors.primary,
              title: 'Inventario',
              subtitle: 'Activos de TI',
              onTap: () => context.go('/inventario'),
            ),
            const _ModuleItem(
              icon: Icons.confirmation_number_outlined,
              color: Color(0xFF0891B2),
              title: 'Tickets',
              subtitle: 'Próximamente',
            ),
            const _ModuleItem(
              icon: Icons.vpn_key_outlined,
              color: Color(0xFF7C3AED),
              title: 'Licencias',
              subtitle: 'Próximamente',
            ),
            const _ModuleItem(
              icon: Icons.people_outline,
              color: Color(0xFF059669),
              title: 'Usuarios',
              subtitle: 'Próximamente',
            ),
          ]),
        ],
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _PageHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 700;
      final cards = const [
        _StatCard(label: 'Total activos', value: '—', icon: Icons.inventory, color: AppColors.primary),
        _StatCard(label: 'Operativos', value: '—', icon: Icons.check_circle_outline, color: AppColors.success),
        _StatCard(label: 'En revisión', value: '—', icon: Icons.build_outlined, color: AppColors.warning),
        _StatCard(label: 'Retirados', value: '—', icon: Icons.archive_outlined, color: AppColors.danger),
      ];
      return wide
          ? Row(
              children: cards
                  .map((c) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: c,
                        ),
                      ))
                  .toList(),
            )
          : Wrap(
              spacing: 12,
              runSpacing: 12,
              children: cards
                  .map((c) => SizedBox(width: (constraints.maxWidth - 12) / 2, child: c))
                  .toList(),
            );
    });
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(value,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ModuleGrid extends StatelessWidget {
  final List<_ModuleItem> items;
  const _ModuleGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cross = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);
      return GridView.count(
        crossAxisCount: cross,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.6,
        children: items,
      );
    });
  }
}

class _ModuleItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _ModuleItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
