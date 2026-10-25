import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../ui/components.dart';
import '../ui/scenario_card.dart';
import '../ui/theme.dart';
import 'scenario_detail_screen.dart';

class ScenariosScreen extends StatefulWidget {
  const ScenariosScreen({super.key});

  @override
  State<ScenariosScreen> createState() => _ScenariosScreenState();
}

class _ScenariosScreenState extends State<ScenariosScreen> {
  final _search = TextEditingController();
  String _category = '全部';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final categories = <String>{'全部'};
    for (final scenario in app.scenarios) {
      final category = scenario['category'];
      if (category is String && category.isNotEmpty) categories.add(category);
    }
    final query = _search.text.trim().toLowerCase();
    final filtered = app.scenarios.where((scenario) {
      if (_category != '全部' && scenario['category'] != _category) return false;
      if (query.isEmpty) return true;
      return ['title', 'subtitle', 'category', 'ai_role', 'setting']
          .map((key) => scenario[key]?.toString().toLowerCase() ?? '')
          .any((value) => value.contains(query));
    }).toList();

    return RefreshIndicator(
      color: c.teal,
      onRefresh: app.load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 48),
        child: PageFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 34),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SCENARIOS',
                          style: context.texts.labelSmall?.copyWith(
                            color: c.teal,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('场景练习', style: context.texts.displaySmall),
                        const SizedBox(height: 8),
                        Text(
                          '每个场景都有清晰的角色、目标与开场。选择你想练的那一刻。',
                          style: context.texts.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (MediaQuery.sizeOf(context).width >= 760)
                    SizedBox(
                      width: 280,
                      child: LangoField(
                        label: '搜索场景',
                        controller: _search,
                        hint: '标题、角色或情境',
                        prefixIcon: Icons.search_rounded,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                      ),
                    ),
                ],
              ),
              if (MediaQuery.sizeOf(context).width < 760) ...[
                const SizedBox(height: 20),
                LangoField(
                  label: '搜索场景',
                  controller: _search,
                  hint: '标题、角色或情境',
                  prefixIcon: Icons.search_rounded,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categories.map((category) {
                  return FilterPill(
                    label: category,
                    selected: _category == category,
                    onTap: () => setState(() => _category = category),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              if (app.error != null && app.scenarios.isEmpty)
                ErrorBanner(message: app.error!, onRetry: app.load)
              else if (app.loading && app.scenarios.isEmpty)
                const LoadingBlock(label: '正在载入场景…')
              else if (app.scenarios.isEmpty)
                SurfacePanel(
                  child: EmptyState(
                    title: '还没有可用场景',
                    message: '场景由服务端提供。请检查服务配置，或稍后刷新。',
                    icon: Icons.landscape_outlined,
                    action: LangoButton(
                      label: '刷新',
                      icon: Icons.refresh_rounded,
                      variant: LangoButtonVariant.outline,
                      onPressed: app.loading ? null : app.load,
                    ),
                  ),
                )
              else if (filtered.isEmpty)
                SurfacePanel(
                  child: EmptyState(
                    title: '没有匹配的场景',
                    message: '换一个关键词，或清除分类筛选。',
                    icon: Icons.search_off_rounded,
                    action: LangoButton(
                      label: '清除筛选',
                      variant: LangoButtonVariant.outline,
                      onPressed: () {
                        _search.clear();
                        setState(() => _category = '全部');
                      },
                    ),
                  ),
                )
              else
                _ScenarioWrap(scenarios: filtered),
              const SizedBox(height: 16),
              Text(
                '共 ${filtered.length} 个场景 · 来自你的服务端',
                style: context.texts.labelSmall?.copyWith(color: c.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScenarioWrap extends StatelessWidget {
  const _ScenarioWrap({required this.scenarios});
  final List<Map<String, dynamic>> scenarios;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1060 ? 3 : width >= 660 ? 2 : 1;
        const gap = 16.0;
        final cardWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < scenarios.length; i++)
              SizedBox(
                width: cardWidth,
                child: StaggeredReveal(
                  index: i,
                  child: ScenarioCard(
                    scenario: scenarios[i],
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ScenarioDetailScreen(scenario: scenarios[i]),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
