import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data.dart';
import '../ui/components.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import 'admin_invite_screen.dart';
import 'connect_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loaded = false;
  final _name = TextEditingController();
  final _goal = TextEditingController();
  final _interests = TextEditingController();
  String _level = 'A2';
  String? _voice;
  double _rate = 1.0;
  bool _savingProfile = false;
  bool _savingSound = false;
  String? _profileError;
  String? _soundError;

  static const _levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

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
    final voice = profile['voice'];
    _voice = voice is String ? voice : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _goal.dispose();
    _interests.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 2500),
      ));
  }

  Future<void> _saveProfile() async {
    if (_savingProfile) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _profileError = '称呼不能为空。');
      return;
    }
    final app = AppScope.of(context);
    setState(() {
      _savingProfile = true;
      _profileError = null;
    });
    try {
      await app.updateProfile({
        'display_name': _name.text.trim(),
        'level': _level,
        'goal': _goal.text.trim(),
        'interests': _interests.text.trim(),
      });
      _toast('档案已保存');
    } catch (e) {
      setState(() => _profileError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _saveSound() async {
    if (_savingSound) return;
    final app = AppScope.of(context);
    setState(() {
      _savingSound = true;
      _soundError = null;
    });
    try {
      final changes = <String, dynamic>{'speech_rate': _rate};
      if (_voice != null) changes['voice'] = _voice;
      await app.updateProfile(changes);
      _toast('声音设置已保存');
    } catch (e) {
      setState(() => _soundError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _savingSound = false);
    }
  }

  Future<void> _logout() async {
    final app = AppScope.of(context);
    final confirmed = await confirmAction(
      context,
      title: '退出登录？',
      message: '本机保存的账户凭证会被清除。服务端记录不会删除。',
      confirmLabel: '退出登录',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    await app.logout();
  }

  void _switchServer() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConnectScreen(switching: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final profile = app.profile ?? {};
    final voices = app.voices;
    final engines = app.engines;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 48),
          child: PageFrame(
            maxWidth: 900,
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
                    Text('设置', style: context.texts.labelMedium),
                  ],
                ),
                const SizedBox(height: 18),
                Text('设置', style: context.texts.displaySmall?.copyWith(fontSize: 38)),
                const SizedBox(height: 8),
                Text(
                  '档案、声音与外观。服务器地址和账户操作也在这里。',
                  style: context.texts.bodySmall,
                ),
                const SizedBox(height: 24),
                SurfacePanel(
                  padding: const EdgeInsets.all(20),
                  border: true,
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: c.mint, shape: BoxShape.circle),
                        child: Text(
                          app.displayName.trim().isEmpty
                              ? 'L'
                              : app.displayName.trim().characters.first.toUpperCase(),
                          style: context.texts.titleLarge?.copyWith(color: c.mintInk),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    app.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.texts.titleLarge,
                                  ),
                                ),
                                if (app.isAdmin) ...[
                                  const SizedBox(width: 8),
                                  TagChip('管理员', emphasis: true),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (profile['email'] as String?) ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.texts.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${levelLabel(profile['level'])} · ${voiceLabel(profile)}',
                              style: context.texts.labelSmall?.copyWith(color: c.faint),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                _SectionHeading(title: '个人档案', eyebrow: 'PROFILE', subtitle: '这些信息会保存到服务端，并影响对话中的称呼与难度。'),
                const SizedBox(height: 12),
                SurfacePanel(
                  padding: const EdgeInsets.all(22),
                  border: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LangoField(
                        label: '称呼',
                        controller: _name,
                        enabled: !_savingProfile,
                        hint: '对话中如何称呼你',
                      ),
                      const SizedBox(height: 18),
                      Text('英语水平', style: context.texts.labelMedium),
                      const SizedBox(height: 8),
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
                      const SizedBox(height: 18),
                      LangoField(
                        label: '目标',
                        controller: _goal,
                        enabled: !_savingProfile,
                        maxLines: 3,
                        minLines: 2,
                        hint: '你希望用英语完成什么？',
                      ),
                      const SizedBox(height: 18),
                      LangoField(
                        label: '兴趣与话题',
                        controller: _interests,
                        enabled: !_savingProfile,
                        hint: '例如：电影、徒步、科技',
                      ),
                      if (_profileError != null) ...[
                        const SizedBox(height: 14),
                        ErrorBanner(message: _profileError!),
                      ],
                      const SizedBox(height: 18),
                      LangoButton(
                        label: '保存档案',
                        icon: Icons.check_rounded,
                        loading: _savingProfile,
                        onPressed: _savingProfile ? null : _saveProfile,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                _SectionHeading(
                  title: '声音',
                  eyebrow: 'VOICE',
                  subtitle: '音色与语速保存到账户。声音由服务端提供的引擎生成。',
                ),
                const SizedBox(height: 12),
                SurfacePanel(
                  padding: const EdgeInsets.all(22),
                  border: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('音色', style: context.texts.labelMedium),
                      const SizedBox(height: 8),
                      if (voices.isEmpty)
                        Text('服务端暂未返回可用音色。', style: context.texts.bodySmall)
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
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Text('语速', style: context.texts.labelMedium),
                          const Spacer(),
                          Text(
                            '${_rate.toStringAsFixed(2)}×',
                            style: tabular(context.texts.titleSmall?.copyWith(color: c.teal)),
                          ),
                        ],
                      ),
                      Slider(
                        value: _rate,
                        min: 0.7,
                        max: 1.3,
                        divisions: 12,
                        label: '${_rate.toStringAsFixed(2)}×',
                        onChanged: _savingSound ? null : (value) => setState(() => _rate = value),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('慢 0.70×', style: context.texts.labelSmall?.copyWith(color: c.faint)),
                          Text('1.30× 快', style: context.texts.labelSmall?.copyWith(color: c.faint)),
                        ],
                      ),
                      if (_soundError != null) ...[
                        const SizedBox(height: 14),
                        ErrorBanner(message: _soundError!),
                      ],
                      const SizedBox(height: 18),
                      LangoButton(
                        label: '保存声音设置',
                        icon: Icons.check_rounded,
                        loading: _savingSound,
                        onPressed: _savingSound ? null : _saveSound,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                _SectionHeading(
                  title: '练习与外观',
                  eyebrow: 'PREFERENCES',
                  subtitle: '引擎、主题与动效只保存在这台设备。',
                ),
                const SizedBox(height: 12),
                SurfacePanel(
                  padding: const EdgeInsets.all(22),
                  border: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('练习引擎', style: context.texts.labelMedium),
                      const SizedBox(height: 4),
                      Text(
                        '引擎名称来自服务端配置，不显示底层模型或供应商信息。',
                        style: context.texts.bodySmall?.copyWith(fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      if (engines.isEmpty)
                        Text('服务端暂未返回可用引擎。', style: context.texts.bodySmall)
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: engines.map((engine) {
                            final id = engine['id'] as String?;
                            final name = (engine['name'] as String?) ?? id ?? '引擎';
                            return FilterPill(
                              label: name,
                              selected: app.currentEngine == id,
                              onTap: id == null
                                  ? null
                                  : () => app.setAppearance(engine: id),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 24),
                      Text('主题', style: context.texts.labelMedium),
                      const SizedBox(height: 8),
                      SegmentedChoice<String>(
                        options: const [
                          ChoiceOption(value: 'system', label: '跟随系统'),
                          ChoiceOption(value: 'light', label: '浅色'),
                          ChoiceOption(value: 'dark', label: '深色'),
                        ],
                        selected: app.theme,
                        onChanged: (value) => app.setAppearance(theme: value),
                        wrap: false,
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('减少动效', style: context.texts.titleSmall),
                                const SizedBox(height: 3),
                                Text(
                                  '关闭光球形变、流式模糊和页面过渡；遵循系统动效偏好。',
                                  style: context.texts.bodySmall?.copyWith(fontSize: 12, height: 1.5),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: app.reduceMotion,
                            onChanged: (value) => app.setAppearance(motion: value),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                _SectionHeading(title: '账户与服务器', eyebrow: 'ACCOUNT'),
                const SizedBox(height: 12),
                SurfacePanel(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  border: true,
                  child: Column(
                    children: [
                      _ActionRow(
                        icon: Icons.dns_outlined,
                        title: '服务器',
                        value: app.server,
                        onTap: _switchServer,
                        trailingText: '切换',
                      ),
                      _divider(context),
                      _ActionRow(
                        icon: Icons.alternate_email_rounded,
                        title: '邮箱',
                        value: (profile['email'] as String?) ?? '—',
                      ),
                      if (app.isAdmin) ...[
                        _divider(context),
                        _ActionRow(
                          icon: Icons.vpn_key_outlined,
                          title: '邀请码',
                          value: '管理员可生成新的邀请码',
                          trailingText: '生成',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AdminInviteScreen()),
                          ),
                        ),
                      ],
                      _divider(context),
                      _ActionRow(
                        icon: Icons.logout_rounded,
                        title: '退出登录',
                        value: '清除本机凭证，保留服务端记录',
                        trailingText: '退出',
                        danger: true,
                        onTap: _logout,
                      ),
                    ],
                  ),
                ),
                if (app.serverUsesCleartext) ...[
                  const SizedBox(height: 14),
                  const ErrorBanner(
                    message: '当前使用 HTTP 明文连接。仅限可信局域网开发；公网请配置 HTTPS。',
                  ),
                ],
                const SizedBox(height: 30),
                _SectionHeading(title: '隐私与安全', eyebrow: 'PRIVACY'),
                const SizedBox(height: 12),
                SurfacePanel(
                  padding: const EdgeInsets.all(22),
                  border: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PrivacyLine(
                        icon: Icons.lock_outline_rounded,
                        title: '账户凭证',
                        text: '访问与刷新令牌存放在设备加密存储中；切换服务器或退出登录会清理账户状态。',
                      ),
                      const SizedBox(height: 14),
                      _PrivacyLine(
                        icon: Icons.mic_none_rounded,
                        title: '麦克风与音频',
                        text: '录音以 16 kHz 单声道 PCM16 流式发送；原始录音不写入磁盘。播放时暂停麦克风（半双工）。',
                      ),
                      const SizedBox(height: 14),
                      _PrivacyLine(
                        icon: Icons.graphic_eq_rounded,
                        title: '自动静音的边界',
                        text: '自动静音使用能量阈值检测，不是神经网络 VAD；约 0.95 秒静音后提交。',
                      ),
                      const SizedBox(height: 14),
                      _PrivacyLine(
                        icon: Icons.link_rounded,
                        title: '连接票据',
                        text: 'WebSocket 使用每次连接新签发的一次性短期票据；访问令牌不会出现在网址中。',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 34),
                Center(
                  child: Text(
                    'Lango · 真实的英语口语练习',
                    style: context.texts.labelSmall?.copyWith(color: c.faint),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(height: 1, color: context.colors.line.withValues(alpha: 0.55)),
      );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.eyebrow, this.subtitle});
  final String title;
  final String eyebrow;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: context.texts.labelSmall?.copyWith(
            color: c.teal,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(title, style: context.texts.headlineSmall?.copyWith(fontSize: 21)),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(subtitle!, style: context.texts.bodySmall),
        ],
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.value,
    this.trailingText,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? trailingText;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        children: [
          Icon(icon, size: 19, color: danger ? c.danger : c.secondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.texts.titleSmall?.copyWith(color: danger ? c.danger : c.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelSmall?.copyWith(color: c.faint),
                ),
              ],
            ),
          ),
          if (trailingText != null) ...[
            const SizedBox(width: 10),
            Text(
              trailingText!,
              style: context.texts.labelSmall?.copyWith(
                color: danger ? c.danger : c.teal,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: danger ? c.danger : c.faint),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

class _PrivacyLine extends StatelessWidget {
  const _PrivacyLine({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: c.teal),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.texts.titleSmall),
              const SizedBox(height: 3),
              Text(text, style: context.texts.bodySmall?.copyWith(fontSize: 12, height: 1.55)),
            ],
          ),
        ),
      ],
    );
  }
}
