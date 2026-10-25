import 'package:flutter/material.dart';

import 'theme.dart';

class ScenarioCard extends StatelessWidget {
  const ScenarioCard({
    super.key,
    required this.scenario,
    required this.onTap,
  });

  final Map<String, dynamic> scenario;
  final VoidCallback onTap;

  String _text(String key, [String fallback = '']) {
    final value = scenario[key];
    return value is String && value.isNotEmpty ? value : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final goals = scenario['goals'];
    final goalCount = goals is List ? goals.length : 0;
    final aiRole = _text('ai_role', 'AI 角色');
    final learnerRole = _text('learner_role', '你');
    return Semantics(
      button: true,
      label: _text('title', '场景'),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: c.line.withValues(alpha: 0.65)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: c.mint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _text('level', '—'),
                        style: context.texts.labelSmall?.copyWith(
                          color: c.mintInk,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _text('category', '练习'),
                      style: context.texts.labelSmall?.copyWith(color: c.faint),
                    ),
                    const Spacer(),
                    Icon(Icons.arrow_outward_rounded, size: 17, color: c.faint),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  _text('title', '未命名场景'),
                  style: context.texts.headlineSmall?.copyWith(fontSize: 21, height: 1.25),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  _text('subtitle', '开始一段角色对话'),
                  style: context.texts.bodySmall?.copyWith(color: c.secondary, height: 1.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.record_voice_over_outlined, size: 14, color: c.faint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$learnerRole ↔ $aiRole',
                        style: context.texts.labelSmall?.copyWith(color: c.faint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _ScenarioTag('$goalCount 个目标'),
                    const Spacer(),
                    Text(
                      '进入场景',
                      style: context.texts.labelSmall?.copyWith(
                        color: c.teal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScenarioTag extends StatelessWidget {
  const _ScenarioTag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.sunken,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: context.texts.labelSmall?.copyWith(
          color: c.secondary,
        ),
      ),
    );
  }
}
