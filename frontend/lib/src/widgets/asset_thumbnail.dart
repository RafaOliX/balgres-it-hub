import 'package:flutter/material.dart';

import '../models/it_asset.dart';

class AssetThumbnail extends StatelessWidget {
  final ItAsset asset;
  final double size;
  const AssetThumbnail({super.key, required this.asset, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final color = switch (asset.status) {
      'Operativo' => const Color(0xFF10B981),
      'En Revisión' => const Color(0xFFF59E0B),
      'Retirado' => const Color(0xFFEF4444),
      _ => const Color(0xFF6B7280),
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: asset.imageUrl != null
            ? Image.network(
                asset.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(color),
              )
            : _placeholder(color),
      ),
    );
  }

  Widget _placeholder(Color color) => Container(
        color: color.withOpacity(0.12),
        child: Icon(Icons.inventory_2, color: color, size: size * 0.5),
      );
}
