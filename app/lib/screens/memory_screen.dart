import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data.dart';
import '../ui/components.dart';
import '../ui/format.dart';
import '../ui/theme.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  bool _busy = false;
  String? _deletingId;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 2500),
      ));
  }

  Future<void> _toggle(bool enabled) async {
    if (_busy) return;
    final app = AppScope.of(context);
    setState(() => _busy = true);
    try {
      await app.setMemoryEnabled(enabled);
      _toast(enabled ? '记忆已开启' : '记忆已关闭，后续对话不会建立新记忆');
    } catch (e) {
      _toast(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteOne(String id) async {
    if (_busy) return;
    final confirmed = await confirmAction(
      context,
      title: '删除这条记忆？',
      message: '删除后无法恢复。它不会再被用于之后的对话。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final app = AppScope.of(context);
    setState(() {
      _busy = true;
      _deletingId = id;
    });
    try {
      await app.forget(id);
      _toast('记忆已删除');
    } catch (e) {
      _toast(errorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _deletingId = null;
        });
      }
    }
  }

  Future<void> _forgetAll() async {
    if (_busy) return;
    final confirmed = await confirmAction(
      context,
      title: '遗忘全部记忆？',
      message: '所有已建立的记忆会被删除，尚未完成的记忆任务也会作废。此操作无法撤销。',
      confirmLabel: '全部遗忘',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final app = AppScope.of(context);
    setState(() => _busy = true);
    try {
      await app.forget();
      _toast('全部记忆已遗忘');
    } catch (e) {
      _toast(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    return RefreshIndicator(
      color: c.teal,
      onRefresh: app.load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 48),
        child: PageFrame(
          maxWidth: 900,
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
                          'MEMORY',
                          style: context.texts.labelSmall?.copyWith(
                            color: c.teal,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('记忆', style: context.texts.displaySmall),
                        const SizedBox(height: 8),
                        Text(
                          '只保存服务端确认的学习信息，不把角色扮演里的虚构内容当成你的真实经历。',
                          style: context.texts.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SurfacePanel(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
                border: true,
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: app.memoryEnabled ? c.mint : c.sunken,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        app.memoryEnabled ? Icons.auto_awesome_outlined : Icons.memory_outlined,
                        size: 20,
                        color: app.memoryEnabled ? c.mintInk : c.faint,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.memoryEnabled ? '记忆已开启' : '记忆已关闭',
                            style: context.texts.titleSmall,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            app.memoryEnabled
                                ? '后续对话结束时，服务端会整理可复用的学习信息。'
                                : '已有记忆仍可查看与删除；不会新增记忆。',
                            style: context.texts.bodySmall?.copyWith(fontSize: 12, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: app.memoryEnabled,
                      onChanged: _busy ? null : _toggle,
                    ),
                  ],
                ),
              ),
              if (app.error != null) ...[
                const SizedBox(height: 16),
                ErrorBanner(message: app.error!, onRetry: app.load),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Text(
                    '已建立 ${app.memories.length} 条',
                    style: context.texts.titleSmall,
                  ),
                  const Spacer(),
                  if (app.memories.isNotEmpty)
                    TextButton.icon(
                      onPressed: _busy ? null : _forgetAll,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      style: TextButton.styleFrom(foregroundColor: c.danger),
                      label: const Text('全部遗忘'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (app.loading && app.memories.isEmpty)
                const LoadingBlock(label: '正在读取记忆…')
              else if (app.memories.isEmpty)
                SurfacePanel(
                  padding: EdgeInsets.zero,
                  child: EmptyState(
                    icon: Icons.auto_awesome_outlined,
                    title: '还没有记忆',
                    message: app.memoryEnabled
                        ? '完成更多对话后，服务端可能会整理出可复用的学习信息。这里不会出现演示数据。'
                        : '记忆目前关闭。打开后，新的对话才会建立记忆。',
                  ),
                )
              else
                SurfacePanel(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Column(
                    children: [
                      for (var i = 0; i < app.memories.length; i++) ...[
                        _MemoryRow(
                          memory: app.memories[i],
                          deleting: _deletingId == app.memories[i]['id'],
                          onDelete: _busy
                              ? null
                              : () => _deleteOne(app.memories[i]['id'] as String),
                        ),
                        if (i != app.memories.length - 1)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Container(height: 1, color: c.line.withValues(alpha: 0.5)),
                          ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 22),
              InfoBanner(
                icon: Icons.shield_outlined,
                message: '记忆始终按账户隔离。删除单条或全部遗忘后，服务端还会作废正在排队的记忆任务，避免已遗忘的内容复活。',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryRow extends StatelessWidget {
  const _MemoryRow({required this.memory, required this.deleting, required this.onDelete});
  final Map<String, dynamic> memory;
  final bool deleting;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final created = parseUtc(memory['created_at']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: c.mint,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.auto_awesome, size: 14, color: c.mintInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (memory['memory'] as String?) ?? '',
                  style: context.texts.bodyMedium?.copyWith(height: 1.55),
                ),
                if (created != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    '建立于 ${formatSessionDate(created)}',
                    style: context.texts.labelSmall?.copyWith(color: c.faint),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (deleting)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 19),
              tooltip: '删除这条记忆',
              color: c.faint,
            ),
        ],
      ),
    );
  }
}
