import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data.dart';
import '../ui/components.dart';
import '../ui/format.dart';
import '../ui/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _loaded = false;
  bool _busy = false;
  String? _error;
  final _name = TextEditingController();
  final _goal = TextEditingController();
  final _interests = TextEditingController();
  String _level = 'A2';
  String? _voice;
  double _rate = 1.0;

  static const _levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];
  static const _goalSuggestions = ['旅行英语', '工作沟通', '日常社交', '面试准备', '更自然的口语'];
  static const _interestSuggestions = ['电影', '音乐', '旅行', '科技', '美食', '运动', '阅读'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final app = AppScope.of(context);
    final profile = app.profile ?? {};
    _name.text = (profile['display_name'] as String?) ?? '';
    _goal.text = (profile['goal'] as String?) ?? '';
    _interests.text = (profile['interests'] as String?) ?? '';
    final level = profile['level'];
    if (level is String && _levels.contains(level)) _level = level;
    final rate = profile['speech_rate'];
    if (rate is num) _rate = rate.toDouble().clamp(0.7, 1.3);
    final voices = app.voices;
    if (voices.isNotEmpty) {
      final existing = profile['voice'];
      _voice = voices.any((v) => v['id'] == existing) ? existing as String : voices.first['id'] as String?;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _goal.dispose();
    _interests.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 0 && _name.text.trim().isEmpty) {
      setState(() => _error = '请先填写你的称呼。');
      return;
    }
    setState(() {
      _error = null;
      _step = (_step + 1).clamp(0, 2);
    });
  }

  void _back() {
    setState(() {
      _error = null;
      _step = (_step - 1).clamp(0, 2);
    });
  }

  Future<void> _finish() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请先填写你的称呼。');
      return;
    }
    final app = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final changes = <String, dynamic>{
        'display_name': _name.text.trim(),
        'native_language': 'zh',
        'target_language': 'en',
        'level': _level,
        'goal': _goal.text.trim(),
        'interests': _interests.text.trim(),
        'speech_rate': _rate,
        'onboarding_completed': true,
      };
      if (_voice != null) changes['voice'] = _voice;
      await app.updateProfile(changes);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleTag(TextEditingController controller, String value) {
    final current = controller.text.trim();
    final parts = current
        .split(RegExp(r'[\n,，、]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    setState(() {
      if (parts.contains(value)) {
        parts.remove(value);
      } else {
        parts.add(value);
      }
      controller.text = parts.join('、');
    });
  }

  bool _hasTag(TextEditingController controller, String value) {
    return controller.text
        .split(RegExp(r'[\n,，、]'))
        .map((e) => e.trim())
        .contains(value);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: PageFrame(
            maxWidth: 820,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const LangoMark(size: 34),
                    const SizedBox(width: 10),
                    Text(
                      'Lango',
                      style: LangoTheme.display(22, weight: FontWeight.w500).copyWith(color: c.ink),
                    ),
                    const Spacer(),
                    Text(
                      '${_step + 1} / 3',
                      style: tabular(context.texts.labelSmall?.copyWith(color: c.faint)),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              await app.logout();
                            },
                      child: const Text('退出'),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Row(
                  children: List.generate(3, (index) {
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: index == 2 ? 0 : 6),
                        child: AnimatedContainer(
                          duration: context.motion(220),
                          height: 3,
                          decoration: BoxDecoration(
                            color: index <= _step ? c.teal : c.line,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 36),
                AnimatedSwitcher(
                  duration: context.motion(220),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.025, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _stepBody(app),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  ErrorBanner(message: _error!),
                ],
                const SizedBox(height: 28),
                Row(
                  children: [
                    if (_step > 0)
                      LangoButton(
                        label: '上一步',
                        variant: LangoButtonVariant.ghost,
                        onPressed: _busy ? null : _back,
                      ),
                    const Spacer(),
                    LangoButton(
                      label: _step == 2 ? '完成设置' : '继续',
                      icon: _step == 2 ? Icons.check_rounded : Icons.arrow_forward_rounded,
                      loading: _busy,
                      onPressed: _busy ? null : (_step == 2 ? _finish : _next),
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

  Widget _stepBody(AppState app) {
    switch (_step) {
      case 0:
        return _StepPanel(
          key: const ValueKey('identity'),
          eyebrow: '01 · 认识你',
          title: '先告诉我们，\n怎么称呼你？',
          description: '这将用于对话中的称呼。目标语言固定为英语，界面语言为中文。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LangoField(
                label: '称呼',
                controller: _name,
                hint: '例如：小林',
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _next(),
              ),
              const SizedBox(height: 26),
              Text('当前英语水平', style: context.texts.titleSmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _levels.map((level) {
                  return FilterPill(
                    label: levelLabel(level),
                    selected: _level == level,
                    onTap: () => setState(() => _level = level),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                '只影响场景与反馈的起点，不影响你已经可以说的话。',
                style: context.texts.bodySmall,
              ),
            ],
          ),
        );
      case 1:
        return _StepPanel(
          key: const ValueKey('goals'),
          eyebrow: '02 · 你的目标',
          title: '你想用英语\n做成什么事？',
          description: '这些信息只用于挑选合适的练习重点，你可以随时在设置里修改。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('快速选择', style: context.texts.titleSmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _goalSuggestions.map((value) {
                  return FilterPill(
                    label: value,
                    selected: _hasTag(_goal, value),
                    onTap: () => _toggleTag(_goal, value),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              LangoField(
                label: '练习目标',
                controller: _goal,
                hint: '例如：能更自在地完成商务会议与旅行对话',
                maxLines: 3,
                minLines: 2,
                enabled: !_busy,
              ),
              const SizedBox(height: 22),
              Text('兴趣与话题', style: context.texts.titleSmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _interestSuggestions.map((value) {
                  return FilterPill(
                    label: value,
                    selected: _hasTag(_interests, value),
                    onTap: () => _toggleTag(_interests, value),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              LangoField(
                label: '其他兴趣',
                controller: _interests,
                hint: '用顿号分隔，例如：纪录片、徒步',
                enabled: !_busy,
              ),
            ],
          ),
        );
      default:
        final voices = app.voices;
        return _StepPanel(
          key: const ValueKey('voice'),
          eyebrow: '03 · 声音',
          title: '最后，\n把声音调舒服。',
          description: '音色与语速会保存到你的账户。引擎是本机的练习偏好，入口在设置中。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (voices.isEmpty)
                InfoBanner(
                  message: '服务器暂未返回可用音色，完成后可在设置中调整。',
                  icon: Icons.info_outline_rounded,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: voices.map((voice) {
                    final id = voice['id'] as String?;
                    final name = (voice['name'] as String?) ?? id ?? '音色';
                    final accent = voice['accent'] as String?;
                    return FilterPill(
                      label: accent == null || accent.isEmpty ? name : '$name · $accent',
                      selected: _voice == id,
                      onTap: () => setState(() => _voice = id),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Text('语速', style: context.texts.titleSmall),
                  const Spacer(),
                  Text(
                    '${_rate.toStringAsFixed(2)}×',
                    style: tabular(context.texts.titleSmall?.copyWith(color: context.colors.teal)),
                  ),
                ],
              ),
              Slider(
                value: _rate,
                min: 0.7,
                max: 1.3,
                divisions: 12,
                label: '${_rate.toStringAsFixed(2)}×',
                onChanged: _busy ? null : (value) => setState(() => _rate = value),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('慢一些', style: context.texts.bodySmall),
                  Text('自然', style: context.texts.bodySmall),
                  Text('快一些', style: context.texts.bodySmall),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.colors.sunken,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('设置预览', style: context.texts.labelMedium),
                    const SizedBox(height: 10),
                    _ReviewRow(label: '称呼', value: _name.text.trim()),
                    _ReviewRow(label: '水平', value: levelLabel(_level)),
                    _ReviewRow(label: '目标', value: _goal.text.trim().isEmpty ? '尚未填写' : _goal.text.trim()),
                    _ReviewRow(
                      label: '音色',
                      value: _voice == null ? '服务器默认' : voices
                          .firstWhere((v) => v['id'] == _voice, orElse: () => {})['name'] as String? ?? _voice!,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _StepPanel extends StatelessWidget {
  const _StepPanel({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SurfacePanel(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 30),
      radius: 28,
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: context.texts.labelSmall?.copyWith(
              color: c.teal,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Text(title, style: context.texts.displaySmall?.copyWith(fontSize: 34, height: 1.16)),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(description, style: context.texts.bodySmall?.copyWith(height: 1.6)),
          ),
          const SizedBox(height: 30),
          child,
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: context.texts.bodySmall?.copyWith(color: context.colors.faint)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: context.texts.bodySmall?.copyWith(color: context.colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
