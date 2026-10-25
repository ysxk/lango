import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data.dart';
import '../ui/components.dart';
import '../ui/format.dart';
import '../ui/theme.dart';

class AdminInviteScreen extends StatefulWidget {
  const AdminInviteScreen({super.key});

  @override
  State<AdminInviteScreen> createState() => _AdminInviteScreenState();
}

class _AdminInviteScreenState extends State<AdminInviteScreen> {
  int _maxUses = 1;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _invite;

  Future<void> _generate() async {
    if (_busy) return;
    final app = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invite = await app.issueInvite(_maxUses);
      if (!mounted) return;
      setState(() => _invite = invite);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final invite = _invite;
    final expires = invite == null ? null : parseUtc(invite['expires_at']);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 48),
          child: PageFrame(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: '返回',
                    ),
                    const SizedBox(width: 2),
                    Text('管理员', style: context.texts.labelMedium),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'ADMIN · INVITES',
                  style: context.texts.labelSmall?.copyWith(
                    color: c.teal,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text('生成邀请码', style: context.texts.displaySmall?.copyWith(fontSize: 38)),
                const SizedBox(height: 10),
                Text(
                  '邀请码用于注册新账户。请通过可信渠道发送给受邀者，并说明使用次数上限。',
                  style: context.texts.bodySmall,
                ),
                if (!app.isAdmin) ...[
                  const SizedBox(height: 22),
                  const ErrorBanner(message: '当前账户不是管理员，无法生成邀请码。'),
                ],
                const SizedBox(height: 26),
                SurfacePanel(
                  padding: const EdgeInsets.all(24),
                  border: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('可用次数', style: context.texts.labelMedium),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _StepButton(
                            icon: Icons.remove_rounded,
                            onPressed: _busy || _maxUses <= 1
                                ? null
                                : () => setState(() => _maxUses--),
                          ),
                          SizedBox(
                            width: 72,
                            child: Text(
                              '$_maxUses',
                              textAlign: TextAlign.center,
                              style: tabular(context.texts.headlineMedium),
                            ),
                          ),
                          _StepButton(
                            icon: Icons.add_rounded,
                            onPressed: _busy || _maxUses >= 100
                                ? null
                                : () => setState(() => _maxUses++),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              '每个邀请码最多可供 $_maxUses 次注册。',
                              style: context.texts.bodySmall?.copyWith(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        ErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: 20),
                      LangoButton(
                        label: '生成邀请码',
                        icon: Icons.vpn_key_outlined,
                        loading: _busy,
                        onPressed: !app.isAdmin || _busy ? null : _generate,
                      ),
                    ],
                  ),
                ),
                if (invite != null) ...[
                  const SizedBox(height: 24),
                  SurfacePanel(
                    padding: const EdgeInsets.all(24),
                    radius: 26,
                    color: c.mint,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle_rounded, size: 19, color: c.mintInk),
                            const SizedBox(width: 8),
                            Text(
                              '邀请码已生成',
                              style: context.texts.titleSmall?.copyWith(color: c.mintInk),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SelectableText(
                          (invite['code'] as String?) ?? '',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 19,
                            height: 1.5,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                            color: c.mintInk,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            Text(
                              '可用次数 ${invite['max_uses'] ?? _maxUses}',
                              style: context.texts.labelSmall?.copyWith(color: c.mintInk),
                            ),
                            Text(
                              '已使用 ${invite['uses'] ?? 0}',
                              style: tabular(context.texts.labelSmall?.copyWith(color: c.mintInk)),
                            ),
                            if (expires != null)
                              Text(
                                '到期 ${formatSessionDate(expires)}',
                                style: tabular(context.texts.labelSmall?.copyWith(color: c.mintInk)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        CopyAction(
                          text: (invite['code'] as String?) ?? '',
                          label: '复制邀请码',
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                InfoBanner(
                  icon: Icons.info_outline_rounded,
                  message: '协议目前只提供生成接口，没有邀请码列表接口。此处只显示本次生成的结果；离开页面后请自行妥善保存。',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: c.sunken,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Icon(
            icon,
            size: 20,
            color: onPressed == null ? c.faint : c.ink,
          ),
        ),
      ),
    );
  }
}
