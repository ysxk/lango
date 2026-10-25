import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data.dart';
import '../talk/talk_controller.dart';
import '../ui/components.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import 'session_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.onBrowseScenarios});
  final VoidCallback onBrowseScenarios;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final sessions = app.sessions;
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
                          'HISTORY',
                          style: context.texts.labelSmall?.copyWith(
                            color: c.teal,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('对话记录', style: context.texts.displaySmall),
                        const SizedBox(height: 8),
                        Text(
                          '只显示服务端真实保存的对话。可以回看，也可以继续同一段会话。',
                          style: context.texts.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: app.loading ? null : app.load,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: '刷新记录',
                  ),
                ],
              ),
              if (app.error != null) ...[
                const SizedBox(height: 16),
                ErrorBanner(message: app.error!, onRetry: app.load),
              ],
              const SizedBox(height: 24),
              if (app.loading && sessions.isEmpty)
                const LoadingBlock(label: '正在载入对话记录…')
              else if (sessions.isEmpty)
                SurfacePanel(
                  padding: EdgeInsets.zero,
                  child: EmptyState(
                    icon: Icons.history_rounded,
                    title: '还没有对话记录',
                    message: '完成一段对话后，它会出现在这里。我们不会创建演示记录。',
                    action: LangoButton(
                      label: '去挑一个场景',
                      icon: Icons.arrow_forward_rounded,
                      variant: LangoButtonVariant.outline,
                      onPressed: onBrowseScenarios,
                    ),
                  ),
                )
              else
                _SessionGroups(app: app),
              const SizedBox(height: 16),
              if (sessions.isNotEmpty)
                Text(
                  '共 ${sessions.length} 条 · 最多显示最近 100 条',
                  style: context.texts.labelSmall?.copyWith(color: c.faint),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionGroups extends StatelessWidget {
  const _SessionGroups({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    final now = DateTime.now();
    for (final session in app.sessions) {
      final started = parseUtc(session['started_at']);
      String key = '更早';
      if (started != null) {
        final local = started.toLocal();
        final day = DateTime(local.year, local.month, local.day);
        final today = DateTime(now.year, now.month, now.day);
        final diff = today.difference(day).inDays;
        if (diff == 0) {
          key = '今天';
        } else if (diff == 1) {
          key = '昨天';
        } else if (diff < 7) {
          key = '本周';
        }
      }
      groups.putIfAbsent(key, () => []).add(session);
    }
    final order = ['今天', '昨天', '本周', '更早'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final key in order)
          if (groups[key] != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 10, left: 4),
              child: Text(
                key,
                style: context.texts.labelSmall?.copyWith(
                  color: context.colors.faint,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (var i = 0; i < groups[key]!.length; i++)
              StaggeredReveal(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SessionRow(app: app, session: groups[key]![i]),
                ),
              ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.app, required this.session});
  final AppState app;
  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final started = parseUtc(session['started_at']);
    final duration = (session['duration_seconds'] as num?)?.toInt() ?? 0;
    final engine = session['engine'] as String?;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SessionDetailScreen(
              app: app,
              session: session,
              onBrowseScenarios: () {},
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line.withValues(alpha: 0.65)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c.mint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.forum_outlined, size: 19, color: c.mintInk),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sessionTitle(session),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (started != null) formatSessionDate(started),
                        if (duration > 0) formatDuration(duration),
                        engineLabel(app.config, engine),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelSmall?.copyWith(color: c.faint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                duration > 0 ? formatShortDuration(duration) : '—',
                style: tabular(context.texts.labelSmall?.copyWith(color: c.secondary)),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18, color: c.faint),
            ],
          ),
        ),
      ),
    );
  }
}

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.app,
    required this.session,
    required this.onBrowseScenarios,
  });

  final AppState app;
  final Map<String, dynamic> session;
  final VoidCallback onBrowseScenarios;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  Map<String, dynamic>? _detail;
  String? _error;
  bool _loading = true;
  bool _opening = false;

  String get _id => (widget.session['id'] as String?) ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_id.isEmpty) {
      setState(() {
        _loading = false;
        _error = '这条记录缺少标识，无法载入。';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.app.session(_id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e);
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _turns {
    final turns = _detail?['turns'];
    if (turns is List) {
      return turns.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<void> _resume() async {
    if (_opening) return;
    final mode = await showModalBottomSheet<TalkMode>(
      context: context,
      builder: (context) {
        final c = context.colors;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('继续这段对话', style: context.texts.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  '服务端会恢复这段会话的文本历史，不会重放旧音频。',
                  style: context.texts.bodySmall,
                ),
                const SizedBox(height: 18),
                _ModeTile(
                  icon: Icons.mic_none_rounded,
                  title: '按住说话',
                  subtitle: '手动控制每一句的开头与提交',
                  onTap: () => Navigator.of(context).pop(TalkMode.ptt),
                ),
                const SizedBox(height: 8),
                _ModeTile(
                  icon: Icons.graphic_eq_rounded,
                  title: '自动静音',
                  subtitle: '能量阈值检测，约 0.95 秒静音后提交；非神经网络 VAD',
                  onTap: () => Navigator.of(context).pop(TalkMode.handsFree),
                ),
                const SizedBox(height: 12),
                Text(
                  '两种方式都使用半双工：对方播放时暂停麦克风。',
                  style: context.texts.labelSmall?.copyWith(color: c.faint),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (mode == null || !mounted) return;
    setState(() => _opening = true);
    final app = widget.app;
    final scenarioId = (_detail?['scenario_id'] ?? widget.session['scenario_id']) as String?;
    Map<String, dynamic>? scenario;
    if (scenarioId != null) {
      for (final item in app.scenarios) {
        if (item['id'] == scenarioId) {
          scenario = item;
          break;
        }
      }
    }
    final lines = _turns.map((turn) {
      return TalkLine(
        role: (turn['role'] as String?) ?? 'assistant',
        text: (turn['text'] as String?) ?? '',
        interrupted: turn['interrupted'] == true,
        createdAt: parseUtc(turn['created_at']),
      );
    }).toList();
    final goals = (_detail?['completed_goals'] as List? ?? [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toList();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionScreen(
          app: app,
          mode: mode,
          scenarioId: scenarioId,
          sessionId: _id,
          scenario: scenario,
          title: sessionTitle(_detail ?? widget.session),
          subtitle: scenario?['subtitle'] as String?,
          initialLines: lines,
          initialGoals: goals,
          engine: app.currentEngine,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _opening = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final session = _detail ?? widget.session;
    final started = parseUtc(session['started_at']);
    final ended = parseUtc(session['ended_at']);
    final duration = (session['duration_seconds'] as num?)?.toInt() ??
        (started != null && ended != null ? ended.difference(started).inSeconds : 0);
    final scenarioId = session['scenario_id'] as String?;
    Map<String, dynamic>? scenario;
    for (final item in widget.app.scenarios) {
      if (item['id'] == scenarioId) {
        scenario = item;
        break;
      }
    }
    final goals = (scenario?['goals'] as List? ?? []);
    final completed = (_detail?['completed_goals'] as List? ?? [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toSet();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 48),
          child: PageFrame(
            maxWidth: 940,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: '返回记录',
                    ),
                    const SizedBox(width: 2),
                    Text('记录详情', style: context.texts.labelMedium),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TagChip(
                                ended == null ? '未结束' : '已结束',
                                emphasis: ended == null,
                              ),
                              if (scenario?['level'] is String)
                                TagChip(scenario!['level'] as String),
                              TagChip(engineLabel(widget.app.config, session['engine'] as String?)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            sessionTitle(session),
                            style: context.texts.displaySmall?.copyWith(fontSize: 36),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            [
                              if (started != null) formatSessionDate(started),
                              if (duration > 0) formatDuration(duration),
                              '${_turns.length} 句',
                            ].join(' · '),
                            style: context.texts.bodySmall?.copyWith(color: c.secondary),
                          ),
                        ],
                      ),
                    ),
                    if (started != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: c.sunken,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Text(
                              formatShortDuration(duration),
                              style: tabular(context.texts.titleMedium?.copyWith(color: c.ink)),
                            ),
                            Text('时长', style: context.texts.labelSmall?.copyWith(color: c.faint)),
                          ],
                        ),
                      ),
                  ],
                ),
                if (scenario?['subtitle'] is String) ...[
                  const SizedBox(height: 12),
                  Text(
                    scenario!['subtitle'] as String,
                    style: context.texts.bodyMedium?.copyWith(color: c.secondary),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  ErrorBanner(message: _error!, onRetry: _load),
                ],
                if (goals.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  SectionHeading(
                    title: '完成的目标',
                    eyebrow: 'PROGRESS',
                    trailing: Text(
                      '${completed.length} / ${goals.length}',
                      style: tabular(context.texts.titleSmall?.copyWith(color: c.teal)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < goals.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            completed.contains(i)
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 19,
                            color: completed.contains(i) ? c.teal : c.faint,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              goals[i].toString(),
                              style: context.texts.bodyMedium?.copyWith(
                                color: completed.contains(i) ? c.ink : c.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 28),
                Row(
                  children: [
                    Text('对话原文', style: context.texts.titleMedium),
                    const Spacer(),
                    if (_loading)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: c.teal),
                      ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _opening || _id.isEmpty ? null : _resume,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('继续对话'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: c.line.withValues(alpha: 0.6)),
                  ),
                  child: _loading && _detail == null
                      ? const LoadingBlock(label: '正在读取对话…')
                      : _turns.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 26),
                              child: Center(
                                child: Text('这段会话还没有保存的对话内容。', style: context.texts.bodySmall),
                              ),
                            )
                          : Column(
                              children: [
                                for (var i = 0; i < _turns.length; i++)
                                  _DetailTurn(
                                    turn: _turns[i],
                                    aiRole: (scenario?['ai_role'] as String?) ?? '对话伙伴',
                                    isLast: i == _turns.length - 1,
                                  ),
                              ],
                            ),
                ),
                const SizedBox(height: 20),
                InfoBanner(
                  message: '继续对话会使用一次性票据恢复这段会话的文本历史；不会重放旧音频，也不会补发未提交的录音。',
                  icon: Icons.history_toggle_off_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailTurn extends StatelessWidget {
  const _DetailTurn({required this.turn, required this.aiRole, required this.isLast});
  final Map<String, dynamic> turn;
  final String aiRole;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final role = turn['role'] as String? ?? 'assistant';
    final text = turn['text'] as String? ?? '';
    final interrupted = turn['interrupted'] == true;
    final created = parseUtc(turn['created_at']);
    final user = role == 'user';
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
      child: Column(
        crossAxisAlignment: user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: user ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!user) ...[
                const LangoMark(size: 16),
                const SizedBox(width: 6),
              ],
              Text(
                user ? '你' : aiRole,
                style: context.texts.labelSmall?.copyWith(color: c.faint),
              ),
              if (created != null) ...[
                const SizedBox(width: 8),
                Text(
                  formatClock(created.toLocal()),
                  style: tabular(context.texts.labelSmall?.copyWith(fontSize: 10, color: c.faint)),
                ),
              ],
              if (user) ...[
                const SizedBox(width: 6),
                const LangoMark(size: 16),
              ],
            ],
          ),
          const SizedBox(height: 5),
          if (user)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.mint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                text,
                style: context.texts.bodyMedium?.copyWith(color: c.mintInk, height: 1.55),
              ),
            )
          else
            Text(
              text,
              style: context.texts.bodyMedium?.copyWith(height: 1.65),
            ),
          if (interrupted) ...[
            const SizedBox(height: 4),
            Text(
              '已打断 · 仅保留已播放的内容',
              style: context.texts.labelSmall?.copyWith(
                color: c.faint,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.sunken,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 21, color: c.teal),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.texts.titleSmall),
                    const SizedBox(height: 2),
                    Text(subtitle, style: context.texts.bodySmall?.copyWith(fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: c.faint),
            ],
          ),
        ),
      ),
    );
  }
}
