/// Support for doing something awesome.
///
/// More dartdocs go here.
library somehow_i_manage;

export 'src/somehow_i_manage_base.dart';
export 'package:logger/logger.dart';

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'package:somehow_i_manage/somehow_i_manage.dart';
import 'package:rxdart/rxdart.dart';

import 'iso_implementation.dart';

void _logI(String message, bool logging,
    {dynamic error, Level level = Level.nothing}) {
  var log = Logger();

  switch (level) {
    case Level.verbose:
      log.v(message, error);
      break;
    case Level.debug:
      log.d(message, error);
      break;
    case Level.nothing:
    case Level.info:
      log.i(message, error);
      break;
    case Level.warning:
      log.w(message, error);
      break;
    case Level.error:
      log.e(message, error);
      break;
    case Level.wtf:
      log.wtf(message, error);
      break;
  }
}

class _StreamKit<T> {
  final BehaviorSubject<T> _subject = BehaviorSubject();
  late final StreamSubscription<T> subscription;
  final BehaviorSubject<IState> _state = BehaviorSubject()..add(IState.listen);
  final Function(IState state)? onStateChange;

  _StreamKit(
      {ReceivePort? receivePort,
      Function(T message)? onListen,
      this.onStateChange,
      Function()? onPause,
      Function()? onResume,
      Function()? onCancel}) {
    receivePort
        ?.asBroadcastStream()
        .takeWhile((e) => e is T)
        .cast<T>()
        .listen((T message) {
      print("The message is $message");
      add(message);
    });

    subscription = _subject.stream
        .listen((event) => {print(event.runtimeType), onListen?.call(event)});
    _state.stream.listen(_onStateChange);
  }

  IState get state => _state.value;

  ValueStream<T> get stream => _subject.stream;

  Future<List<T>> get values => _subject.toList();

  void _onStateChange(IState iState) {
    onStateChange?.call(iState);
    switch (iState) {
      case IState.listen:
        if (!subscription.isPaused) {
          subscription.resume();
        }
        break;
      case IState.cancel:
        _dispose();
        break;
      case IState.pause:
        if (!subscription.isPaused) {
          subscription.pause();
        }
        break;
    }
  }

  bool add(T t) {
    switch (state) {
      case IState.listen:
        // TODO: Handle this case.
        break;
      case IState.cancel:
        throw Exception("Stream has been cancelled");
      case IState.pause:
        return false;
    }

    if (_subject.isClosed) {
      return false;
    }

    _subject.add(t);
    return true;
  }

  T? get value => _subject.hasValue ? _subject.value : null;

  Future<void> resume() async {
    _state.add(IState.listen);
  }

  Future<void> pause() async {
    _state.add(IState.pause);
  }

  Future<void> clear() async {
    await _subject.drain();
  }

  Future<void> dispose() async {
    _state.add(IState.cancel);
  }

  Future<void> _dispose() async {
    await _subject.close();
    await stream.drain();
    await subscription.cancel();
  }
}

///Work
class IWork {
  IWork(this.work, {this.name = "anonymous", this.onWorkStatusNotifier}) {
    _workStatusKit.stream.listen((status) {
      onWorkStatusNotifier?.call(status);
    });
  }

  final String name;
  final Future<dynamic> Function() work;
  final Function(IWorkStatus workStatus)? onWorkStatusNotifier;

  //status
  final _StreamKit<IWorkStatus> _workStatusKit = _StreamKit()
    ..add(IWorkStatus.undone);

  IWorkStatus get status => _workStatusKit.value ?? IWorkStatus.undone;

  void setStatus(IWorkStatus status) => _workStatusKit.add(status);

  @override
  String toString() => "{name : $name, status : $status}";
}

///Classes
abstract class IMessage<T> {
  const IMessage(this.state,
      {this.info,
      this.data,
      this.tag,
      required this.name,
      required this.from,
      required this.to});

  final String name;
  final String? info;
  final String? tag;
  final T? data;
  final IState state;
  final SendPort from;
  final SendPort to;

  @override
  String toString() =>
      "{name: $name, info: $info, tag:$tag state : $state, data: $data";

  Map<String, dynamic> toMap() => {
        "name": name,
        "info": info,
        "tag": tag,
        "data": data,
        "state": state.name
      };

  static IMessage<T> createDataMessage<T>(
      {String? info,
      String? tag,
      T? data,
      required String name,
      required SendPort from,
      required SendPort to}) {
    return IWorkerMessageImpl(
        info: info ?? "Sending data message",
        IState.listen,
        data: data,
        tag: tag,
        from: from,
        to: to,
        name: name);
  }

  static IMessage<T> _error<T>({
    String? info,
    T? data,
    required SendPort from,
    required SendPort to,
    required String name,
  }) {
    return IWorkerMessageImpl(
        info: info ?? "Error",
        IState.listen,
        data: data,
        from: from,
        to: to,
        name: name);
  }

  static IMessage<T> _cancel<T>(
      {required String name,
      T? data,
      required SendPort from,
      required SendPort to}) {
    return IWorkerMessageImpl<T>(
        info: "Stopping worker $name",
        IState.cancel,
        data: data,
        from: from,
        to: to,
        name: name);
  }

  static IMessage<T> _pause<T>(
      {required String name, required SendPort from, required SendPort to}) {
    return IWorkerMessageImpl(
        info: "Pausing worker $name",
        IState.pause,
        from: from,
        to: to,
        name: name);
  }

  static IMessage<T> _resume<T>(
      {required String name, required SendPort from, required SendPort to}) {
    return IWorkerMessageImpl(
        info: "Resuming worker $name",
        IState.listen,
        from: from,
        to: to,
        name: name);
  }
}

abstract class IManager {
  IManager({
    required this.name,
    required bool log,
  }) {
    _logging = log;
    _managerReceivePort = ReceivePort(name);
    _errorReceivePort = ReceivePort("$name:error");
    _stateReceivePort = ReceivePort("$name:state");

    _errorsKit = _StreamKit(
        receivePort: _errorReceivePort, onListen: (e) => _onErrorMessage(e));

    _allMessagesKit = _StreamKit(
        receivePort: _managerReceivePort,
        onListen: (m) => _onReceiveMessage(m));

    _stateKit = _StreamKit(
        receivePort: _stateReceivePort, onListen: (s) => _onStateMessage(s));

    _init();
  }

  //Meta IManager
  final String name;
  late final bool _logging;
  late final ReceivePort _managerReceivePort;
  late final ReceivePort _errorReceivePort;
  late final ReceivePort _stateReceivePort;

  SendPort get managerSendPort => _managerReceivePort.sendPort;

  //Workers
  final HashMap<String, IWorker> _workers = HashMap();

  //Messages
  late final _StreamKit<IMessage<dynamic>> _allMessagesKit;

  Stream<IMessage<dynamic>> get messageStream => _allMessagesKit.stream;

  //Errors
  late final _StreamKit<IMessage<dynamic>> _errorsKit;

  Stream<IMessage<dynamic>> get errorStream => _errorsKit.stream;

  //State
  late final _StreamKit<IMessage<IState>> _stateKit;

  Stream<IMessage<IState>> get stateStream => _stateKit.stream;

  //Create Manager
  static IManager create({String? name, bool? log}) {
    return IManagerImpl(name: name, log: log);
  }

  //Workers
  Future<IWorker> addWorker(String name,
      {dynamic Function(IMessage<dynamic>, IWorker worker)? onReceiveMessage,
      dynamic Function(IWorker worker)? onCancelMessageSubscription,
      dynamic Function(IWorker worker)? onPauseMessageSubscription,
      dynamic Function(IWorker worker)? onResumeMessageSubscription}) async {
    if (isWorkerPresent(name)) throw Exception("Worker already present");
    IWorker isoWorker = await IWorker._create(name, managerSendPort,
        _errorReceivePort.sendPort, _stateReceivePort.sendPort,
        onReceiveMessage: onReceiveMessage, logging: _logging);
    _workers.putIfAbsent(name, () => isoWorker);
    return isoWorker;
  }

  bool isWorkerPresent(String name) {
    return getWorker(name) != null;
  }

  IWorker? getWorker(String name) {
    return _workers[name];
  }

  Future<void> killAllWorker() async {
    for (IWorker w in _workers.values) {
      w.cancel(initiator: name);
      _killWorker(w);
    }
  }

  //Logging Listener
  void _setLogLevel() {
    Logger.level = _logging ? Level.warning : Level.info;
  }

  ///Listener
  //message
  void _removeMessageListener() {
    _allMessagesKit.dispose();
  }

  void _onReceiveMessage(IMessage message) {
    if (_logging) {
      _logI(message.info ?? "Message $name", _logging);
    }
  }

  //error
  void _removeErrorListener() {
    _errorsKit.dispose();
  }

  void _onErrorMessage(IMessage message) {
    _logI(message.info ?? "Error $name", _logging, level: Level.error);
  }

  //state
  void _removeStateListener() {
    _stateKit.dispose();
  }

  void _onStateMessage(IMessage message) {
    String w = message.name;
    print(w);
    IWorker? worker = getWorker(w);
    if (worker == null) {
      _logI("Worker not found", _logging);
      return;
    }

    switch (message.state) {
      case IState.listen:
        worker.resume();
        break;
      case IState.cancel:
        _killWorker(worker);
        break;
      case IState.pause:
        worker.pause();
        break;
    }
  }

  void _killWorker(IWorker worker) {
    worker.dispose();
    _workers.remove(worker);
  }

  @override
  String toString() => name;

  //Lifecycle
  void _init() {
    // _setLogLevel();
    if (_logging) {
      _allMessagesKit.add(IMessage.createDataMessage(
          name: name,
          from: managerSendPort,
          to: managerSendPort,
          data: "$name created"));
    }
  }

  Future<void> dispose() async {
    _removeMessageListener();
    _removeErrorListener();
    _removeStateListener();
    await killAllWorker();
  }
}

abstract class IWorker {
  IWorker(
      {required this.name,
      required this.managerSendPort,
      required this.errorSendPort,
      required this.stateSendPort,
      required this.onReceiveMessage,
      required this.logging,
      dynamic Function(IWorker worker)? onCancelMessageSubscription,
      dynamic Function(IWorker worker)? onPauseMessageSubscription,
      dynamic Function(IWorker worker)? onResumeMessageSubscription,
      this.onWorkerStateChange}) {
    try {
      workerReceivePort = ReceivePort(name);
      _workerMessagesKit = _StreamKit(
          receivePort: workerReceivePort,
          onListen: _onReceiveMessage,
          onStateChange: _informManagerOfStateChange);

      _workKit = _StreamKit<IWork>(
          onCancel: () => sendMessage(
              info: "$name work cancelled", sendPort: managerSendPort),
          onPause: () =>
              sendMessage(info: "$name work paused", sendPort: managerSendPort),
          onResume: () => sendMessage(
              info: "$name work resumed", sendPort: managerSendPort),
          onListen: _doWork,
          onStateChange: (iState) {
            _onStateChange(iState);
            _informManagerOfStateChange(iState);
          });

      _init();
    } catch (e, trace) {
      _sendError(info: e.toString(), data: trace);
    }
  }

  static Future<void> actualWork(dynamic p) async {
    // _workKit.stream.listen((work) {
    // _doWork(work);
    // });
    print("================");
  }

  //Create Worker
  static Future<IWorker> _create(String name, SendPort managerSendPort,
      SendPort errorSendPort, SendPort stateSendPort,
      {required bool logging,
      dynamic Function(IMessage<dynamic>, IWorker worker)? onReceiveMessage,
      dynamic Function(IWorker worker)? onCancelMessageSubscription,
      dynamic Function(IWorker worker)? onPauseMessageSubscription,
      dynamic Function(IWorker worker)? onResumeMessageSubscription,
      dynamic Function(IState state, IWorker worker)?
          onWorkerStateChange}) async {
    return IWorkerImpl(
      name: name,
      logging: logging,
      managerSendPort: managerSendPort,
      errorSendPort: errorSendPort,
      stateSendPort: stateSendPort,
      onReceiveMessage: onReceiveMessage,
      onCancelMessageSubscription: onCancelMessageSubscription,
      onPauseMessageSubscription: onPauseMessageSubscription,
      onResumeMessageSubscription: onResumeMessageSubscription,
      onWorkerStateChange: onWorkerStateChange,
    );
  }

  //IWorker meta
  final String name;
  final bool logging;
  late final ReceivePort workerReceivePort;
  late final SendPort errorSendPort;
  late final SendPort stateSendPort;

  SendPort get workerSendPort => workerReceivePort.sendPort;
  final SendPort managerSendPort;

  //Messaging
  late final _StreamKit<IMessage<dynamic>> _workerMessagesKit;

  Stream<IMessage<dynamic>> get workerMessageStream =>
      _workerMessagesKit.stream;
  final dynamic Function(IMessage<dynamic> message, IWorker worker)?
      onReceiveMessage;

  //Worker state

  IState get workerState => _workKit.state;
  dynamic Function(IState state, IWorker worker)? onWorkerStateChange;

  //work
  late final _StreamKit<IWork> _workKit;

  //isolate

  //messages
  void _onReceiveMessage(IMessage iMessage) {
    onReceiveMessage?.call(iMessage, this);
  }

  Future<void> pauseMessageListening() async {
    await _workerMessagesKit.pause();
  }

  Future<void> resumeMessageListening() async {
    await _workerMessagesKit.resume();
  }

  Future<void> cancelMessageListening() async {
    await _workerMessagesKit.dispose();
  }

  void _informManagerOfStateChange(IState iState) {
    switch (iState) {
      case IState.listen:
        managerSendPort.send(IMessage._resume(
            name: name, from: workerSendPort, to: stateSendPort));
        break;
      case IState.cancel:
        managerSendPort.send(IMessage._cancel(
            name: name, from: workerSendPort, to: stateSendPort));
        break;
      case IState.pause:
        managerSendPort.send(IMessage._pause(
            name: name, from: workerSendPort, to: stateSendPort));
        break;
    }
  }

  //work
  Future<void> _doWork(IWork work) async {
    Isolate.spawn<IWork>((work) {
      _logI("Starting work ${work.name}", logging);
      work.setStatus(IWorkStatus.active);
      work.work.call().then((_) {
        _logI("Finished work ${work.name}", logging);
        work.setStatus(IWorkStatus.done);
      }).catchError((e, trace) {
        work.setStatus(IWorkStatus.failed);
        _logI("Failed work ${work.name}", logging, error: trace);
      });
    }, work);
  }

  void _removeWorkListener() {
    _workKit.dispose();
  }

  void addWork(Future<dynamic> Function() work,
      {Function(IWorkStatus workStatus)? onWorkStatusNotifier}) {
    IWork newWork = IWork(work, onWorkStatusNotifier: onWorkStatusNotifier);
    _workKit.add(newWork);
  }

  //state

  Future<void> pause() async {
    await _workKit.pause();
  }

  Future<void> resume() async {
    await _workKit.resume();
  }

  Future<void> cancel({String initiator = "Anonymous"}) async {
    await _workKit.dispose();
  }

  //messages
  IMessage<T> sendMessage<T>(
      {String? info, T? data, String? tag, required SendPort sendPort}) {
    IMessage<T> message = IMessage.createDataMessage(
        info: info,
        data: data,
        tag: tag,
        from: workerSendPort,
        to: sendPort,
        name: name);
    sendPort.send(message);
    return message;
  }

  IMessage<T>? reply<T>({String? info, T? data, required IMessage message}) {
    IMessage<T> m = IMessage.createDataMessage(
        info: info,
        data: data,
        tag: message.tag,
        from: workerSendPort,
        to: message.from,
        name: name);
    message.from.send(m);
    return m;
  }

  IMessage<T> _sendError<T>({required String info, T? data}) {
    IMessage<T> message = IMessage._error(
        info: info,
        data: data,
        from: workerSendPort,
        to: errorSendPort,
        name: name);
    errorSendPort.send(message);
    return message;
  }

  void _onStateChange(IState iState) {
    onWorkerStateChange?.call(iState, this);

    switch (iState) {
      case IState.listen:
        IMessage<IState> message = IMessage._resume<IState>(
            name: name, from: workerSendPort, to: stateSendPort);
        stateSendPort.send(message);
        break;
      case IState.cancel:
        IMessage<IState> message = IMessage._cancel(
            name: name, from: workerSendPort, to: stateSendPort);
        stateSendPort.send(message);
        break;
      case IState.pause:
        IMessage<IState> message = IMessage._pause(
            name: name, from: workerSendPort, to: stateSendPort);
        stateSendPort.send(message);
        break;
    }
  }

  @override
  String toString() => name;

  //Lifecycle
  void _init() {
    print("Init $name worker");
  }

  void dispose() {
    _removeWorkListener();
    Isolate.exit(stateSendPort,
        sendMessage(info: "$name disposed", sendPort: managerSendPort).toMap());
  }
}
