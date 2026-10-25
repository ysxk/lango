import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../ui/components.dart';
import '../ui/format.dart';
import '../ui/scenario_card.dart';
import '../ui/theme.dart';
import 'admin_invite_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onNavigate, required this.onOpenSettings});
  final ValueChanged<int> onNavigate;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final now = DateTime.now();
    final recent = app.sessions.take(3).toList();
    final featured = app.scenarios.take(3).toList();
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
              const SizedBox(height: 32),
              _TopGreeting(
                greeting: greetingFor(now),
                name: app.displayName,
                date: todayLabel(now),
                loading: app.loading,
                onRefresh: app.loading ? null : app.load,
                onOpenSettings: onOpenSettings,
              ),
              if (app.error != null) ...[
                const SizedBox(height: 18),
                ErrorBanner(message: app.error!, onRetry: app.load),
              ],
              const SizedBox(height: 24),
              StaggeredReveal(
                index: 0,
                child: _Hero(
                  todaySeconds: app.todaySeconds,
                  limitSeconds: app.dailyLimitSeconds,
                  recent: recent.isEmpty ? null : recent.first,
                  onStart: app.scenarios.isEmpty ? null : () => onNavigate(1),
                  onContinue: recent.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SessionDetailScreen(
                                app: app,
                                session: recent.first,
                                onBrowseScenarios: () => onNavigate(1),
                              ),
                            ),
                          ),
                ),
              ),
              const SizedBox(height: 22),
              StaggeredReveal(index: 1, child: _Metrics(app: app)),
              const SizedBox(height: 38),
              StaggeredReveal(
                index: 2,
                child: SectionHeading(
                  eyebrow: 'CONTINUE',
                  title: '继续上次',
                  subtitle: recent.isEmpty ? '还没有对话记录。第一次开口，会从这里开始。' : '从真实保存的对话继续。',
                  trailing: recent.isEmpty
                      ? null
                      : TextButton(
                          onPressed: () => onNavigate(2),
                          child: const Text('全部记录'),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              StaggeredReveal(
                index: 3,
                child: recent.isEmpty
                    ? SurfacePanel(
                        padding: EdgeInsets.zero,
                        child: EmptyState(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: '还没有练习记录',
                          message: '选一个场景，开口说第一句。结束后，对话会真实地出现在这里。',
                          action: app.scenarios.isEmpty
                              ? null
                              : LangoButton(
                                  label: '挑选场景',
                                  icon: Icons.arrow_forward_rounded,
                                  variant: LangoButtonVariant.outline,
                                  onPressed: () => onNavigate(1),
                                ),
                        ),
                      )
                    : SurfacePanel(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Column(
                          children: [
                            for (var i = 0; i < recent.length; i++) ...[
                              _RecentSessionRow(
                                session: recent[i],
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SessionDetailScreen(
                                      app: app,
                                      session: recent[i],
                                      onBrowseScenarios: () => onNavigate(1),
                                    ),
                                  ),
                                ),
                              ),
                              if (i != recent.length - 1)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Container(height: 1, color: c.line.withValues(alpha: 0.5)),
                                ),
                            ],
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 38),
              StaggeredReveal(
                index: 4,
                child: SectionHeading(
                  eyebrow: 'SCENARIOS',
                  title: '今天想练什么？',
                  subtitle: '来自服务端的 12 个生活与工作场景。',
                  trailing: app.scenarios.isEmpty
                      ? null
                      : TextButton(
                          onPressed: () => onNavigate(1),
                          child: const Text('查看全部'),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              if (app.scenarios.isEmpty)
                SurfacePanel(
                  padding: EdgeInsets.zero,
                  child: EmptyState(
                    title: app.loading ? '正在载入场景…' : '场景暂未载入',
                    message: app.loading ? '正在从你的服务端获取场景。' : '请检查服务是否正常，然后刷新。',
                    icon: Icons.landscape_outlined,
                    action: app.loading
                        ? null
                        : LangoButton(
                            label: '刷新',
                            icon: Icons.refresh_rounded,
                            variant: LangoButtonVariant.outline,
                            onPressed: app.load,
                          ),
                  ),
                )
              else
                _ScenarioPreview(
                  scenarios: featured,
                  onAll: () => onNavigate(1),
                  onOpen: (scenario) {
                    onNavigate(1);
                  },
                ),
              const SizedBox(height: 34),
              StaggeredReveal(
                index: 5,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _MemoryShortcut(
                        count: app.memoryCount,
                        enabled: app.memoryEnabled,
                        onTap: () => onNavigate(3),
                      ),
                    ),
                    if (app.isAdmin) ...[
                      const SizedBox(width: 14),
                      Expanded(
                        child: SurfacePanel(
                          padding: const EdgeInsets.all(20),
                          border: true,
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: c.warm,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.vpn_key_outlined, size: 19, color: c.ink),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('管理员', style: context.texts.titleSmall),
                                    const SizedBox(height: 2),
                                    Text('生成邀请码', style: context.texts.bodySmall),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const AdminInviteScreen()),
                                ),
                                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                                tooltip: '生成邀请码',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopGreeting extends StatelessWidget {
  const _TopGreeting({
    required this.greeting,
    required this.name,
    required this.date,
    required this.loading,
    required this.onRefresh,
    required this.onOpenSettings,
  });

  final String greeting;
  final String name;
  final String date;
  final bool loading;
  final VoidCallback? onRefresh;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                date,
                style: context.texts.labelSmall?.copyWith(
                  color: c.teal,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$greeting，$name',
                style: context.texts.headlineMedium?.copyWith(fontSize: 28),
              ),
            ],
          ),
        ),
        if (loading)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.teal),
            ),
          ),
        IconButton(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 20),
          tooltip: '刷新',
        ),
        IconButton(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.tune_rounded, size: 20),
          tooltip: '设置',
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.todaySeconds,
    required this.limitSeconds,
    required this.recent,
    required this.onStart,
    required this.onContinue,
  });

  final int todaySeconds;
  final int limitSeconds;
  final Map<String, dynamic>? recent;
  final VoidCallback? onStart;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: c.teal, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              'TODAY\'S PRACTICE',
              style: context.texts.labelSmall?.copyWith(
                color: c.teal,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            '把今天，\n用英语说出来。',
            style: context.texts.displaySmall?.copyWith(fontSize: 40, height: 1.12),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          todaySeconds > 0
              ? '今天已经开口 ${formatDuration(todaySeconds)}。保持这个节奏，比一次练很久更重要。'
              : '从一句真实的对话开始。不需要准备，选一个场景就够了。',
          style: context.texts.bodyMedium?.copyWith(color: c.secondary, height: 1.7),
        ),
        const SizedBox(height: 26),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            LangoButton(
              label: '挑选一个场景',
              icon: Icons.arrow_forward_rounded,
              onPressed: onStart,
              compact: true,
            ),
            if (recent != null)
              LangoButton(
                label: '继续「${sessionTitle(recent!)}」',
                icon: Icons.history_rounded,
                variant: LangoButtonVariant.outline,
                onPressed: onContinue,
                compact: true,
              ),
          ],
        ),
      ],
    );
    return SurfacePanel(
      padding: EdgeInsets.all(wide ? 32 : 24),
      radius: 28,
      border: true,
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: text),
                const SizedBox(width: 32),
                _UsageRing(todaySeconds: todaySeconds, limitSeconds: limitSeconds),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: 24),
                Center(
                  child: _UsageRing(todaySeconds: todaySeconds, limitSeconds: limitSeconds),
                ),
              ],
            ),
    );
  }
}

class _UsageRing extends StatelessWidget {
  const _UsageRing({required this.todaySeconds, required this.limitSeconds});
  final int todaySeconds;
  final int limitSeconds;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final progress = limitSeconds <= 0 ? 0.0 : (todaySeconds / limitSeconds).clamp(0.0, 1.0);
    final minutes = todaySeconds ~/ 60;
    final value = minutes == 0 && todaySeconds > 0 ? '<1' : '$minutes';
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: context.motion(700),
      curve: Curves.easeOutCubic,
      builder: (context, animated, child) {
        return SizedBox(
          width: 168,
          height: 168,
          child: CustomPaint(
            painter: _RingPainter(progress: animated, track: c.line, accent: c.teal),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        value,
                        style: tabular(context.texts.displayMedium?.copyWith(fontSize: 38)),
                      ),
                      const SizedBox(width: 3),
                      Text('分', style: context.texts.labelSmall?.copyWith(color: c.secondary)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    limitSeconds > 0 ? '今日 / 上限 ${(limitSeconds / 60).round()} 分' : '今日练习',
                    style: context.texts.labelSmall?.copyWith(fontSize: 10.5, color: c.faint),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.track, required this.accent});
  final double progress;
  final Color track;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = track,
    );
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = accent,
      );
    }
    canvas.drawCircle(
      center,
      radius - 16,
      Paint()..color = accent.withValues(alpha: 0.045),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.track != track || old.accent != accent;
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.app});
  final dynamic app;

  @override
  Widget build(BuildContext context) {
    final todayMinutes = app.todaySeconds ~/ 60;
    final metrics = [
      MetricCard(
        label: '今日开口',
        value: todayMinutes == 0 && app.todaySeconds > 0 ? '<1' : '$todayMinutes',
        unit: '分钟',
        hint: app.todaySeconds == 0 ? '还没有开始' : formatDuration(app.todaySeconds),
        icon: Icons.mic_none_rounded,
      ),
      MetricCard(
        label: '最近记录',
        value: '${app.sessions.length}',
        unit: '条',
        hint: '来自 /sessions',
        icon: Icons.history_rounded,
      ),
      MetricCard(
        label: '记忆',
        value: '${app.memoryCount}',
        unit: '条',
        hint: app.memoryEnabled ? '记忆已开启' : '记忆已关闭',
        icon: Icons.auto_awesome_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 3 : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final metric in metrics) SizedBox(width: width, child: metric),
          ],
        );
      },
    );
  }
}

class _RecentSessionRow extends StatelessWidget {
  const _RecentSessionRow({required this.session, required this.onTap});
  final Map<String, dynamic> session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final started = parseUtc(session['started_at']);
    final duration = (session['duration_seconds'] as num?)?.toInt() ?? 0;
    final engine = session['engine'] as String?;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.mint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.forum_outlined, size: 18, color: c.mintInk),
              ),
              const SizedBox(width: 13),
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
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (started != null) formatSessionDate(started),
                        if (duration > 0) formatDuration(duration),
                        ?engine,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelSmall?.copyWith(color: c.faint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 18, color: c.faint),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScenarioPreview extends StatelessWidget {
  const _ScenarioPreview({
    required this.scenarios,
    required this.onAll,
    required this.onOpen,
  });
  final List<Map<String, dynamic>> scenarios;
  final VoidCallback onAll;
  final ValueChanged<Map<String, dynamic>> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 3 : constraints.maxWidth >= 640 ? 2 : 1;
        const gap = 14.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < scenarios.length; i++)
                  SizedBox(
                    width: width,
                    child: StaggeredReveal(
                      index: i,
                      child: ScenarioCard(
                        scenario: scenarios[i],
                        onTap: () {
                          onAll();
                        },
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '打开「场景」标签，查看完整角色、目标与开场。',
              style: context.texts.labelSmall?.copyWith(color: context.colors.faint),
            ),
          ],
        );
      },
    );
  }
}

class _MemoryShortcut extends StatelessWidget {
  const _MemoryShortcut({required this.count, required this.enabled, required this.onTap});
  final int count;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.line.withValues(alpha: 0.7)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.mint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.auto_awesome_outlined, size: 19, color: c.mintInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('记忆 · $count 条', style: context.texts.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      enabled ? '可逐条删除或全部遗忘' : '记忆已关闭，不会新增',
                      style: context.texts.bodySmall,
                    ),
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
