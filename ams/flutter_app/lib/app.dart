import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/auth/auth_bloc.dart';
import 'config/routes.dart';
import 'themes/app_theme.dart';

class AttendEaseApp extends StatefulWidget {
  const AttendEaseApp({super.key});

  @override
  State<AttendEaseApp> createState() => _AttendEaseAppState();
}

class _AttendEaseAppState extends State<AttendEaseApp> {
  AppThemeVariant _variant = AppThemeVariant.light;

  void _cycleTheme() {
    setState(() {
      _variant = AppThemeVariant.values[
          (_variant.index + 1) % AppThemeVariant.values.length];
    });
  }

  void _setTheme(AppThemeVariant variant) {
    setState(() => _variant = variant);
  }

  ThemeData get _activeTheme => switch (_variant) {
    AppThemeVariant.light     => AppTheme.lightTheme,
    AppThemeVariant.dark      => AppTheme.darkTheme,
    AppThemeVariant.goldBlack => AppTheme.goldBlackTheme,
  };

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final router = AppRouter.createRouter(authState);

        return MaterialApp.router(
          title: 'AttendEase',
          debugShowCheckedModeBanner: false,
          theme: _activeTheme,
          themeMode: ThemeMode.light, // always use `theme`, we manage it ourselves
          routerConfig: router,
          builder: (context, child) {
            return ThemeToggleProvider(
              toggleTheme: _cycleTheme,
              setTheme: _setTheme,
              variant: _variant,
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}

/// Makes theme toggle accessible throughout the widget tree
class ThemeToggleProvider extends InheritedWidget {
  final VoidCallback toggleTheme;
  final void Function(AppThemeVariant) setTheme;
  final AppThemeVariant variant;

  const ThemeToggleProvider({
    super.key,
    required this.toggleTheme,
    required this.setTheme,
    required this.variant,
    required super.child,
  });

  static ThemeToggleProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThemeToggleProvider>();
  }

  /// Convenience: is any dark-background theme active?
  bool get isDark =>
      variant == AppThemeVariant.dark || variant == AppThemeVariant.goldBlack;

  @override
  bool updateShouldNotify(ThemeToggleProvider old) => variant != old.variant;
}
