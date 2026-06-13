import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../services/settings_service.dart';
import '../../services/api_service.dart';
import '../../themes/app_theme.dart';
import '../../app.dart';

class AdminShell extends StatefulWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;
  String _companyName = 'Admin';  // default while loading

  final _settingsService = SettingsService(ApiService());

  @override
  void initState() {
    super.initState();
    _loadCompanyName();
  }

  Future<void> _loadCompanyName() async {
    try {
      final settings = await _settingsService.getSettings();
      if (mounted) {
        setState(() {
          _companyName = settings['company_name'] as String? ?? 'Admin';
        });
      }
    } catch (_) {
      // Keep default if settings fail
    }
  }

  final _navItems = const [
    _NavItem(icon: Icons.dashboard_outlined,     activeIcon: Icons.dashboard,         label: 'Dashboard',  route: '/admin'),
    _NavItem(icon: Icons.people_outline,         activeIcon: Icons.people,             label: 'Employees',  route: '/admin/employees'),
    _NavItem(icon: Icons.access_time_outlined,   activeIcon: Icons.access_time_filled, label: 'Attendance', route: '/admin/attendance'),
    _NavItem(icon: Icons.bar_chart_outlined,     activeIcon: Icons.bar_chart,          label: 'Analytics',  route: '/admin/analytics'),
    _NavItem(icon: Icons.notifications_outlined, activeIcon: Icons.notifications,      label: 'Alerts',     route: '/admin/notifications'),
    _NavItem(icon: Icons.settings_outlined,      activeIcon: Icons.settings,           label: 'Settings',   route: '/admin/settings'),
    _NavItem(icon: Icons.event_note_outlined,     activeIcon: Icons.event_note,         label: 'Leave',      route: '/admin/leave'),
    _NavItem(icon: Icons.credit_card_outlined,    activeIcon: Icons.credit_card,        label: 'RFID',       route: '/admin/rfid'),
  ];

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
    context.go(_navItems[index].route);

    // Reload company name when returning to any screen
    // (in case it was changed in Settings)
    if (_navItems[index].route == '/admin') {
      _loadCompanyName();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      body: Row(
        children: [
          // ── Desktop: Navigation Rail ─────────────────────────
          if (isWide) _buildNavigationRail(theme),

          // ── Main Content ─────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                _buildTopBar(theme, isWide),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),

      // ── Mobile: Bottom Navigation Bar ───────────────────────
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onNavTap,
              backgroundColor: theme.colorScheme.surface,
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: _navItems
                  .map((item) => NavigationDestination(
                        icon: Icon(item.icon),
                        selectedIcon:
                            Icon(item.activeIcon, color: AppTheme.primaryBlue),
                        label: item.label,
                      ))
                  .toList(),
            ),
    );
  }

  Widget _buildNavigationRail(ThemeData theme) {
    return NavigationRail(
      extended: MediaQuery.of(context).size.width >= 1100,
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onNavTap,
      backgroundColor: theme.cardTheme.color,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.fingerprint, color: Colors.white, size: 24),
        ),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ThemeCycleButton(small: true),
                IconButton(
                  icon: const Icon(Icons.logout_outlined,
                      color: Color(0xFF94A3B8)),
                  onPressed: () => _showLogoutDialog(context),
                ),
              ],
            ),
          ),
        ),
      ),
      destinations: _navItems
          .map((item) => NavigationRailDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.activeIcon),
                label: Text(item.label),
              ))
          .toList(),
    );
  }

  Widget _buildTopBar(ThemeData theme, bool isWide) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          if (!isWide) ...[
            const Icon(Icons.fingerprint,
                color: AppTheme.primaryBlue, size: 28),
            const SizedBox(width: 8),
          ],
          // ── Company Name ───────────────────────────────────
          Text(
            _companyName,
            style: AppTextStyles.heading3.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const Spacer(),

          if (isWide) ...[
            const _ThemeCycleButton(small: false),
            const SizedBox(width: 8),
            _AdminAvatar(onLogout: () => _showLogoutDialog(context)),
          ],
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AuthBloc>().add(AuthLogoutRequested());
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

// ── Admin Avatar ───────────────────────────────────────────────

class _AdminAvatar extends StatelessWidget {
  final VoidCallback onLogout;
  const _AdminAvatar({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final name = state is AuthAuthenticated
            ? state.user.employee?.firstName ?? 'Admin'
            : 'Admin';
        return PopupMenuButton<String>(
          child: CircleAvatar(
            backgroundColor: AppTheme.primaryBlue,
            radius: 18,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'A',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'profile',
              child: Row(children: [
                Icon(Icons.person_outline),
                SizedBox(width: 8),
                Text('Profile'),
              ]),
            ),
            PopupMenuItem(
              value: 'logout',
              child: Row(children: [
                Icon(Icons.logout, color: AppTheme.accentRed),
                const SizedBox(width: 8),
                Text('Sign out',
                    style: TextStyle(color: AppTheme.accentRed)),
              ]),
            ),
          ],
          onSelected: (val) {
            if (val == 'logout') onLogout();
          },
        );
      },
    );
  }
}

// ── Theme cycle button ─────────────────────────────────────────

class _ThemeCycleButton extends StatelessWidget {
  final bool small;
  const _ThemeCycleButton({required this.small});

  @override
  Widget build(BuildContext context) {
    final provider = ThemeToggleProvider.of(context);
    final variant  = provider?.variant ?? AppThemeVariant.light;

    final (IconData icon, String tooltip, Color color) = switch (variant) {
      AppThemeVariant.light     => (Icons.dark_mode_outlined,   'Switch to Dark',       const Color(0xFF94A3B8)),
      AppThemeVariant.dark      => (Icons.brightness_auto,      'Switch to Gold & Black', const Color(0xFF94A3B8)),
      AppThemeVariant.goldBlack => (Icons.light_mode_outlined,  'Switch to Light',      AppTheme.goldPrimary),
    };

    return Tooltip(
      message: tooltip,
      child: IconButton(
        iconSize: small ? 20 : 24,
        icon: Icon(icon, color: color),
        onPressed: () => provider?.toggleTheme(),
      ),
    );
  }
}

// ── Nav Item model ─────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
  });
}