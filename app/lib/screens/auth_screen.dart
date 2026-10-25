import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'connect_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _register = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _invite = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _invite.dispose();
    super.dispose();
  }

  String? _validate() {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return '请输入有效邮箱地址。';
    }
    if (_password.text.length < 10) return '密码至少需要 10 个字符。';
    if (_register) {
      if (_name.text.trim().isEmpty) return '请填写称呼。';
      if (_invite.text.trim().length < 16) return '邀请码至少为 16 个字符，请向管理员确认。';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final validation = _validate();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    final app = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final values = <String, dynamic>{
        'email': _email.text.trim(),
        'password': _password.text,
      };
      if (_register) {
        values['display_name'] = _name.text.trim();
        values['invite_code'] = _invite.text.trim();
      }
      await app.login(_register, values);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(bool register) {
    if (_busy) return;
    setState(() {
      _register = register;
      _error = null;
    });
  }

  void _changeServer() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConnectScreen(switching: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final app = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 920;
    final card = _AuthCard(
      register: _register,
      busy: _busy,
      obscure: _obscure,
      error: _error ?? app.error,
      email: _email,
      password: _password,
      name: _name,
      invite: _invite,
      onToggle: _toggle,
      onToggleObscure: () => setState(() => _obscure = !_obscure),
      onSubmit: _submit,
      onChangeServer: _changeServer,
      server: app.server,
    );
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(vertical: wide ? 44 : 24),
          child: PageFrame(
            maxWidth: 1060,
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _AuthIntro(register: _register),
                      ),
                      const SizedBox(width: 56),
                      SizedBox(width: 440, child: card),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const LangoMark(size: 34),
                          const SizedBox(width: 10),
                          Text(
                            'Lango',
                            style: LangoTheme.display(22, weight: FontWeight.w500)
                                .copyWith(color: c.ink),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _changeServer,
                            icon: const Icon(Icons.dns_outlined, size: 20),
                            tooltip: '更换服务器',
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      card,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _AuthIntro extends StatelessWidget {
  const _AuthIntro({required this.register});
  final bool register;

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
          ],
        ),
        const SizedBox(height: 72),
        AnimatedSwitcher(
          duration: context.motion(220),
          switchInCurve: Curves.easeOutCubic,
          child: Text(
            register ? 'A room of\nyour own.' : 'Welcome\nback.',
            key: ValueKey(register),
            style: context.texts.displayLarge?.copyWith(fontSize: 58, height: 1.04),
          ),
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            register
                ? '用邀请码创建账户。先认识你的水平与目标，再开始第一段对话。'
                : '回到你的练习记录、场景目标与语音对话。所有的进度，都来自真实练习。',
            style: context.texts.bodyLarge?.copyWith(color: c.secondary, height: 1.8),
          ),
        ),
        const SizedBox(height: 44),
        Row(
          children: [
            _QuietPoint(icon: Icons.mic_none_rounded, label: '说或写都可以'),
            const SizedBox(width: 24),
            _QuietPoint(icon: Icons.auto_awesome_outlined, label: '12 个生活场景'),
          ],
        ),
      ],
    );
  }
}

class _QuietPoint extends StatelessWidget {
  const _QuietPoint({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Icon(icon, size: 17, color: c.teal),
        const SizedBox(width: 8),
        Text(label, style: context.texts.bodySmall?.copyWith(color: c.secondary)),
      ],
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.register,
    required this.busy,
    required this.obscure,
    required this.error,
    required this.email,
    required this.password,
    required this.name,
    required this.invite,
    required this.onToggle,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onChangeServer,
    required this.server,
  });

  final bool register;
  final bool busy;
  final bool obscure;
  final String? error;
  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController name;
  final TextEditingController invite;
  final ValueChanged<bool> onToggle;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback onChangeServer;
  final String server;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SurfacePanel(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
      radius: 28,
      elevated: true,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              register ? '创建账户' : '登录',
              style: context.texts.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              register ? '邀请制的小练习室。' : '继续上次的练习。',
              style: context.texts.bodySmall,
            ),
            const SizedBox(height: 22),
            SegmentedChoice<bool>(
              options: const [
                ChoiceOption(value: false, label: '登录'),
                ChoiceOption(value: true, label: '注册'),
              ],
              selected: register,
              onChanged: onToggle,
              wrap: false,
            ),
            const SizedBox(height: 22),
            if (register) ...[
              LangoField(
                label: '称呼',
                controller: name,
                hint: '我们怎么称呼你？',
                enabled: !busy,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
              ),
              const SizedBox(height: 16),
            ],
            LangoField(
              label: '邮箱',
              controller: email,
              hint: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              enabled: !busy,
              autofillHints: const [AutofillHints.email],
              enableSuggestions: false,
            ),
            const SizedBox(height: 16),
            LangoField(
              label: '密码',
              controller: password,
              hint: '至少 10 个字符',
              obscure: obscure,
              enabled: !busy,
              textInputAction: register ? TextInputAction.next : TextInputAction.done,
              onSubmitted: (_) {
                if (!register) onSubmit();
              },
              autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
              suffix: IconButton(
                onPressed: onToggleObscure,
                icon: Icon(
                  obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 19,
                ),
                tooltip: obscure ? '显示密码' : '隐藏密码',
              ),
            ),
            if (register) ...[
              const SizedBox(height: 16),
              LangoField(
                label: '邀请码',
                controller: invite,
                hint: '16 位或更长的邀请码',
                enabled: !busy,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmit(),
                helper: '邀请码由管理员发放，每个邀请码有使用次数上限。',
                enableSuggestions: false,
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              ErrorBanner(message: error!),
            ],
            const SizedBox(height: 22),
            LangoButton(
              label: busy ? '请稍候…' : (register ? '创建并继续' : '登录'),
              expand: true,
              loading: busy,
              onPressed: busy ? null : onSubmit,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    server,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelSmall?.copyWith(color: c.faint),
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : onChangeServer,
                  child: const Text('更换服务器'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
