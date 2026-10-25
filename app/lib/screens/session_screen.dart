import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import '../talk/talk_controller.dart';
import '../ui/components.dart';
import '../ui/format.dart';
import '../ui/orb.dart';
import '../ui/theme.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.app,
    required this.mode,
    required this.title,
    this.subtitle,
    this.scenarioId,
    this.sessionId,
    this.scenario,
    this.initialLines = const [],
    this.initialGoals = const [],
    this.engine,
  });

  final AppState app;
  final TalkMode mode;
  final String title;
  final String? subtitle;
  final String? scenarioId;
  final String? sessionId;
  final Map<String, dynamic>? scenario;
  final List<TalkLine> initialLines;
  final List<int> initialGoals;
  final String? engine;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> with WidgetsBindingObserver {
  late final TalkController _talk;
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  final _scroll = ScrollController();
  Timer? _clock;
  bool _sending = false;
  bool _ending = false;
  bool _reloaded = false;
  bool _scrolledOnce = false;
  String _signature = '';
  int get _elapsed => _talk.startedAt == null
      ? 0
      : DateTime.now().difference(_talk.startedAt!).inSeconds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _talk = TalkController(
      api: widget.app.api,
      config: TalkControllerConfig(
        mode: widget.mode,
        scenarioId: widget.scenarioId,
        sessionId: widget.sessionId,
        engine: widget.engine,
        initialLines: widget.initialLines,
        initialGoals: widget.initialGoals,
        lessonTitle: widget.title,
      ),
    )..addListener(_onTalk);
    _talk.start();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_scrolledOnce) {
      _scrolledOnce = true;
      _scheduleScroll();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_talk.suspend());
    } else if (state == AppLifecycleState.resumed) {
      _talk.resumeFromBackground();
    }
  }

  void _onTalk() {
    if (!mounted) return;
    final signature =
        '${_talk.lines.length}:${_talk.lines.isEmpty ? 0 : _talk.lines.last.text.length}:${_talk.phase.name}';
    if (signature != _signature) {
      _signature = signature;
      _scheduleScroll();
    }
    if (_talk.phase == TalkPhase.ended && !_reloaded) {
      _reloaded = true;
      unawaited(widget.app.reloadAfterSession());
    }
    setState(() {});
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _sendText() async {
    if (_sending) return;
    final value = _composer.text.trim();
    if (value.isEmpty) return;
    setState(() => _sending = true);
    final ok = await _talk.sendText(value);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _composer.clear();
      _composerFocus.requestFocus();
    }
  }

  Future<void> _requestClose() async {
    if (_ending) return;
    if (_talk.phase == TalkPhase.ended) {
      Navigator.of(context).pop();
      return;
    }
    final confirmed = await confirmAction(
      context,
      title: '结束这次对话？',
      message: '对话会保存到记录中。只有开启记忆时的自由对话会参与记忆整理；角色扮演不会提取为个人经历。',
      confirmLabel: '结束对话',
      destructive: false,
    );
    if (!confirmed || !mounted) return;
    setState(() => _ending = true);
    await _talk.end();
    if (!mounted) return;
    setState(() => _ending = false);
    Navigator.of(context).pop();
  }

  void _showGoals() {
    final goals = (widget.scenario?['goals'] as List? ?? []);
    final completed = _talk.completedGoals;
    final phrases = (widget.scenario?['useful_phrases'] as List? ?? []);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final c = context.colors;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('本轮目标', style: context.texts.headlineSmall),
                  const SizedBox(height: 6),
                  Text(
                    '完成进度来自服务端的事件，不根据猜测勾选。',
                    style: context.texts.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  if (goals.isEmpty)
                    Text('这个场景没有目标列表。', style: context.texts.bodySmall)
                  else
                    for (var i = 0; i < goals.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              completed.contains(i)
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 20,
                              color: completed.contains(i) ? c.teal : c.faint,
                            ),
                            const SizedBox(width: 12),
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
                  if (phrases.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('可用表达', style: context.texts.titleSmall),
                    const SizedBox(height: 10),
                    for (final phrase in phrases)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '· ${phrase.toString()}',
                          style: context.texts.bodySmall?.copyWith(color: c.ink),
                        ),
                      ),
                  ],
                  const SizedBox(height: 22),
                  InfoBanner(
                    icon: Icons.visibility_outlined,
                    message: _talk.mode == TalkMode.handsFree
                        ? '自动静音由麦克风能量阈值检测触发，不是神经网络 VAD。对方播放时麦克风会暂停。'
                        : '按住说话时才会录音；对方播放时麦克风暂停（半双工）。',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _talk.removeListener(_onTalk);
    _talk.dispose();
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final c = context.colors;
    final elapsed = _talk.startedAt == null
        ? 0
        : DateTime.now().difference(_talk.startedAt!).inSeconds;
    return PopScope(
      canPop: _talk.phase == TalkPhase.ended,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _Header(
                    title: widget.title,
                    subtitle: widget.subtitle,
                    phase: _talk.phase,
                    elapsed: elapsed,
                    onBack: _requestClose,
                    onGoals: _showGoals,
                    onEnd: _requestClose,
                    ended: _talk.phase == TalkPhase.ended,
                  ),
                  Expanded(
                    child: wide
                        ? _buildWide(context)
                        : _buildNarrow(context),
                  ),
                ],
              ),
              if (_ending)
                Positioned.fill(
                  child: ColoredBox(
                    color: c.canvas.withValues(alpha: 0.72),
                    child: Center(
                      child: SurfacePanel(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: c.teal),
                            ),
                            const SizedBox(width: 14),
                            Text('正在结束对话…', style: context.texts.bodyMedium),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 372,
            child: _ControlPanel(
              talk: _talk,
              scenario: widget.scenario,
              elapsed: _elapsed,
              onGoals: _showGoals,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _TranscriptPanel(
                    talk: _talk,
                    scroll: _scroll,
                    scenario: widget.scenario,
                    onRetry: _talk.reconnect,
                    onClearError: _talk.clearError,
                    onRetryMic: _talk.retryMicrophone,
                  ),
                ),
                const SizedBox(height: 12),
                _Composer(
                  controller: _composer,
                  focusNode: _composerFocus,
                  enabled: _talk.canAcceptInput && _talk.phase != TalkPhase.ended,
                  sending: _sending,
                  onSend: _sendText,
                  onChanged: () => setState(() {}),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrow(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _TranscriptPanel(
            talk: _talk,
            scroll: _scroll,
            scenario: widget.scenario,
            onRetry: _talk.reconnect,
            onClearError: _talk.clearError,
            onRetryMic: _talk.retryMicrophone,
            compact: true,
          ),
        ),
        _MobileDock(
          talk: _talk,
          elapsed: _elapsed,
          composer: _composer,
          focusNode: _composerFocus,
          sending: _sending,
          canSend: _talk.canAcceptInput && _talk.phase != TalkPhase.ended,
          onSend: _sendText,
          onChanged: () => setState(() {}),
          onGoals: _showGoals,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.phase,
    required this.elapsed,
    required this.onBack,
    required this.onGoals,
    required this.onEnd,
    required this.ended,
  });

  final String title;
  final String? subtitle;
  final TalkPhase phase;
  final int elapsed;
  final VoidCallback onBack;
  final VoidCallback onGoals;
  final VoidCallback onEnd;
  final bool ended;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final (label, color) = _phaseMeta(phase, c);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line.withValues(alpha: 0.55))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            tooltip: '结束并返回',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleMedium,
                ),
                if (wide && subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(fontSize: 12),
                  ),
              ],
            ),
          ),
          if (wide) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.sunken,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(color: color, pulse: phase == TalkPhase.speaking || phase == TalkPhase.listening),
                  const SizedBox(width: 7),
                  Text(label, style: context.texts.labelSmall?.copyWith(color: c.secondary)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatShortDuration(elapsed),
              style: tabular(context.texts.labelSmall?.copyWith(color: c.faint)),
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            onPressed: onGoals,
            icon: const Icon(Icons.flag_outlined, size: 20),
            tooltip: '本轮目标',
          ),
          if (ended)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text('已结束', style: context.texts.labelSmall?.copyWith(color: c.faint)),
            )
          else
            TextButton(
              onPressed: onEnd,
              child: const Text('结束'),
            ),
        ],
      ),
    );
  }
}

(String, Color) _phaseMeta(TalkPhase phase, LangoColors c) {
  switch (phase) {
    case TalkPhase.idle:
      return ('准备中', c.faint);
    case TalkPhase.connecting:
      return ('连接中', c.faint);
    case TalkPhase.listening:
      return ('在听你说', c.teal);
    case TalkPhase.thinking:
      return ('正在思考', c.warm);
    case TalkPhase.speaking:
      return ('正在回应', c.teal);
    case TalkPhase.paused:
      return ('已暂停', c.faint);
    case TalkPhase.disconnected:
      return ('连接断开', c.danger);
    case TalkPhase.ended:
      return ('对话结束', c.faint);
    case TalkPhase.failed:
      return ('连接失败', c.danger);
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.talk,
    required this.scenario,
    required this.elapsed,
    required this.onGoals,
  });

  final TalkController talk;
  final Map<String, dynamic>? scenario;
  final int elapsed;
  final VoidCallback onGoals;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final goals = (scenario?['goals'] as List? ?? []).length;
    return SurfacePanel(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
      radius: 26,
      border: true,
      child: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(
              height: 230,
              child: Center(
                child: TalkOrb(
                  phase: talk.phase,
                  level: talk.micLevel,
                  reducedMotion: context.reduceMotion,
                  size: 228,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _PhaseText(talk: talk, elapsed: elapsed),
            const SizedBox(height: 18),
            _MicMeter(talk: talk),
            const SizedBox(height: 22),
            _TalkControls(talk: talk, compact: false),
            if (talk.micError != null) ...[
              const SizedBox(height: 16),
              ErrorBanner(
                message: talk.micError!,
                onRetry: talk.micUnsupported ? null : talk.retryMicrophone,
              ),
            ],
            const SizedBox(height: 22),
            Container(height: 1, color: c.line.withValues(alpha: 0.55)),
            const SizedBox(height: 16),
            InkWell(
              onTap: onGoals,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined, size: 17, color: c.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        goals == 0 ? '本轮没有设定目标' : '目标 ${talk.completedGoals.length} / $goals',
                        style: context.texts.bodySmall?.copyWith(color: c.ink),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 18, color: c.faint),
                  ],
                ),
              ),
            ),
            if (goals > 0) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (talk.completedGoals.length / goals).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: c.line,
                  color: c.teal,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              talk.mode == TalkMode.handsFree
                  ? '自动静音 · 能量阈值检测（非神经网络 VAD）· 约 0.95 秒静音后提交'
                  : '按住说话 · 松开后提交 · 最长 60 秒',
              textAlign: TextAlign.center,
              style: context.texts.labelSmall?.copyWith(fontSize: 10.5, height: 1.5, color: c.faint),
            ),
            const SizedBox(height: 4),
            Text(
              '半双工 · 对方播放时暂停麦克风',
              textAlign: TextAlign.center,
              style: context.texts.labelSmall?.copyWith(fontSize: 10.5, color: c.faint),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseText extends StatelessWidget {
  const _PhaseText({required this.talk, required this.elapsed});
  final TalkController talk;
  final int elapsed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, color) = _phaseMeta(talk.phase, c);
    String subtitle = switch (talk.phase) {
      TalkPhase.connecting => '正在获取一次性票据并建立连接',
      TalkPhase.listening => talk.isRecording ? '正在采集 16 kHz 单声道 PCM' : '等待你开口',
      TalkPhase.thinking => '对方正在组织回应',
      TalkPhase.speaking => '音频按顺序播放，播完才确认',
      TalkPhase.paused => '应用切到后台，麦克风与播放已停止',
      TalkPhase.disconnected => '会话仍在，可重新连接继续',
      TalkPhase.failed => '失败原因见下方提示',
      TalkPhase.ended => '本次对话已保存',
      TalkPhase.idle => '准备开始',
    };
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StatusDot(color: color, pulse: talk.phase == TalkPhase.speaking),
            const SizedBox(width: 8),
            Text(
              label,
              style: context.texts.titleSmall?.copyWith(color: c.ink, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 10),
            Text(
              formatShortDuration(elapsed),
              style: tabular(context.texts.labelSmall?.copyWith(color: c.faint)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: context.texts.bodySmall?.copyWith(fontSize: 12, color: c.secondary),
        ),
      ],
    );
  }
}

class _MicMeter extends StatelessWidget {
  const _MicMeter({required this.talk});
  final TalkController talk;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = talk.isRecording;
    return Column(
      children: [
        Row(
          children: [
            Icon(
              active ? Icons.mic_rounded : Icons.mic_none_rounded,
              size: 15,
              color: active ? c.teal : c.faint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  height: 4,
                  color: c.sunken,
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    duration: context.motion(110),
                    curve: Curves.easeOut,
                    widthFactor: (talk.micLevel * 1.6).clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: Container(color: c.teal),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              active ? '录音中' : '麦克风待机',
              style: context.texts.labelSmall?.copyWith(color: active ? c.teal : c.faint),
            ),
          ],
        ),
      ],
    );
  }
}

class _TalkControls extends StatelessWidget {
  const _TalkControls({required this.talk, required this.compact});
  final TalkController talk;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final needsReconnect = talk.phase == TalkPhase.disconnected || talk.phase == TalkPhase.failed;
    final busy = talk.phase == TalkPhase.thinking || talk.phase == TalkPhase.speaking;
    if (talk.phase == TalkPhase.ended) {
      return Column(
        children: [
          InfoBanner(message: '对话已结束并保存。可以在「记录」中回看或继续。'),
          const SizedBox(height: 12),
          LangoButton(
            label: '返回',
            icon: Icons.arrow_back_rounded,
            expand: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      );
    }
    if (needsReconnect) {
      return Column(
        children: [
          LangoButton(
            label: '重新连接同一会话',
            icon: Icons.refresh_rounded,
            expand: true,
            onPressed: talk.reconnect,
          ),
          const SizedBox(height: 8),
          Text(
            '会获取新的票据并恢复已保存对话；未提交的录音不会重发。',
            textAlign: TextAlign.center,
            style: context.texts.labelSmall?.copyWith(fontSize: 10.5, color: c.faint),
          ),
        ],
      );
    }
    final children = <Widget>[];
    if (talk.mode == TalkMode.ptt) {
      children.add(
        _PttButton(
          enabled: talk.isRecording || talk.canStartCapture,
          recording: talk.isRecording,
          waiting: busy,
          level: talk.micLevel,
          onStart: () => talk.beginPtt(),
          onEnd: () => talk.endPtt(),
        ),
      );
    } else {
      final canStart = talk.canStartCapture;
      final denied = talk.micPermissionDenied || talk.micUnsupported;
      final label = talk.isRecording
          ? '暂停聆听'
          : denied
              ? (talk.micUnsupported ? '当前设备不支持录音' : '重试麦克风')
              : busy
                  ? '对方回应中'
                  : canStart
                      ? '开始聆听'
                      : '等待连接';
      children.add(
        LangoButton(
          label: label,
          icon: talk.isRecording
              ? Icons.pause_rounded
              : denied
                  ? Icons.refresh_rounded
                  : Icons.graphic_eq_rounded,
          variant: talk.isRecording ? LangoButtonVariant.tonal : LangoButtonVariant.filled,
          expand: true,
          onPressed: talk.isRecording || (denied && !talk.micUnsupported) || canStart
              ? () {
                  if (talk.isRecording) {
                    talk.toggleAutoListening();
                  } else if (denied && !talk.micUnsupported) {
                    talk.retryMicrophone();
                  } else {
                    talk.toggleAutoListening();
                  }
                }
              : null,
        ),
      );
    }
    if (talk.canInterrupt) {
      children.add(const SizedBox(height: 8));
      children.add(
        LangoButton(
          label: '打断回应',
          icon: Icons.stop_rounded,
          variant: LangoButtonVariant.outline,
          expand: true,
          onPressed: talk.interrupt,
        ),
      );
    }
    if (talk.phase == TalkPhase.connecting) {
      children.insert(
        0,
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: LoadingBlock(label: '正在建立安全连接…', compact: true),
        ),
      );
    }
    return Column(children: children);
  }
}

class _PttButton extends StatefulWidget {
  const _PttButton({
    required this.enabled,
    required this.recording,
    required this.waiting,
    required this.level,
    required this.onStart,
    required this.onEnd,
  });

  final bool enabled;
  final bool recording;
  final bool waiting;
  final double level;
  final Future<bool> Function() onStart;
  final Future<void> Function() onEnd;

  @override
  State<_PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<_PttButton> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;
  bool _spaceHeld = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!widget.enabled || widget.recording || _starting) return;
    _starting = true;
    try {
      await widget.onStart();
    } finally {
      _starting = false;
    }
  }

  Future<void> _end() async {
    if (!widget.recording) return;
    await widget.onEnd();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.space) return KeyEventResult.ignored;
    if (event is KeyDownEvent && !_spaceHeld) {
      _spaceHeld = true;
      unawaited(_start());
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent && _spaceHeld) {
      _spaceHeld = false;
      unawaited(_end());
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.enabled || widget.recording;
    final color = widget.recording ? c.teal : (enabled ? c.ink : c.sunken);
    final foreground = widget.recording ? c.onTeal : (enabled ? c.canvas : c.faint);
    final label = widget.recording
        ? '松开，提交这一句'
        : widget.waiting
            ? '等待对方回应'
            : widget.enabled
                ? '按住说话'
                : '尚未就绪';
    return Column(
      children: [
        Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: Semantics(
            button: true,
            enabled: enabled,
            label: label,
            child: MouseRegion(
              cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
              child: Listener(
                onPointerDown: enabled && !widget.recording ? (_) => _start() : null,
                onPointerUp: widget.recording ? (_) => _end() : null,
                onPointerCancel: widget.recording ? (_) => _end() : null,
                child: AnimatedContainer(
                  duration: context.motion(160),
                  curve: Curves.easeOutCubic,
                  height: 62,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      if (widget.recording)
                        BoxShadow(
                          color: c.teal.withValues(alpha: 0.16 + widget.level.clamp(0, 1) * 0.20),
                          blurRadius: 0,
                          spreadRadius: 4 + widget.level.clamp(0, 1) * 7,
                        ),
                      if (_focused)
                        BoxShadow(
                          color: c.teal.withValues(alpha: 0.26),
                          blurRadius: 0,
                          spreadRadius: 4,
                        ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.recording ? Icons.mic_rounded : Icons.mic_none_rounded,
                        size: 20,
                        color: foreground,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        label,
                        style: context.texts.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: context.motion(160),
          child: Text(
            widget.recording ? '松手即提交 · 说到一半可先松开取消' : '也可以使用下方文字输入',
            key: ValueKey(widget.recording),
            style: context.texts.labelSmall?.copyWith(fontSize: 10.5, color: c.faint),
          ),
        ),
      ],
    );
  }
}

class _TranscriptPanel extends StatelessWidget {
  const _TranscriptPanel({
    required this.talk,
    required this.scroll,
    required this.scenario,
    required this.onRetry,
    required this.onClearError,
    required this.onRetryMic,
    this.compact = false,
  });

  final TalkController talk;
  final ScrollController scroll;
  final Map<String, dynamic>? scenario;
  final VoidCallback onRetry;
  final VoidCallback onClearError;
  final VoidCallback onRetryMic;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lines = talk.lines;
    final aiRole = (scenario?['ai_role'] as String?) ?? '对话伙伴';
    final canReconnect = talk.phase == TalkPhase.disconnected || talk.phase == TalkPhase.failed;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.line.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 16 : 22, 14, compact ? 12 : 18, 12),
            child: Row(
              children: [
                Text('对话', style: context.texts.titleSmall),
                const SizedBox(width: 8),
                if (lines.isNotEmpty)
                  Text(
                    '${lines.length} 句',
                    style: tabular(context.texts.labelSmall?.copyWith(color: c.faint)),
                  ),
                const Spacer(),
                if (talk.phase == TalkPhase.connecting)
                  Text('连接中…', style: context.texts.labelSmall?.copyWith(color: c.faint)),
                if (talk.phase == TalkPhase.speaking)
                  Row(
                    children: [
                      StatusDot(color: c.teal, pulse: true),
                      const SizedBox(width: 6),
                      Text('播放中', style: context.texts.labelSmall?.copyWith(color: c.teal)),
                    ],
                  ),
              ],
            ),
          ),
          Container(height: 1, color: c.line.withValues(alpha: 0.45)),
          if (talk.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: ErrorBanner(
                message: talk.error!,
                onDismiss: onClearError,
                onRetry: canReconnect ? onRetry : null,
              ),
            ),
          if (talk.micError != null && compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: ErrorBanner(
                message: talk.micError!,
                onRetry: talk.micUnsupported ? null : onRetryMic,
              ),
            ),
          Expanded(
            child: lines.isEmpty
                ? _EmptyTranscript(talk: talk, compact: compact)
                : ListView.builder(
                    controller: scroll,
                    padding: EdgeInsets.fromLTRB(compact ? 14 : 22, 18, compact ? 14 : 22, 24),
                    itemCount: lines.length,
                    itemBuilder: (context, index) {
                      final line = lines[index];
                      return _Turn(
                        line: line,
                        aiRole: aiRole,
                        isLast: index == lines.length - 1,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTranscript extends StatelessWidget {
  const _EmptyTranscript({required this.talk, required this.compact});
  final TalkController talk;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final connecting = talk.phase == TalkPhase.connecting ||
        talk.phase == TalkPhase.idle;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              connecting ? Icons.wifi_tethering_rounded : Icons.forum_outlined,
              size: 26,
              color: c.teal,
            ),
            const SizedBox(height: 14),
            Text(
              connecting ? '正在建立对话…' : '对话会显示在这里',
              style: context.texts.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              connecting
                  ? '正在获取一次性凭证，不会把令牌放进网址。'
                  : '开口或打字，对方会先向你打招呼。',
              textAlign: TextAlign.center,
              style: context.texts.bodySmall?.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Turn extends StatelessWidget {
  const _Turn({required this.line, required this.aiRole, required this.isLast});
  final TalkLine line;
  final String aiRole;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (line.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 6),
              child: Text('你', style: context.texts.labelSmall?.copyWith(color: c.faint)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: c.mint,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(6),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                child: Text(
                  line.text,
                  style: context.texts.bodyLarge?.copyWith(
                    fontSize: 15,
                    height: 1.55,
                    color: c.mintInk,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LangoMark(size: 18),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  aiRole,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelSmall?.copyWith(color: c.faint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (line.text.isEmpty && line.streaming)
            _ThinkingDots(color: c.teal)
          else
            _InkBloomText(
              text: line.text,
              streaming: line.streaming,
              isLast: isLast,
            ),
          if (line.interrupted) ...[
            const SizedBox(height: 6),
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

class _InkBloomText extends StatefulWidget {
  const _InkBloomText({required this.text, required this.streaming, required this.isLast});
  final String text;
  final bool streaming;
  final bool isLast;

  @override
  State<_InkBloomText> createState() => _InkBloomTextState();
}

class _InkBloomTextState extends State<_InkBloomText> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _controller.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = context.reduceMotion;
  }

  @override
  void didUpdateWidget(covariant _InkBloomText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text && widget.streaming && !_reduced) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      style: context.texts.bodyLarge?.copyWith(fontSize: 16, height: 1.7),
    );
    if (!widget.streaming || _reduced) return text;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(_controller.value);
        return ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: (1 - v) * 2.2, sigmaY: (1 - v) * 2.2),
          child: Opacity(opacity: 0.72 + v * 0.28, child: child),
        );
      },
      child: text,
    );
  }
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots({required this.color});
  final Color color;

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) {
      return Row(
        children: List.generate(
          3,
          (i) => Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Container(width: 5, height: 5, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          children: List.generate(3, (i) {
            final phase = (_controller.value - i * 0.16) % 1.0;
            final opacity = 0.25 + 0.75 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
            return Padding(
              padding: const EdgeInsets.only(right: 5, top: 6),
              child: Opacity(
                opacity: opacity.clamp(0.2, 1.0),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.sending,
    required this.onSend,
    required this.onChanged,
    this.compact = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onChanged;
  final bool compact;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant _Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_focusChanged);
      widget.focusNode.addListener(_focusChanged);
    }
  }

  void _focusChanged() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_focusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canSend = widget.enabled && !widget.sending && widget.controller.text.trim().isNotEmpty;
    return AnimatedContainer(
      duration: context.motion(180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(widget.compact ? 12 : 14, 8, 8, 8),
      decoration: BoxDecoration(
        color: _focused ? c.surface : c.raised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _focused ? c.teal.withValues(alpha: 0.3) : c.line.withValues(alpha: 0.75),
        ),
        boxShadow: _focused
            ? [
                BoxShadow(color: c.teal.withValues(alpha: 0.22), blurRadius: 0, spreadRadius: 3),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              enabled: widget.enabled,
              minLines: 1,
              maxLines: 4,
              maxLength: 4000,
              textInputAction: TextInputAction.send,
              keyboardType: TextInputType.text,
              onSubmitted: (_) => widget.onSend(),
              onChanged: (_) => widget.onChanged(),
              onTapOutside: (_) => widget.focusNode.unfocus(),
              style: context.texts.bodyLarge?.copyWith(fontSize: 15, height: 1.45),
              decoration: InputDecoration(
                hintText: widget.enabled ? '也可以打字练习英语…' : '连接中，暂时无法发送',
                counterText: '',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: widget.compact ? 10 : 12, horizontal: 6),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 46,
            height: 46,
            child: Material(
              color: canSend ? c.teal : c.sunken,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: canSend ? widget.onSend : null,
                customBorder: const CircleBorder(),
                child: Center(
                  child: widget.sending
                      ? SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2, color: c.teal),
                        )
                      : Icon(
                          Icons.arrow_upward_rounded,
                          size: 20,
                          color: canSend ? c.onTeal : c.faint,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileDock extends StatelessWidget {
  const _MobileDock({
    required this.talk,
    required this.elapsed,
    required this.composer,
    required this.focusNode,
    required this.sending,
    required this.canSend,
    required this.onSend,
    required this.onChanged,
    required this.onGoals,
  });

  final TalkController talk;
  final int elapsed;
  final TextEditingController composer;
  final FocusNode focusNode;
  final bool sending;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onChanged;
  final VoidCallback onGoals;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line.withValues(alpha: 0.6))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: TalkOrb(
                  phase: talk.phase,
                  level: talk.micLevel,
                  reducedMotion: context.reduceMotion,
                  size: 78,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _phaseMeta(talk.phase, c).$1,
                            style: context.texts.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatShortDuration(elapsed),
                          style: tabular(context.texts.labelSmall?.copyWith(color: c.faint)),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: onGoals,
                          icon: const Icon(Icons.flag_outlined, size: 18),
                          tooltip: '本轮目标',
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    _MicMeter(talk: talk),
                    const SizedBox(height: 2),
                    Text(
                      talk.mode == TalkMode.handsFree
                          ? '自动静音 · 能量 VAD · 半双工'
                          : '按住说话 · 半双工外放安全',
                      style: context.texts.labelSmall?.copyWith(fontSize: 10, color: c.faint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (talk.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ErrorBanner(
                message: talk.error!,
                onDismiss: talk.clearError,
                onRetry: talk.phase == TalkPhase.disconnected || talk.phase == TalkPhase.failed
                    ? talk.reconnect
                    : null,
              ),
            ),
          if (talk.micError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ErrorBanner(
                message: talk.micError!,
                onRetry: talk.micUnsupported ? null : talk.retryMicrophone,
              ),
            ),
          const SizedBox(height: 8),
          _TalkControls(talk: talk, compact: true),
          const SizedBox(height: 8),
          _Composer(
            controller: composer,
            focusNode: focusNode,
            enabled: canSend && talk.phase != TalkPhase.ended ? true : (canSend || talk.canAcceptInput),
            sending: sending,
            onSend: onSend,
            onChanged: onChanged,
            compact: true,
          ),
        ],
      ),
    );
  }
}
