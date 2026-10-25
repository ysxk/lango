import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../talk/talk_controller.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'session_screen.dart';

class ScenarioDetailScreen extends StatefulWidget {
  const ScenarioDetailScreen({super.key, required this.scenario});
  final Map<String, dynamic> scenario;

  @override
  State<ScenarioDetailScreen> createState() => _ScenarioDetailScreenState();
}

class _ScenarioDetailScreenState extends State<ScenarioDetailScreen> {
  TalkMode _mode = TalkMode.ptt;
  String? _engine;

  String _text(String key, [String fallback = '']) {
    final value = widget.scenario[key];
    return value is String && value.isNotEmpty ? value : fallback;
  }

  List<String> get _goals {
    final goals = widget.scenario['goals'];
    if (goals is List) {
      return goals.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  List<String> get _phrases {
    final phrases = widget.scenario['useful_phrases'];
    if (phrases is List) {
      return phrases.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final engine = _engine ??
        (app.engines.any((e) => e['id'] == app.currentEngine)
            ? app.currentEngine
            : (app.config['default_engine'] as String?));

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Hero(
          scenario: widget.scenario,
          title: _text('title', '场景练习'),
          subtitle: _text('subtitle'),
          setting: _text('setting'),
        ),
        const SizedBox(height: 28),
        _Roles(
          learner: _text('learner_role', '学习者'),
          ai: _text('ai_role', '对话伙伴'),
        ),
        const SizedBox(height: 28),
        SectionHeading(title: '这一轮的目标', eyebrow: 'GOALS'),
        const SizedBox(height: 14),
        for (var i = 0; i < _goals.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.mint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: tabular(context.texts.labelSmall?.copyWith(
                      color: c.mintInk,
                      fontWeight: FontWeight.w600,
                    )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(_goals[i], style: context.texts.bodyMedium),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 22),
        if (_text('opening_line').isNotEmpty) ...[
          SectionHeading(title: '对方会先说', eyebrow: 'OPENING'),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.sunken,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              '“${_text('opening_line')}”',
              style: context.texts.bodyLarge?.copyWith(
                fontStyle: FontStyle.italic,
                height: 1.65,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(height: 26),
        ],
        if (_phrases.isNotEmpty) ...[
          SectionHeading(title: '可能用得上', eyebrow: 'PHRASES'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final phrase in _phrases)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.line.withValues(alpha: 0.8)),
                  ),
                  child: Text(phrase, style: context.texts.bodySmall?.copyWith(color: c.ink)),
                ),
            ],
          ),
        ],
      ],
    );

    final startPanel = SurfacePanel(
      padding: const EdgeInsets.all(24),
      radius: 26,
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('准备进入', style: context.texts.labelSmall?.copyWith(
            color: c.teal,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          )),
          const SizedBox(height: 10),
          Text(_text('title', '场景练习'), style: context.texts.headlineSmall),
          const SizedBox(height: 20),
          Text('说话方式', style: context.texts.labelMedium),
          const SizedBox(height: 8),
          SegmentedChoice<TalkMode>(
            options: const [
              ChoiceOption(value: TalkMode.ptt, label: '按住说话', hint: '手动提交'),
              ChoiceOption(value: TalkMode.handsFree, label: '自动静音', hint: '能量 VAD'),
            ],
            selected: _mode,
            onChanged: (value) => setState(() => _mode = value),
            wrap: false,
          ),
          const SizedBox(height: 10),
          Text(
            _mode == TalkMode.handsFree
                ? '检测到约 0.95 秒静音后提交。使用能量阈值检测，非神经网络 VAD。'
                : '按住按钮说话，松开后提交。说错了可先松手取消。',
            style: context.texts.bodySmall?.copyWith(fontSize: 12, height: 1.5),
          ),
          if (app.engines.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('练习引擎', style: context.texts.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in app.engines)
                  FilterPill(
                    label: (item['name'] as String?) ?? (item['id'] as String?) ?? '引擎',
                    selected: engine == item['id'],
                    onTap: () async {
                      final id = item['id'] as String?;
                      if (id == null) return;
                      setState(() => _engine = id);
                      await app.setAppearance(engine: id);
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          InfoBanner(
            icon: Icons.headphones_outlined,
            message: '半双工：对方说话时会暂停麦克风。建议佩戴耳机或使用外放时保持安静环境。',
          ),
          const SizedBox(height: 18),
          LangoButton(
            label: '开始这段对话',
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SessionScreen(
                    app: app,
                    mode: _mode,
                    scenarioId: widget.scenario['id'] as String?,
                    scenario: widget.scenario,
                    title: _text('title', '场景练习'),
                    subtitle: _text('subtitle'),
                    engine: engine,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            '对话通过一次性 WebSocket 票据连接；原始录音不会写入磁盘。',
            style: context.texts.bodySmall?.copyWith(fontSize: 11.5, color: c.faint),
          ),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 48),
          child: PageFrame(
            maxWidth: 1080,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: '返回场景',
                    ),
                    const SizedBox(width: 4),
                    Text('场景详情', style: context.texts.labelMedium),
                  ],
                ),
                const SizedBox(height: 18),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: content),
                      const SizedBox(width: 32),
                      SizedBox(width: 360, child: startPanel),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      content,
                      const SizedBox(height: 28),
                      startPanel,
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

class _Hero extends StatelessWidget {
  const _Hero({
    required this.scenario,
    required this.title,
    required this.subtitle,
    required this.setting,
  });

  final Map<String, dynamic> scenario;
  final String title;
  final String subtitle;
  final String setting;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final level = scenario['level'];
    final category = scenario['category'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (level is String) TagChip(level, emphasis: true),
            if (category is String) TagChip(category),
            const TagChip('角色对话', icon: Icons.forum_outlined),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: context.texts.displayMedium?.copyWith(fontSize: 44, height: 1.08),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(title == subtitle ? '' : subtitle, style: context.texts.bodyLarge?.copyWith(color: c.secondary)),
        ],
        if (setting.isNotEmpty) ...[
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(
              setting,
              style: context.texts.bodyMedium?.copyWith(color: c.secondary, height: 1.7),
            ),
          ),
        ],
      ],
    );
  }
}

class _Roles extends StatelessWidget {
  const _Roles({required this.learner, required this.ai});
  final String learner;
  final String ai;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RoleCard(
            label: '你的角色',
            value: learner,
            icon: Icons.person_outline_rounded,
            emphasis: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RoleCard(
            label: '对方角色',
            value: ai,
            icon: Icons.face_retouching_natural_outlined,
            emphasis: false,
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.emphasis,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: emphasis ? c.mint : c.surface,
        borderRadius: BorderRadius.circular(18),
        border: emphasis ? null : Border.all(color: c.line.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: emphasis ? c.mintInk : c.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.texts.labelSmall?.copyWith(
                    color: emphasis ? c.mintInk : c.faint,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: context.texts.titleSmall?.copyWith(
                    color: emphasis ? c.mintInk : c.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
