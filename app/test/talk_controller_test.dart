import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lango/data.dart';
import 'package:lango/talk/talk_controller.dart';

class FakeSocket implements TalkSocket {
  final incoming = StreamController<dynamic>();
  final sent = <Json>[];
  @override
  Stream<dynamic> get messages => incoming.stream;
  @override
  void sendJson(String text) => sent.add(Json.from(jsonDecode(text)));
  @override
  void sendBinary(Uint8List bytes) {}
  @override
  Future<void> close([int? code, String? reason]) async {
    unawaited(incoming.close());
  }

  void emit(Json event) => incoming.add(jsonEncode(event));
}

class FakeMic implements MicSource {
  bool allowed = true;
  bool stopped = false;
  final input = StreamController<Uint8List>();
  @override
  Future<bool> isSupported() async => true;
  @override
  Future<bool> ensurePermission() async => allowed;
  @override
  Future<Stream<Uint8List>> start() async => input.stream;
  @override
  Future<void> stop() async => stopped = true;
  @override
  Future<void> dispose() async {
    unawaited(input.close());
  }
}

class FakePlayer implements WavePlayer {
  final events = StreamController<void>.broadcast();
  int plays = 0;
  bool fail = false;
  @override
  Stream<void> get completed => events.stream;
  @override
  Future<void> play(Uint8List wav) async {
    plays++;
    if (fail) throw StateError('synthetic playback failure');
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    unawaited(events.close());
  }

  void finish() => events.add(null);
}

Future<void> flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeSocket socket;
  late FakeMic mic;
  late FakePlayer player;
  late TalkController talk;
  late ApiClient api;

  Future<void> connect({String? resume}) async {
    socket = FakeSocket();
    mic = FakeMic();
    player = FakePlayer();
    api =
        ApiClient(
            client: MockClient((request) async {
              expect(request.url.path, '/api/v1/talk/ticket');
              return http.Response('{"ticket":"single-use-ticket"}', 200);
            }),
          )
          ..server = 'https://lango.example.com'
          ..tokens = {'access_token': 'private-access'};
    talk = TalkController(
      api: api,
      config: TalkControllerConfig(mode: TalkMode.ptt, sessionId: resume),
      mic: mic,
      player: player,
      socketFactory: (uri) async {
        expect(uri.scheme, 'wss');
        expect(uri.queryParameters, {'ticket': 'single-use-ticket'});
        expect(uri.toString(), isNot(contains('private-access')));
        return socket;
      },
    );
    await talk.start();
    socket.emit({
      'type': 'session.created',
      'session_id': resume ?? 'session-one',
    });
    await flush();
  }

  void audio(int sequence, {String id = 'response-one'}) {
    socket.emit({
      'type': 'response.audio',
      'response_id': id,
      'sequence': sequence,
      'text': 'Phrase $sequence.',
      'audio': base64Encode([1, 2]),
      'mime_type': 'audio/wav',
    });
  }

  void started() =>
      socket.emit({'type': 'response.started', 'response_id': 'response-one'});
  void done() => socket.emit({
    'type': 'response.done',
    'response_id': 'response-one',
    'status': 'completed',
  });
  List<Json> acknowledgements() =>
      socket.sent.where((e) => e['type'] == 'playback.ack').toList();

  tearDown(() async {
    talk.dispose();
    api.client.close();
    await flush();
  });

  test(
    'History resume sends the original session ID on first connection',
    () async {
      await connect(resume: 'owned-history-id');
      expect(socket.sent.first, {
        'type': 'session.start',
        'mode': 'ptt',
        'session_id': 'owned-history-id',
      });
      expect(player.plays, 0);
    },
  );

  test('Generation completion does not acknowledge unplayed audio', () async {
    await connect();
    started();
    audio(0);
    audio(1);
    done();
    await flush();
    expect(player.plays, 1);
    expect(talk.phase, TalkPhase.speaking);
    expect(acknowledgements(), isEmpty);
    player.finish();
    await flush();
    expect(player.plays, 2);
    expect(acknowledgements().map((e) => e['sequence']), [0]);
    expect(talk.phase, TalkPhase.speaking);
    player.finish();
    await flush();
    expect(acknowledgements().map((e) => e['sequence']), [0, 1]);
    expect(talk.phase, TalkPhase.listening);
    expect(talk.isPlaying, isFalse);
  });

  test(
    'Interrupt after generation completes releases playback and ignores late frames',
    () async {
      await connect();
      started();
      audio(0);
      audio(1);
      done();
      await flush();
      await talk.interrupt();
      await flush();
      expect(
        socket.sent.where((e) => e['type'] == 'response.cancel'),
        hasLength(1),
      );
      expect(talk.isPlaying, isFalse);
      expect(talk.canStartCapture, isTrue);
      audio(2);
      player.finish();
      await flush();
      expect(player.plays, 1);
      expect(acknowledgements(), isEmpty);
      expect(talk.lines, isEmpty);
    },
  );

  test('Interrupted captions retain only completely played phrases', () async {
    await connect();
    started();
    audio(0);
    audio(1);
    done();
    await flush();
    player.finish();
    await flush();
    await talk.interrupt();
    await flush();
    expect(talk.lines.single.text, 'Phrase 0.');
    expect(talk.lines.single.interrupted, isTrue);
    expect(acknowledgements().map((e) => e['sequence']), [0]);
  });

  test(
    'Playback failure cancels the response instead of acknowledging later segments',
    () async {
      await connect();
      player.fail = true;
      started();
      audio(0);
      audio(1);
      done();
      await flush();
      expect(player.plays, 1);
      expect(talk.error, contains('音频播放失败'));
      expect(talk.isPlaying, isFalse);
      expect(acknowledgements(), isEmpty);
      expect(
        socket.sent.where((e) => e['type'] == 'response.cancel'),
        hasLength(1),
      );
    },
  );

  test('Microphone denial still permits typed input', () async {
    await connect();
    mic.allowed = false;
    expect(await talk.beginPtt(), isFalse);
    expect(talk.micPermissionDenied, isTrue);
    expect(await talk.sendText('Hello without a microphone'), isTrue);
    expect(socket.sent.last, {
      'type': 'text.input',
      'text': 'Hello without a microphone',
    });
  });

  test(
    'Background suspension cancels playback without a false acknowledgement',
    () async {
      await connect();
      started();
      audio(0);
      await flush();
      await talk.suspend();
      await flush();
      expect(talk.phase, TalkPhase.paused);
      expect(talk.isPlaying, isFalse);
      expect(talk.canAcceptInput, isFalse);
      expect(acknowledgements(), isEmpty);
      talk.resumeFromBackground();
      expect(talk.phase, TalkPhase.listening);
    },
  );
}
