String pad2(int value) => value.toString().padLeft(2, '0');

String formatDuration(int seconds) {
  if (seconds <= 0) return '0 分钟';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (minutes == 0) return '$rest 秒';
  if (rest == 0) return '$minutes 分钟';
  return '$minutes 分 $rest 秒';
}

String formatShortDuration(int seconds) {
  final clamped = seconds < 0 ? 0 : seconds;
  final minutes = clamped ~/ 60;
  final rest = clamped % 60;
  return '$minutes:${pad2(rest)}';
}

String formatClock(DateTime time) => '${pad2(time.hour)}:${pad2(time.minute)}';

String formatSessionDate(DateTime utc) {
  final local = utc.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(local.year, local.month, local.day);
  final difference = today.difference(thatDay).inDays;
  if (difference == 0) return '今天 ${formatClock(local)}';
  if (difference == 1) return '昨天 ${formatClock(local)}';
  if (local.year == now.year) {
    return '${local.month} 月 ${local.day} 日 ${formatClock(local)}';
  }
  return '${local.year} 年 ${local.month} 月 ${local.day} 日';
}

DateTime? parseUtc(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour < 5) return '夜深了';
  if (hour < 11) return '早上好';
  if (hour < 13) return '中午好';
  if (hour < 18) return '下午好';
  return '晚上好';
}

String todayLabel(DateTime now) {
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  return '${now.month} 月 ${now.day} 日 · 星期${weekdays[now.weekday - 1]}';
}

String levelLabel(Object? value) {
  final level = value is String ? value : '';
  return switch (level) {
    'A1' => '入门 A1',
    'A2' => '基础 A2',
    'B1' => '进阶 B1',
    'B2' => '中高级 B2',
    'C1' => '流利 C1',
    'C2' => '精通 C2',
    _ => '未设置',
  };
}

String engineLabel(Map<String, dynamic> config, String? id) {
  if (id == null || id.isEmpty) return '默认引擎';
  final engines = config['engines'];
  if (engines is List) {
    for (final engine in engines) {
      if (engine is Map && engine['id'] == id) {
        final name = engine['name'];
        if (name is String && name.isNotEmpty) return name;
      }
    }
  }
  return id;
}

String voiceLabel(Map<String, dynamic> profile) {
  final voice = profile['voice'];
  return voice is String && voice.isNotEmpty ? voice : '默认音色';
}

String sessionTitle(Map<String, dynamic> session) {
  final title = session['title'];
  if (title is String && title.trim().isNotEmpty) return title.trim();
  final scenario = session['scenario_id'];
  return scenario is String ? scenario : '练习对话';
}
