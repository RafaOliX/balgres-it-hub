import 'package:flutter/material.dart';

import '../models/it_asset.dart';

const _border = Color(0xFFE5E7EB);
const _textSecondary = Color(0xFF6B7280);

class AssetCard extends StatelessWidget {
  final ItAsset asset;
  const AssetCard({super.key, required this.asset});

  Color get _statusColor => switch (asset.status) {
        'Operativo' => const Color(0xFF10B981),
        'En Revisión' => const Color(0xFFF59E0B),
        'Retirado' => const Color(0xFFEF4444),
        _ => _textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    asset.assetTag,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    asset.status ?? '—',
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${asset.brand} ${asset.model}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.qr_code_2,
                    size: 13, color: _textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    asset.serialNumber,
                    style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: _textSecondary),
                  ),
                ),
                if (asset.location != null) ...[
                  const Icon(Icons.place_outlined,
                      size: 13, color: _textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    asset.location!,
                    style: const TextStyle(
                        fontSize: 12, color: _textSecondary),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              asset.category,
              style: const TextStyle(fontSize: 12, color: _textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
