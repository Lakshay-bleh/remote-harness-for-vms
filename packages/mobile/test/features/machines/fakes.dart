import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

/// A socket the test drives by hand.
class FakeSocket implements WebSocketChannel {
  FakeSocket(this.url, this.protocols);
  final Uri url;
  final List<String> protocols;
  final _in = StreamController<dynamic>();
  late final FakeSink _sink = FakeSink(this);
  bool closed = false;
  final sent = <dynamic>[];
  final _ready = Completer<void>();

  void open() {
    if (!_ready.isCompleted) _ready.complete();
  }

  void message(String data) => _in.add(data);
  void drop() => _in.close();

  @override
  Stream<dynamic> get stream => _in.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  Future<void> get ready => _ready.future;
  @override
  String? get protocol => 'escanor.hub.v1';
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSink implements WebSocketSink {
  FakeSink(this.socket);
  final FakeSocket socket;
  @override
  void add(dynamic data) => socket.sent.add(data);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    socket.closed = true;
  }

  @override
  Future<void> get done => Future.value();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
