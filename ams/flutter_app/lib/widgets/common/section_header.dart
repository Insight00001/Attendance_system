import 'package:flutter/material.dart';
import '../../themes/app_theme.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showViewAll;
  final VoidCallback? onViewAll;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showViewAll = true,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.heading3),
              if (subtitle != null)
                Text(subtitle!,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B))),
            ],
          ),
        ),
        if (showViewAll)
          TextButton(
            onPressed: onViewAll,
            child: const Text('View all →',
                style: TextStyle(
                    fontSize: 13, color: AppTheme.primaryBlue)),
          ),
      ],
    );
  }
}
