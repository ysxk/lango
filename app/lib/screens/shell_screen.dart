import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'memory_screen.dart';
import 'scenarios_screen.dart';
import 'settings_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  static const _labels = ['首页', '场景', '记录', '记忆'];
  static const _icons = [
    Icons.eco_outlined,
    Icons.landscape_outlined,
    Icons.history_rounded,
    Icons.auto_awesome_outlined,
  ];

  void _navigate(int index) => setState(() => _index = index.clamp(0, 3));

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 940;
    final pages = [
      HomeScreen(onNavigate: _navigate, onOpenSettings: _openSettings),
      const ScenariosScreen(),
      HistoryScreen(onBrowseScenarios: () => _navigate(1)),
      const MemoryScreen(),
    ];
    if (wide) {
      final extended = width >= 1120;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _Rail(
                extended: extended,
                index: _index,
                labels: _labels,
                icons: _icons,
                onSelect: _navigate,
                onSettings: _openSettings,
                app: app,
              ),
              Expanded(
                child: ClipRect(
                  child: IndexedStack(index: _index, children: pages),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _MobileBar(
              label: _labels[_index],
              app: app,
              onSettings: _openSettings,
            ),
            Expanded(
              child: IndexedStack(index: _index, children: pages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _navigate,
        destinations: [
          for (var i = 0; i < 4; i++)
            NavigationDestination(
              icon: Icon(_icons[i]),
              selectedIcon: Icon(_icons[i]),
              label: _labels[i],
            ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.extended,
    required this.index,
    required this.labels,
    required this.icons,
    required this.onSelect,
    required this.onSettings,
    required this.app,
  });

  final bool extended;
  final int index;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelect;
  final VoidCallback onSettings;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: context.motion(220),
      curve: Curves.easeOutCubic,
      width: extended ? 236 : 88,
      padding: EdgeInsets.fromLTRB(extended ? 18 : 12, 24, extended ? 18 : 12, 20),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: c.line.withValues(alpha: 0.5))),
      ),
      child: Column(
        crossAxisAlignment: extended ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(left: extended ? 6 : 0, bottom: 34),
            child: extended
                ? Row(
                    children: [
                      const LangoMark(size: 34),
                      const SizedBox(width: 10),
                      Text(
                        'Lango',
                        style: LangoTheme.display(23, weight: FontWeight.w500)
                            .copyWith(color: c.ink),
                      ),
                    ],
                  )
                : const LangoMark(size: 34),
          ),
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _RailItem(
                label: labels[i],
                icon: icons[i],
                selected: index == i,
                extended: extended,
                onTap: () => onSelect(i),
              ),
            ),
          const Spacer(),
          if (extended)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: c.sunken.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusDot(color: c.teal),
                      const SizedBox(width: 7),
                      Text('已连接', style: context.texts.labelSmall?.copyWith(color: c.secondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Uri.tryParse(app.server)?.host ?? app.server,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelSmall?.copyWith(fontSize: 10.5, color: c.faint),
                  ),
                  if (app.serverUsesCleartext) ...[
                    const SizedBox(height: 3),
                    Text(
                      'HTTP 明文 · 仅限可信局域网',
                      style: context.texts.labelSmall?.copyWith(fontSize: 10, color: c.danger),
                    ),
                  ],
                ],
              ),
            ),
          _RailItem(
            label: '设置',
            icon: Icons.tune_rounded,
            selected: false,
            extended: extended,
            onTap: onSettings,
          ),
          const SizedBox(height: 12),
          if (extended)
            InkWell(
              onTap: onSettings,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    _Avatar(name: app.displayName),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.titleSmall,
                          ),
                          Text(
                            app.isAdmin ? '管理员' : '练习者',
                            style: context.texts.labelSmall?.copyWith(color: c.faint),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            _Avatar(name: app.displayName),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final child = AnimatedContainer(
      duration: context.motion(170),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(horizontal: extended ? 13 : 0, vertical: 11),
      decoration: BoxDecoration(
        color: selected ? c.mint : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: selected ? c.mintInk : c.secondary),
          if (extended) ...[
            const SizedBox(width: 12),
            Text(
              label,
              style: context.texts.labelMedium?.copyWith(
                color: selected ? c.mintInk : c.secondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: extended
              ? child
              : Tooltip(message: label, child: child),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initial = name.trim().isEmpty ? 'L' : name.trim().characters.first.toUpperCase();
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.mint, shape: BoxShape.circle),
      child: Text(
        initial,
        style: context.texts.titleSmall?.copyWith(color: c.mintInk, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MobileBar extends StatelessWidget {
  const _MobileBar({required this.label, required this.app, required this.onSettings});
  final String label;
  final AppState app;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line.withValues(alpha: 0.45))),
      ),
      child: Row(
        children: [
          const LangoMark(size: 28),
          const SizedBox(width: 9),
          Text(
            'Lango',
            style: LangoTheme.display(20, weight: FontWeight.w500).copyWith(color: c.ink),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 16, color: c.line),
          const SizedBox(width: 10),
          Text(label, style: context.texts.labelMedium?.copyWith(color: c.secondary)),
          if (app.isAdmin) ...[
            const SizedBox(width: 8),
            TagChip('管理员', emphasis: true),
          ],
          const Spacer(),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.tune_rounded, size: 20),
            tooltip: '设置',
          ),
        ],
      ),
    );
  }
}
