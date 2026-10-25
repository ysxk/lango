import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data.dart';
import '../ui/components.dart';
import '../ui/theme.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, this.switching = false});
  final bool switching;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TextEditingController _server;
  bool _busy = false;
  String? _error;
  bool _canSkip = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final server = AppScope.maybeOf(context)?.server ?? '';
    if (server.isNotEmpty) _server.text = server;
  }

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  Future<void> _submit({bool skipHealth = false}) async {
    if (_busy) return;
    final app = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _canSkip = false;
    });
    try {
      if (widget.switching) {
        await app.changeServer(_server.text, skipHealth: skipHealth);
      } else {
        await app.connectToServer(_server.text, skipHealth: skipHealth);
      }
      if (!mounted) return;
      if (widget.switching) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _canSkip = !skipHealth;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final app = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final form = _ConnectForm(
      controller: _server,
      switching: widget.switching,
      busy: _busy,
      error: _error,
      canSkip: _canSkip,
      onServerChanged: () => setState(() {}),
      onSubmit: () => _submit(),
      onSkip: () => _submit(skipHealth: true),
      onBack: widget.switching ? () => Navigator.of(context).maybePop() : null,
      server: app.server,
    );

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(vertical: wide ? 48 : 24),
          child: PageFrame(
            maxWidth: 1080,
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(flex: 5, child: _ConnectIntro()),
                      const SizedBox(width: 56),
                      SizedBox(width: 430, child: form),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MobileBrand(onBack: widget.switching ? () => Navigator.of(context).maybePop() : null),
                      const SizedBox(height: 28),
                      Text(
                        '让英语，\n从一句真实的话开始。',
                        style: context.texts.displaySmall?.copyWith(height: 1.12),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '连接到你自己的 Lango 服务，进入安静的口语练习室。',
                        style: context.texts.bodyMedium?.copyWith(color: c.secondary),
                      ),
                      const SizedBox(height: 28),
                      form,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _MobileBrand extends StatelessWidget {
  const _MobileBrand({this.onBack});
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null)
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: '返回',
          ),
        const LangoMark(size: 34),
        const SizedBox(width: 10),
        Text(
          'Lango',
          style: LangoTheme.display(22, weight: FontWeight.w500).copyWith(color: context.colors.ink),
        ),
      ],
    );
  }
}

class _ConnectIntro extends StatelessWidget {
  const _ConnectIntro();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const LangoMark(size: 38),
            const SizedBox(width: 12),
            Text(
              'Lango',
              style: LangoTheme.display(24, weight: FontWeight.w500).copyWith(color: c.ink),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: c.mint, borderRadius: BorderRadius.circular(999)),
              child: Text('英语口语', style: context.texts.labelSmall?.copyWith(color: c.mintInk)),
            ),
          ],
        ),
        const SizedBox(height: 64),
        Text(
          'Speak a little,\nevery day.',
          style: context.texts.displayLarge?.copyWith(fontSize: 58, height: 1.03),
        ),
        const SizedBox(height: 26),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            '一个安静、专注的英语练习室。选择真实场景，和 AI 角色开口对话；说错了也没关系，随时可以停下。',
            style: context.texts.bodyLarge?.copyWith(color: c.secondary, height: 1.8),
          ),
        ),
        const SizedBox(height: 40),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: const [
            TagChip('12 个真实场景', emphasis: true),
            TagChip('语音与文字'),
            TagChip('记忆可随时遗忘'),
          ],
        ),
        const SizedBox(height: 56),
        Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: c.faint),
            const SizedBox(width: 8),
            Text('账户凭证保存在设备的加密存储中', style: context.texts.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _ConnectForm extends StatelessWidget {
  const _ConnectForm({
    required this.controller,
    required this.switching,
    required this.busy,
    required this.error,
    required this.canSkip,
    required this.onServerChanged,
    required this.onSubmit,
    required this.onSkip,
    required this.onBack,
    required this.server,
  });

  final TextEditingController controller;
  final bool switching;
  final bool busy;
  final String? error;
  final bool canSkip;
  final VoidCallback onServerChanged;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;
  final VoidCallback? onBack;
  final String server;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = controller.text.trim();
    final isHttp = value.toLowerCase().startsWith('http://');
    final blockedMixedContent =
        kIsWeb && Uri.base.scheme == 'https' && isHttp;
    return SurfacePanel(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
      radius: 28,
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onBack != null) ...[
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  tooltip: '返回',
                ),
                const SizedBox(width: 4),
              ],
              Text(
                switching ? '切换服务器' : '连接服务',
                style: context.texts.labelSmall?.copyWith(letterSpacing: 1.4, color: c.teal),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            switching ? '回到你的练习室' : '先连接，再开始。',
            style: context.texts.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '输入你自己部署的 Lango 服务地址。地址不带路径，协议为 v1。',
            style: context.texts.bodySmall?.copyWith(color: c.secondary),
          ),
          const SizedBox(height: 24),
          LangoField(
            label: '服务器地址',
            controller: controller,
            hint: 'https://lango.example.com',
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            prefixIcon: Icons.link_rounded,
            enabled: !busy,
            onChanged: (_) => onServerChanged(),
            onSubmitted: (_) => onSubmit(),
            helper: '例如 https://lango.example.com 或 http://192.168.1.20:8000',
          ),
          if (isHttp) ...[
            const SizedBox(height: 14),
            InfoBanner(
              icon: Icons.warning_amber_rounded,
              message: blockedMixedContent
                  ? '当前网页通过 HTTPS 打开，浏览器会拦截明文 HTTP 连接。请改用 HTTPS 服务地址。'
                  : 'HTTP 为明文连接，仅限可信局域网开发使用。公网请配置 HTTPS。',
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(message: error!),
          ],
          const SizedBox(height: 22),
          LangoButton(
            label: busy ? '正在连接…' : '连接并继续',
            icon: Icons.arrow_forward_rounded,
            expand: true,
            loading: busy,
            onPressed: busy ? null : onSubmit,
          ),
          if (canSkip && !busy) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: onSkip,
                child: const Text('健康检查不可用，仍然继续'),
              ),
            ),
          ],
          const SizedBox(height: 22),
          Container(height: 1, color: c.line.withValues(alpha: 0.7)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, size: 16, color: c.faint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '访问令牌保存在设备加密存储中；语音不写入磁盘。',
                  style: context.texts.bodySmall?.copyWith(fontSize: 12, height: 1.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
