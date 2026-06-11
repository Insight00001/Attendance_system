import 'package:flutter/material.dart';
import '../../themes/app_theme.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_outlined,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Notifications', style: AppTextStyles.heading3),
            const SizedBox(height: 8),
            Text('No new notifications',
                style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}
