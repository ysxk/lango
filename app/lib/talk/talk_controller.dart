import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../data.dart';

enum TalkMode {
  ptt,
  handsFree;

  String get wire => this == TalkMode.ptt ? 'ptt' : 'hands_free';
  String get label => this == TalkMode.ptt ? '按住说话' : '自动静音';
}

enum TalkPhase { idle, connecting, listening, thinking, speaking, paused, disconnected, ended, failed }

class TalkLine {
  TalkLine({
    required this.role,
    required this.text,
    this.interrupted = false,
    this.streaming = false,
    this.local = false,
    this.createdAt,
  });

  final String role;
  String text;
  bool interrupted;
  bool streaming;
  bool local;
  final DateTime? createdAt;

  bool get isUser => role == 'user';
}

class TalkControllerConfig {
  const TalkControllerConfig({
    required this.mode,
    this.scenarioId,
    this.sessionId,
    this.engine,
    this.initialLines = const [],
    this.initialGoals = const [],
    this.startedAt,
    this.lessonTitle,
  });

  final TalkMode mode;
  final String? scenarioId;
  final String? sessionId;
  final String? engine;
  final List<TalkLine> initialLines;
  final List<int> initialGoals;
  final DateTime? startedAt;
  final String? lessonTitle;
}

abstract class TalkSocket {
  Stream<dynamic> get messages;
  void sendJson(String text);
  void sendBinary(Uint8List bytes);
  Future<void> close([int? code, String? reason]);
}

typedef TalkSocketFactory = Future<TalkSocket> Function(Uri uri);

class _ChannelTalkSocket implements TalkSocket {
  _ChannelTalkSocket(this._channel);
  final WebSocketChannel _channel;

  @override
  Stream<dynamic> get messages => _channel.stream;

  @override
  void sendJson(String text) => _channel.sink.add(text);

  @override
  void sendBinary(Uint8List bytes) => _channel.sink.add(bytes);

  @override
  Future<void> close([int? code, String? reason]) => _channel.sink.close(code, reason);
}

Future<TalkSocket> openWebSocket(Uri uri) async {
  final channel = WebSocketChannel.connect(uri);
  await channel.ready.timeout(const Duration(seconds: 20));
  return _ChannelTalkSocket(channel);
}

abstract class MicSource {
  Future<bool> isSupported();
  Future<bool> ensurePermission();
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> dispose();
}

class RecordMicSource implements MicSource {
  final AudioRecorder _recorder = AudioRecorder();
  bool? _supported;

  @override
  Future<bool> isSupported() async {
    final cached = _supported;
    if (cached != null) return cached;
    final value = await _recorder.isEncoderSupported(AudioEncoder.pcm16bits);
    _supported = value;
    return value;
  }

  @override
  Future<bool> ensurePermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> start() {
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: false,
        streamBufferSize: 3200,
      ),
    );
  }

  @override
  Future<void> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}

abstract class WavePlayer {
  Stream<void> get completed;
  Future<void> play(Uint8List wav);
  Future<void> stop();
  Future<void> dispose();
}

class AudioplayersWavePlayer implements WavePlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<void> get completed => _player.onPlayerComplete;

  @override
  Future<void> play(Uint8List wav) =>
      _player.play(BytesSource(wav, mimeType: 'audio/wav'));

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

class _Segment {
  const _Segment(this.responseId, this.sequence, this.wav, this.text);
  final String responseId;
  final int sequence;
  final Uint8List wav;
  final String text;
}

class _Response {
  _Response(this.id);
  final String id;
  final StringBuffer delta = StringBuffer();
  final List<String> phrases = [];
  final List<String> playedPhrases = [];
  TalkLine? line;
  bool done = false;
  String status = '';

  String get displayText {
    final d = delta.toString().trim();
    if (d.isNotEmpty) return d;
    return phrases.join(' ').trim();
  }

  void refreshLine() {
    final current = line;
    if (current == null) return;
    final text = displayText;
    if (text.isNotEmpty) current.text = text;
    current.streaming = !done;
  }
}

class TalkController extends ChangeNotifier {
  TalkController({
    required this.api,
    required this.config,
    TalkSocketFactory? socketFactory,
    MicSource? mic,
    WavePlayer? player,
    DateTime Function()? clock,
  })  : _socketFactory = socketFactory ?? openWebSocket,
        _mic = mic ?? RecordMicSource(),
        _player = player ?? AudioplayersWavePlayer(),
        _clock = clock ?? DateTime.now,
        _lines = List<TalkLine>.of(config.initialLines),
        _completedGoals = List<int>.of(config.initialGoals),
        startedAt = config.startedAt {
    _audioSub = _player.completed.listen((_) {
      final completer = _segmentDone;
      if (completer != null && !completer.isCompleted) completer.complete();
    });
  }

  final ApiClient api;
  final TalkControllerConfig config;
  final TalkSocketFactory _socketFactory;
  final MicSource _mic;
  final WavePlayer _player;
  final DateTime Function() _clock;

  final List<TalkLine> _lines;
  final List<int> _completedGoals;
  final List<_Segment> _queue = [];
  final Map<String, _Response> _responses = {};
  final Set<String> _ignoredResponses = {};
  final Set<String> _finalizedResponses = {};

  late final StreamSubscription<void> _audioSub;
  StreamSubscription<dynamic>? _socketSub;
  StreamSubscription<Uint8List>? _micSub;
  TalkSocket? _socket;
  Timer? _startTimer;
  Timer? _resumeTimer;
  Completer<void>? _segmentDone;
  Completer<void>? _ended;

  TalkPhase phase = TalkPhase.idle;
  String? sessionId;
  String? error;
  String? micError;
  bool micPermissionDenied = false;
  bool micUnsupported = false;
  bool autoPaused = false;
  bool suspended = false;
  double micLevel = 0;
  String? activeResponseId;
  DateTime? startedAt;
  String? engineAlias;

  int _epoch = 0;
  int _captureEpoch = 0;
  bool _disposed = false;
  bool _closing = false;
  bool _playing = false;
  bool _capturing = false;
  bool _startingCapture = false;
  bool _autoCapture = false;
  bool _manualPtt = false;

  bool _speechStarted = false;
  double _noiseFloor = 0;
  int _calibrationChunks = 0;
  double _calibrationMs = 0;
  double _speechMs = 0;
  double _silenceMs = 0;
  double _totalMs = 0;
  final List<Uint8List> _preRoll = [];
  int _preRollBytes = 0;

  List<TalkLine> get lines => List.unmodifiable(_lines);
  List<int> get completedGoals => List.unmodifiable(_completedGoals);
  TalkMode get mode => config.mode;
  bool get isRecording => _capturing;
  bool get isPlaying => _playing;
  bool get ended => phase == TalkPhase.ended;
  bool get canAcceptInput =>
      !_closing &&
      !_disposed &&
      sessionId != null &&
      phase != TalkPhase.connecting &&
      phase != TalkPhase.ended &&
      phase != TalkPhase.paused &&
      phase != TalkPhase.failed &&
      phase != TalkPhase.disconnected;

  bool get canStartCapture =>
      canAcceptInput &&
      !suspended &&
      !_capturing &&
      !_startingCapture &&
      !_playing &&
      _queue.isEmpty &&
      activeResponseId == null &&
      phase == TalkPhase.listening;

  bool get canInterrupt => activeResponseId != null || _playing || _queue.isNotEmpty;

  String? get currentResponseText {
    final id = activeResponseId;
    if (id == null) return null;
    return _responses[id]?.displayText;
  }

  Future<void> start() async {
    if (_disposed || _closing || _socket != null) return;
    await _connect();
  }

  Future<void> _connect() async {
    final epoch = ++_epoch;
    phase = TalkPhase.connecting;
    error = null;
    _notify();
    try {
      final result = await api.request('POST', '/talk/ticket');
      if (epoch != _epoch || _disposed || _closing) return;
      final ticket = result is Map ? result['ticket'] : null;
      if (ticket is! String || ticket.isEmpty) {
        throw const ApiException('无法获取会话凭证，请重试。');
      }
      final base = Uri.parse(api.server);
      final uri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/api/v1/talk',
        queryParameters: {'ticket': ticket},
      );
      final socket = await _socketFactory(uri);
      if (epoch != _epoch || _disposed || _closing) {
        unawaited(socket.close());
        return;
      }
      _socket = socket;
      _socketSub = socket.messages.listen(
        (message) => _onMessage(message, epoch),
        onError: (Object _) => _onSocketLost(epoch, '连接发生错误。'),
        onDone: () => _onSocketLost(epoch, '连接已断开。'),
        cancelOnError: false,
      );
      final payload = <String, dynamic>{
        'type': 'session.start',
        'mode': config.mode.wire,
      };
      if (config.sessionId != null) {
        payload['session_id'] = config.sessionId;
      } else if (config.scenarioId != null) {
        payload['scenario_id'] = config.scenarioId;
      }
      if (config.engine != null) {
        payload['engine'] = config.engine;
        engineAlias = config.engine;
      }
      _sendRaw(payload);
      _startTimer?.cancel();
      _startTimer = Timer(const Duration(seconds: 20), () {
        if (epoch == _epoch && phase == TalkPhase.connecting) {
          error = '连接超时，请检查网络或服务地址后重试。';
          phase = TalkPhase.failed;
          _notify();
        }
      });
      _notify();
    } on ApiException catch (e) {
      if (epoch == _epoch && !_disposed) {
        error = e.message;
        phase = TalkPhase.failed;
        _notify();
      }
    } catch (_) {
      if (epoch == _epoch && !_disposed) {
        error = '无法建立实时连接，请检查网络或服务地址。';
        phase = TalkPhase.failed;
        _notify();
      }
    }
  }

  Future<void> reconnect() async {
    if (_disposed || _closing) return;
    if (phase == TalkPhase.ended) return;
    final resumeId = sessionId ?? config.sessionId;
    _epoch++;
    _cancelResumeTimer();
    await _stopCapture(sendCancel: false);
    _queue.clear();
    _ignoredResponses.addAll(_responses.keys);
    _responses.clear();
    activeResponseId = null;
    await _stopPlayback();
    await _teardownSocket();
    suspended = false;
    autoPaused = false;
    phase = TalkPhase.connecting;
    error = null;
    _notify();
    final epoch = ++_epoch;
    await _connectResume(resumeId, epoch);
  }

  Future<void> _connectResume(String? resumeId, int epoch) async {
    try {
      final result = await api.request('POST', '/talk/ticket');
      if (epoch != _epoch || _disposed || _closing) return;
      final ticket = result is Map ? result['ticket'] : null;
      if (ticket is! String || ticket.isEmpty) {
        throw const ApiException('无法获取会话凭证，请重试。');
      }
      final base = Uri.parse(api.server);
      final uri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/api/v1/talk',
        queryParameters: {'ticket': ticket},
      );
      final socket = await _socketFactory(uri);
      if (epoch != _epoch || _disposed || _closing) {
        unawaited(socket.close());
        return;
      }
      _socket = socket;
      _socketSub = socket.messages.listen(
        (message) => _onMessage(message, epoch),
        onError: (Object _) => _onSocketLost(epoch, '连接发生错误。'),
        onDone: () => _onSocketLost(epoch, '连接已断开。'),
        cancelOnError: false,
      );
      final payload = <String, dynamic>{
        'type': 'session.start',
        'mode': config.mode.wire,
      };
      if (resumeId != null) {
        payload['session_id'] = resumeId;
      } else if (config.scenarioId != null) {
        payload['scenario_id'] = config.scenarioId;
      }
      if (config.engine != null) payload['engine'] = config.engine;
      _sendRaw(payload);
      _startTimer?.cancel();
      _startTimer = Timer(const Duration(seconds: 20), () {
        if (epoch == _epoch && phase == TalkPhase.connecting) {
          error = '重连超时，请稍后重试。';
          phase = TalkPhase.failed;
          _notify();
        }
      });
      _notify();
    } on ApiException catch (e) {
      if (epoch == _epoch && !_disposed) {
        error = e.message;
        phase = TalkPhase.disconnected;
        _notify();
      }
    } catch (_) {
      if (epoch == _epoch && !_disposed) {
        error = '重新连接失败，请检查网络后重试。';
        phase = TalkPhase.disconnected;
        _notify();
      }
    }
  }

  Future<void> _teardownSocket() async {
    await _socketSub?.cancel();
    _socketSub = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  void _onMessage(dynamic raw, int epoch) {
    if (epoch != _epoch || _disposed) return;
    if (raw is String) {
      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) return;
        data = Map<String, dynamic>.from(decoded);
      } catch (_) {
        return;
      }
      _onJson(data);
    }
  }

  void _onJson(Map<String, dynamic> data) {
    final type = data['type'];
    switch (type) {
      case 'session.created':
        _startTimer?.cancel();
        _startTimer = null;
        final id = data['session_id'];
        if (id is String && id.isNotEmpty) sessionId = id;
        startedAt ??= _clock();
        if (phase != TalkPhase.ended) phase = TalkPhase.listening;
        _notify();
        _maybeResumeMic(delay: 900);
        return;
      case 'state':
        final state = data['state'];
        if (state is String && const {'listening', 'thinking', 'speaking'}.contains(state)) {
          if (!suspended && sessionId != null && !_playing && _queue.isEmpty) {
            final mapped = _phaseForState(state);
            if (mapped != null) phase = mapped;
          }
          if (state != 'listening') _cancelCaptureForServerSpeech();
          _notify();
        }
        return;
      case 'input.transcript':
        final text = data['text'];
        if (text is String && text.trim().isNotEmpty) {
          final trimmed = text.trim();
          final last = _lines.isEmpty ? null : _lines.last;
          if (last != null && last.local && last.isUser && last.text.trim() == trimmed) {
            last.local = false;
          } else {
            _lines.add(TalkLine(role: 'user', text: trimmed));
          }
          _notify();
        }
        return;
      case 'response.started':
        final id = data['response_id'];
        if (id is String && id.isNotEmpty && !_ignoredResponses.contains(id)) {
          _ensureResponse(id);
          activeResponseId = id;
          _cancelCaptureForServerSpeech();
          if (!suspended) phase = TalkPhase.thinking;
          _notify();
        }
        return;
      case 'response.text':
        final id = data['response_id'];
        final text = data['text'];
        if (id is String && text is String) {
          if (_ignoredResponses.contains(id) || _finalizedResponses.contains(id)) return;
          final response = _ensureResponse(id);
          response.delta.write(text);
          response.refreshLine();
          activeResponseId = id;
          _notify();
        }
        return;
      case 'response.audio':
        _onAudio(data);
        return;
      case 'response.done':
        _onResponseDone(data);
        return;
      case 'scenario.progress':
        final goals = data['completed_goals'];
        if (goals is List) {
          _completedGoals
            ..clear()
            ..addAll(goals.whereType<num>().map((e) => e.toInt()).where((e) => e >= 0));
          _notify();
        }
        return;
      case 'error':
        final message = data['message'];
        error = message is String && message.trim().isNotEmpty
            ? message.trim()
            : '对话服务返回了一个错误。';
        _notify();
        return;
      case 'session.ended':
        final id = data['session_id'];
        if (id is String && id.isNotEmpty) sessionId = id;
        _closing = true;
        _cancelResumeTimer();
        unawaited(_stopCapture(sendCancel: false));
        _queue.clear();
        unawaited(_player.stop().catchError((Object _) {}));
        phase = TalkPhase.ended;
        final ended = _ended;
        if (ended != null && !ended.isCompleted) ended.complete();
        _notify();
        return;
      case 'pong':
        return;
    }
  }

  TalkPhase? _phaseForState(String state) {
    switch (state) {
      case 'listening':
        return TalkPhase.listening;
      case 'thinking':
        return TalkPhase.thinking;
      case 'speaking':
        return TalkPhase.speaking;
    }
    return null;
  }

  _Response _ensureResponse(String id) {
    return _responses.putIfAbsent(id, () {
      final response = _Response(id);
      final line = TalkLine(role: 'assistant', text: '', streaming: true);
      response.line = line;
      _lines.add(line);
      return response;
    });
  }

  void _onAudio(Map<String, dynamic> data) {
    final id = data['response_id'];
    final sequence = data['sequence'];
    final encoded = data['audio'];
    if (id is! String || sequence is! num || encoded is! String) return;
    if (_ignoredResponses.contains(id) || _finalizedResponses.contains(id)) return;
    Uint8List wav;
    try {
      wav = base64Decode(encoded);
    } catch (_) {
      error = '收到无法解码的音频片段。';
      _notify();
      return;
    }
    final response = _ensureResponse(id);
    final phrase = data['text'];
    if (phrase is String && phrase.trim().isNotEmpty) {
      final text = phrase.trim();
      if (!response.phrases.contains(text)) response.phrases.add(text);
      response.refreshLine();
    }
    _cancelCaptureForServerSpeech();
    _queue.add(_Segment(id, sequence.toInt(), wav, phrase is String ? phrase.trim() : ''));
    activeResponseId = id;
    _notify();
    unawaited(_drain());
  }

  void _onResponseDone(Map<String, dynamic> data) {
    final id = data['response_id'];
    final status = data['status'];
    if (id is! String) return;
    final response = _responses[id];
    if (response == null) return;
    response.done = true;
    response.status = status is String ? status : 'completed';
    response.refreshLine();
    if (response.status != 'completed') {
      _ignoredResponses.add(id);
      _queue.removeWhere((segment) => segment.responseId == id);
      if (activeResponseId == id) {
        unawaited(_stopPlayback());
      }
    }
    _finishIfReady();
    _notify();
  }

  void _finishIfReady() {
    if (_disposed) return;
    final id = activeResponseId;
    if (id == null) return;
    final response = _responses[id];
    if (response == null || !response.done) return;
    if (_playing) return;
    if (_queue.any((segment) => segment.responseId == id)) return;
    _finalize(response);
  }

  void _finalize(_Response response) {
    if (_finalizedResponses.contains(response.id)) return;
    _finalizedResponses.add(response.id);
    final interrupted = response.status != 'completed';
    final text = interrupted ? response.playedPhrases.join(' ').trim() : response.displayText;
    final line = response.line;
    if (line != null) {
      if (text.isEmpty) {
        _lines.remove(line);
      } else {
        line.text = text;
        line.streaming = false;
        line.interrupted = interrupted;
      }
    }
    if (response.status == 'failed' && error == null) {
      error = '本轮回应没有完成，请再试一次。';
    }
    if (activeResponseId == response.id) activeResponseId = null;
    _responses.remove(response.id);
    if (!suspended && !_closing && phase != TalkPhase.ended) {
      phase = TalkPhase.listening;
      _maybeResumeMic();
    }
    _notify();
  }

  Future<void> _drain() async {
    if (_playing || _disposed) return;
    if (_queue.isEmpty) {
      _finishIfReady();
      return;
    }
    _playing = true;
    while (_queue.isNotEmpty && !_disposed) {
      final segment = _queue.removeAt(0);
      if (_ignoredResponses.contains(segment.responseId) ||
          _finalizedResponses.contains(segment.responseId)) {
        continue;
      }
      final response = _responses[segment.responseId];
      if (response == null || (response.done && response.status != 'completed')) continue;
      if (!suspended && phase != TalkPhase.ended) {
        phase = TalkPhase.speaking;
        _notify();
      }
      final completed = Completer<void>();
      _segmentDone = completed;
      try {
        await _player.play(segment.wav);
        await completed.future.timeout(const Duration(seconds: 45));
      } on TimeoutException {
        error = '音频播放超时，本轮已停止。';
        await interrupt();
        continue;
      } catch (_) {
        error = '音频播放失败，本轮已停止。';
        await interrupt();
        continue;
      } finally {
        if (identical(_segmentDone, completed)) _segmentDone = null;
      }
      if (_disposed ||
          _ignoredResponses.contains(segment.responseId) ||
          _finalizedResponses.contains(segment.responseId)) {
        continue;
      }
      final current = _responses[segment.responseId];
      if (segment.text.isNotEmpty) current?.playedPhrases.add(segment.text);
      _sendJson({
        'type': 'playback.ack',
        'response_id': segment.responseId,
        'sequence': segment.sequence,
      });
    }
    if (_disposed) return;
    _playing = false;
    _finishIfReady();
  }

  Future<void> _stopPlayback() async {
    final pending = _segmentDone;
    try {
      await _player.stop();
    } catch (_) {
    } finally {
      if (pending != null && !pending.isCompleted) pending.complete();
    }
  }

  Future<void> interrupt() async {
    final id = activeResponseId;
    if (id == null) {
      if (_playing || _queue.isNotEmpty) {
        _queue.clear();
        await _stopPlayback();
      }
      return;
    }
    if (!_ignoredResponses.contains(id)) {
      _ignoredResponses.add(id);
      final response = _responses[id];
      if (response != null) {
        _sendJson({'type': 'response.cancel', 'response_id': id});
      }
      if (response != null) {
        response.done = true;
        response.status = 'cancelled';
        response.refreshLine();
      }
    }
    _queue.removeWhere((segment) => segment.responseId == id);
    _cancelResumeTimer();
    await _stopPlayback();
    _finishIfReady();
    _notify();
  }

  Future<bool> sendText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || text.length > 4000) return false;
    if (!canAcceptInput) return false;
    if (_capturing) await _stopCapture(sendCancel: true);
    if (canInterrupt) await interrupt();
    if (_disposed || _closing) return false;
    if (!_sendJson({'type': 'text.input', 'text': text})) return false;
    _lines.add(TalkLine(role: 'user', text: text, local: true));
    phase = TalkPhase.thinking;
    _notify();
    return true;
  }

  Future<bool> beginPtt() async {
    if (config.mode != TalkMode.ptt) return false;
    if (!canStartCapture) return false;
    _manualPtt = true;
    final started = await _startCapture(auto: false);
    if (started && !_manualPtt) {
      await _stopCapture(sendCancel: true);
      return false;
    }
    return started;
  }

  Future<void> endPtt() async {
    if (!_manualPtt) return;
    _manualPtt = false;
    if (!_capturing) return;
    final shouldCommit = _speechMs >= 250 && _totalMs >= 250;
    await _stopCapture(sendCancel: !shouldCommit, commit: shouldCommit);
  }

  Future<void> toggleAutoListening() async {
    if (config.mode != TalkMode.handsFree) return;
    if (_capturing) {
      autoPaused = true;
      await _stopCapture(sendCancel: true);
      _notify();
      return;
    }
    autoPaused = false;
    micPermissionDenied = false;
    micError = null;
    await _maybeResumeMic(force: true);
  }

  Future<void> retryMicrophone() async {
    micPermissionDenied = false;
    micUnsupported = false;
    micError = null;
    autoPaused = false;
    await _maybeResumeMic(force: true);
  }

  Future<void> _maybeResumeMic({bool force = false, int delay = 260}) async {
    if (_disposed || _closing || suspended) return;
    if (config.mode != TalkMode.handsFree) return;
    if (autoPaused && !force) return;
    if (!canStartCapture) return;
    if (micPermissionDenied && !force) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(Duration(milliseconds: delay), () {
      if (canStartCapture &&
          !suspended &&
          !_closing &&
          config.mode == TalkMode.handsFree &&
          (!autoPaused || force)) {
        unawaited(_startCapture(auto: true));
      }
    });
  }

  Future<bool> _startCapture({required bool auto}) async {
    if (_capturing || _startingCapture || _disposed || _closing) return false;
    _startingCapture = true;
    _captureEpoch++;
    final epoch = _captureEpoch;
    try {
      final supported = await _mic.isSupported();
      if (epoch != _captureEpoch || _disposed || _closing) return false;
      if (!supported) {
        micUnsupported = true;
        micError = '当前浏览器或设备不支持 PCM16 录音。你仍可以使用文字继续练习。';
        _notify();
        return false;
      }
      final granted = await _mic.ensurePermission();
      if (epoch != _captureEpoch || _disposed || _closing) return false;
      if (!granted) {
        micPermissionDenied = true;
        autoPaused = true;
        micError = '麦克风权限被拒绝。你仍可以使用文字继续练习，或到系统设置中允许麦克风。';
        _notify();
        return false;
      }
      if (suspended) return false;
      final stream = await _mic.start();
      if (epoch != _captureEpoch || _disposed || _closing || suspended) {
        await _mic.stop().catchError((Object _) {});
        return false;
      }
      _capturing = true;
      _autoCapture = auto;
      if (auto) autoPaused = false;
      _resetVad();
      micError = null;
      micPermissionDenied = false;
      phase = TalkPhase.listening;
      _notify();
      _micSub = stream.listen(
        (chunk) => _onMicChunk(chunk, epoch),
        onError: (Object _) => _onMicError(epoch),
        onDone: () => _onMicDone(epoch),
        cancelOnError: false,
      );
      return true;
    } catch (_) {
      micPermissionDenied = true;
      autoPaused = true;
      micError = '无法开始录音。Web 端需要 HTTPS 或 localhost；你仍可以使用文字继续练习。';
      _notify();
      return false;
    } finally {
      _startingCapture = false;
    }
  }

  void _cancelCaptureForServerSpeech() {
    if (_startingCapture) _captureEpoch++;
    if (_capturing) {
      _manualPtt = false;
      unawaited(_stopCapture(sendCancel: true));
    }
  }

  void _resetVad() {
    _speechStarted = false;
    _noiseFloor = 0;
    _calibrationChunks = 0;
    _calibrationMs = 0;
    _speechMs = 0;
    _silenceMs = 0;
    _totalMs = 0;
    _preRoll.clear();
    _preRollBytes = 0;
  }

  void _onMicChunk(Uint8List chunk, int epoch) {
    if (epoch != _captureEpoch || !_capturing || _disposed || _closing) return;
    if (chunk.isEmpty) return;
    final durationMs = chunk.length / (16000 * 2) * 1000;
    final rms = pcm16Rms(chunk);
    final normalized = (rms / 7500).clamp(0.0, 1.0);
    micLevel = (micLevel * 0.55 + normalized * 0.45).clamp(0.0, 1.0);
    _totalMs += durationMs;

    if (!_autoCapture) {
      _speechMs += durationMs;
      _sendBinary(chunk);
      if (_totalMs >= 60000) {
        unawaited(_stopCapture(sendCancel: false, commit: true));
      } else {
        _notify();
      }
      return;
    }

    if (_calibrationMs < 500) {
      _calibrationMs += durationMs;
      _noiseFloor += rms;
      _calibrationChunks++;
      _appendPreRoll(chunk);
      _notify();
      return;
    }
    final baseline = _noiseFloor / (_calibrationChunks == 0 ? 1 : _calibrationChunks);
    final threshold = (baseline * 2.7).clamp(550.0, 3800.0).toDouble();

    if (!_speechStarted) {
      if (rms >= threshold) {
        _speechStarted = true;
        _speechMs = durationMs;
        _silenceMs = 0;
        for (final buffered in _preRoll) {
          _sendBinary(buffered);
        }
        _preRoll.clear();
        _preRollBytes = 0;
        _sendBinary(chunk);
      } else {
        _appendPreRoll(chunk);
      }
      _notify();
      return;
    }

    _speechMs += durationMs;
    _sendBinary(chunk);
    if (rms < threshold * 0.82) {
      _silenceMs += durationMs;
    } else {
      _silenceMs = 0;
    }
    if (_speechMs >= 60000) {
      unawaited(_stopCapture(sendCancel: false, commit: true));
    } else if (_silenceMs >= 950) {
      unawaited(_stopCapture(sendCancel: false, commit: true));
    } else {
      _notify();
    }
  }

  void _appendPreRoll(Uint8List chunk) {
    _preRoll.add(chunk);
    _preRollBytes += chunk.length;
    const maxBytes = 16000 * 2 * 200 ~/ 1000;
    while (_preRollBytes > maxBytes && _preRoll.length > 1) {
      _preRollBytes -= _preRoll.removeAt(0).length;
    }
  }

  void _onMicError(int epoch) {
    if (epoch != _captureEpoch) return;
    micError = '麦克风录音中断。请重试，或使用文字继续。';
    unawaited(_stopCapture(sendCancel: true));
  }

  void _onMicDone(int epoch) {
    if (epoch != _captureEpoch) return;
    _capturing = false;
    micLevel = 0;
    _notify();
  }

  Future<void> _stopCapture({
    required bool sendCancel,
    bool commit = false,
  }) async {
    if (!_capturing) {
      if (commit && canAcceptInput) {
        _sendJson({'type': 'input.commit'});
        phase = TalkPhase.thinking;
        _notify();
      }
      return;
    }
    _capturing = false;
    _captureEpoch++;
    final sub = _micSub;
    _micSub = null;
    await sub?.cancel();
    try {
      await _mic.stop();
    } catch (_) {}
    micLevel = 0;
    _preRoll.clear();
    _preRollBytes = 0;
    if (commit && canAcceptInput) {
      _sendRaw({'type': 'input.commit'});
      phase = TalkPhase.thinking;
    } else if (sendCancel) {
      _sendRaw({'type': 'input.cancel'});
    }
    _notify();
  }

  Future<void> suspend() async {
    if (_disposed) return;
    suspended = true;
    autoPaused = true;
    _cancelResumeTimer();
    await _stopCapture(sendCancel: true);
    if (activeResponseId != null || _playing || _queue.isNotEmpty) {
      await interrupt();
    }
    if (!_disposed && phase != TalkPhase.ended) {
      phase = TalkPhase.paused;
      _notify();
    }
  }

  void resumeFromBackground() {
    if (_disposed) return;
    suspended = false;
    if (phase == TalkPhase.paused) {
      phase = sessionId == null ? TalkPhase.connecting : TalkPhase.listening;
      _notify();
    }
  }

  Future<void> end() async {
    if (_disposed || _closing) return;
    _closing = true;
    autoPaused = true;
    _cancelResumeTimer();
    await _stopCapture(sendCancel: true);
    _queue.clear();
    _ignoredResponses.addAll(_responses.keys);
    await _stopPlayback();
    final socket = _socket;
    if (socket == null) {
      phase = TalkPhase.ended;
      _notify();
      return;
    }
    _ended = Completer<void>();
    try {
      socket.sendJson(jsonEncode({'type': 'session.end'}));
    } catch (_) {}
    try {
      await _ended!.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // The local session still ends; the server closes on its own timeout.
    }
    phase = TalkPhase.ended;
    _notify();
    await _teardownSocket();
  }

  void _onSocketLost(int epoch, String message) {
    if (epoch != _epoch || _disposed || _closing) return;
    _cancelResumeTimer();
    unawaited(_stopCapture(sendCancel: false));
    _queue.clear();
    _ignoredResponses.addAll(_responses.keys);
    unawaited(_stopPlayback());
    activeResponseId = null;
    _socket = null;
    if (phase != TalkPhase.ended) {
      error = message;
      phase = TalkPhase.disconnected;
      _notify();
    }
  }

  bool _sendJson(Map<String, dynamic> data) {
    if (_closing) return false;
    return _sendRaw(data);
  }

  bool _sendRaw(Map<String, dynamic> data) {
    final socket = _socket;
    if (socket == null || _disposed) return false;
    try {
      socket.sendJson(jsonEncode(data));
      return true;
    } catch (_) {
      error = '消息未能发送，请检查连接。';
      _notify();
      return false;
    }
  }

  void _sendBinary(Uint8List bytes) {
    final socket = _socket;
    if (socket == null || _disposed || _closing || suspended) return;
    try {
      socket.sendBinary(bytes);
    } catch (_) {}
  }

  void _cancelResumeTimer() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void clearError() {
    if (error == null) return;
    error = null;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closing = true;
    _epoch++;
    _captureEpoch++;
    _startTimer?.cancel();
    _cancelResumeTimer();
    final socket = _socket;
    if (socket != null && sessionId != null && phase != TalkPhase.ended) {
      try {
        socket.sendJson(jsonEncode({'type': 'session.end'}));
      } catch (_) {}
    }
    unawaited(_socketSub?.cancel());
    unawaited(socket?.close());
    unawaited(_micSub?.cancel());
    unawaited(_mic.stop().catchError((Object _) {}));
    unawaited(_mic.dispose().catchError((Object _) {}));
    unawaited(_stopPlayback());
    unawaited(_player.dispose().catchError((Object _) {}));
    unawaited(_audioSub.cancel());
    _responses.clear();
    _queue.clear();
    super.dispose();
  }
}

double pcm16Rms(Uint8List bytes) {
  if (bytes.length < 2) return 0;
  final data = ByteData.sublistView(bytes);
  var sum = 0.0;
  var count = 0;
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    final sample = data.getInt16(i, Endian.little);
    sum += sample * sample;
    count++;
  }
  if (count == 0) return 0;
  return (sum / count) == 0 ? 0 : _sqrt(sum / count);
}

double _sqrt(double value) {
  if (value <= 0) return 0;
  var x = value;
  var y = (x + 1) / 2;
  for (var i = 0; i < 24 && (x - y).abs() > 0.5; i++) {
    x = y;
    y = (x + value / x) / 2;
  }
  return y;
}
