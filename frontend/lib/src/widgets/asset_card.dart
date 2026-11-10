import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/it_asset.dart';
import 'asset_thumbnail.dart';

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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context.push('/inventario/detalle/${asset.assetTag}'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AssetThumbnail(asset: asset, size: 56),
              const SizedBox(width: 12),
              Expanded(
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
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            asset.status ?? '—',
                            style: TextStyle(
                                color: _statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${asset.brand} ${asset.model}',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      '${asset.category} · ${asset.serialNumber ?? 'Sin S/N'}',
                      style: const TextStyle(
                          fontSize: 11, color: _textSecondary),
                    ),
                    if (asset.location != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 12, color: _textSecondary),
                          const SizedBox(width: 3),
                          Text(asset.location!,
                              style: const TextStyle(
                                  fontSize: 11, color: _textSecondary)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
