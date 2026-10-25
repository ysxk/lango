import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_scope.dart';
import 'data.dart';
import 'screens/auth_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell_screen.dart';
import 'ui/components.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LangoApp());
}

class LangoApp extends StatefulWidget {
  const LangoApp({super.key});

  @override
  State<LangoApp> createState() => _LangoAppState();
}

class _LangoAppState extends State<LangoApp> {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    _state.initialize();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  ThemeMode get _themeMode => switch (_state.theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: AnimatedBuilder(
        animation: _state,
        builder: (context, _) {
          final theme = LangoTheme.build(c: LangoColors.light);
          final dark = LangoTheme.build(c: LangoColors.dark);
          return MaterialApp(
            title: 'Lango · 英语口语练习',
            debugShowCheckedModeBanner: false,
            theme: theme,
            darkTheme: dark,
            themeMode: _themeMode,
            themeAnimationDuration: _state.reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
            themeAnimationCurve: Curves.easeOutCubic,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const _RootGate(),
          );
        },
      ),
    );
  }
}

class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.booting) return const _SplashScreen();
    if (app.server.isEmpty) return const ConnectScreen();
    if (!app.hasStoredSession) return const AuthScreen();
    if (app.profile == null) {
      if (app.error != null) return _LoadFailureScreen(message: app.error!);
      return const _SplashScreen();
    }
    if (!app.onboardingCompleted) return const OnboardingScreen();
    return const ShellScreen();
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LangoMark(size: 56),
            const SizedBox(height: 22),
            Text(
              'Lango',
              style: LangoTheme.display(30, weight: FontWeight.w500).copyWith(color: c.ink),
            ),
            const SizedBox(height: 8),
            Text('正在准备你的练习室', style: context.texts.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _LoadFailureScreen extends StatelessWidget {
  const _LoadFailureScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: PageFrame(
          maxWidth: 560,
          child: Center(
            child: SingleChildScrollView(
              child: SurfacePanel(
                padding: const EdgeInsets.all(32),
                elevated: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LangoMark(size: 48),
                    const SizedBox(height: 24),
                    Text('暂时无法载入账户', style: context.texts.headlineSmall),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: context.texts.bodySmall?.copyWith(color: c.secondary),
                    ),
                    const SizedBox(height: 24),
                    LangoButton(
                      label: '重试',
                      icon: Icons.refresh_rounded,
                      expand: true,
                      onPressed: app.loading
                          ? null
                          : () async {
                              await app.load();
                            },
                    ),
                    const SizedBox(height: 10),
                    LangoButton(
                      label: '使用其他账户',
                      variant: LangoButtonVariant.outline,
                      expand: true,
                      onPressed: () async {
                        await app.logout();
                      },
                    ),
                    const SizedBox(height: 10),
                    LangoButton(
                      label: '更换服务器',
                      variant: LangoButtonVariant.ghost,
                      expand: true,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ConnectScreen(switching: true),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
