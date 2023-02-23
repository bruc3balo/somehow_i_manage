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

var _log = Logger();

void _logI(String message, {dynamic error, Level level = Level.nothing}) {
  switch (level) {
    case Level.verbose:
      _log.v(message, [null, error]);
      break;
    case Level.debug:
      _log.d(message, [null, error]);
      break;
    case Level.nothing:
    case Level.info:
      _log.i(message, [null, error]);
      break;
    case Level.warning:
      _log.w(message, [null, error]);
      break;
    case Level.error:
      _log.e(message, [null, error]);
      break;
    case Level.wtf:
      _log.wtf(message, [null, error]);
      break;
  }
}

class _StreamKit<T> {
  final String debugName;
  final BehaviorSubject<T> _subject = BehaviorSubject();
  late final StreamSubscription<T> subscription;
  final BehaviorSubject<IState> _state = BehaviorSubject()..add(IState.listen);
  final Function(IState state)? onStateChange;

  _StreamKit(
      {ReceivePort? receivePort,
      Function(T message)? onListen,
      required this.debugName,
      this.onStateChange,
      Function()? onPause,
      Function()? onResume,
      Function()? onCancel}) {
    receivePort
        ?.asBroadcastStream()
        .takeWhile((e) => e is T)
        .cast<T>()
        .listen((T message) {
      add(message);
    });

    subscription = _subject.stream.listen((T data) {});
    _state.stream.listen(_onStateChange);

    subscription.onData((T data) {
      onListen?.call(data);
    });
  }

  IState get state => _state.value;

  ValueStream<T> get stream => _subject.stream;

  Future<List<T>> get values => _subject.toList();

  void _onStateChange(IState iState) {
    print("$debugName : State change $iState");
    onStateChange?.call(iState);
    switch (iState) {
      case IState.listen:
        if (subscription.isPaused) {
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
        break;
      case IState.cancel:
        throw StreamKitCancelledException(
            "$debugName : Stream has been cancelled");
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

  Future<List<T>> get list async => await _subject.toList();

  Future<bool> resume() async {
    switch (state) {
      case IState.listen:
        return false;

      case IState.cancel:
        throw StreamKitCancelledException(
            "$debugName stream already cancelled");
      case IState.pause:
        _state.add(IState.listen);
        return true;
    }
  }

  Future<bool> pause() async {
    switch (state) {
      case IState.listen:
        _state.add(IState.pause);
        return true;
      case IState.cancel:
        throw StreamKitCancelledException(
            "$debugName stream already cancelled");

      case IState.pause:
        return false;
    }
  }

  Future<void> clear() async {
    await _subject.drain();
  }

  Future<void> dispose() async {
    if (state == IState.cancel) {
      throw StreamKitCancelledException("$debugName stream already cancelled");
    }
    _state.add(IState.cancel);
  }

  Future<void> _dispose() async {
    await _subject.close();
    await stream.drain();
    await subscription.cancel();
  }
}

///Work
class IWork<T> {
  IWork(this.work,
      {this.name = "anonymous", this.onWorkStatusNotifier, this.onResult});

  final String name;
  final Future<T> Function() work;
  final Function(IWorkStatus workStatus)? onWorkStatusNotifier;
  final Function(T? result)? onResult;

  //status

  IWorkStatus _workStatus = IWorkStatus.undone;

  IWorkStatus get status => _workStatus;

  void setStatus(IWorkStatus status, {T? result}) {
    _workStatus = status;
    onWorkStatusNotifier?.call(status);
    if (status == IWorkStatus.done) {
      onResult?.call(result);
    }
  }

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

  static IMessage<IState> _cancel(
      {required String name, required SendPort from, required SendPort to}) {
    return IWorkerMessageImpl<IState>(
        info: "Stopping worker $name",
        IState.cancel,
        from: from,
        to: to,
        name: name);
  }

  static IMessage<IState> _pause(
      {required String name, required SendPort from, required SendPort to}) {
    return IWorkerMessageImpl<IState>(
        info: "Pausing worker $name",
        IState.pause,
        from: from,
        to: to,
        name: name);
  }

  static IMessage<IState> _resume(
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
    required Level logLevel,
  }) {
    _logLevel = logLevel;
    _managerReceivePort = ReceivePort(name);
    _errorReceivePort = ReceivePort("$name:error");
    _stateReceivePort = ReceivePort("$name:state");

    _errorsKit = _StreamKit(
        receivePort: _errorReceivePort,
        onListen: (e) => _onErrorMessage(e),
        debugName: 'Manager : Error');

    _allMessagesKit = _StreamKit(
        receivePort: _managerReceivePort,
        onListen: (m) => _onReceiveMessage(m),
        debugName: 'Manager : Message');

    _stateKit = _StreamKit(
        receivePort: _stateReceivePort,
        onListen: (s) => _onStateMessage(s),
        debugName: 'Manager : State');

    _init();
  }

  //Meta IManager
  final String name;
  late final Level _logLevel;
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
  static IManager create({String? name, Level? logLevel}) {
    return IManagerImpl(name: name, logLevel: logLevel);
  }

  //Workers
  Future<IWorker> addWorker(String name,
      {dynamic Function(IMessage<dynamic>, IWorker worker)? onReceiveMessage,
      dynamic Function(IWorker worker)? onCancelMessageSubscription,
      dynamic Function(IWorker worker)? onPauseMessageSubscription,
      dynamic Function(IWorker worker)? onResumeMessageSubscription,
      dynamic Function(IState state, IWorker worker)?
          onWorkerStateChange}) async {
    if (isWorkerPresent(name)) {
      throw IWorkerPresentException("Worker already present $name");
    }
    IWorker isoWorker = await IWorker._create(name, managerSendPort,
        _errorReceivePort.sendPort, _stateReceivePort.sendPort,
        onReceiveMessage: onReceiveMessage,
        logging: _logLevel,
        onWorkerStateChange: onWorkerStateChange);
    _workers.putIfAbsent(name, () => isoWorker);
    return isoWorker;
  }

  bool isWorkerPresent(String name) {
    return getWorker(name) != null;
  }

  IWorker? getWorker(String name) {
    return _workers[name];
  }

  void killAllWorker() {
    List<IWorker> list = List.from(_workers.values.toList());
    for (IWorker w in list) {
      killWorker(w);
    }
  }

  ///Listener
  //message
  void _removeMessageListener() {
    _allMessagesKit.dispose();
  }

  void _onReceiveMessage(IMessage message) {
    _logI(message.info ?? "Message $name");
  }

  //error
  void _removeErrorListener() {
    _errorsKit.dispose();
  }

  void _onErrorMessage(IMessage message) {
    _logI(message.info ?? "Error $name", level: Level.error);
  }

  //stateStreamKitCancelledException
  void _removeStateListener() {
    _stateKit.dispose();
  }

  void _onStateMessage(IMessage<IState> message) {
    String w = message.name;
    print("======== $w ========");
    IWorker? worker = getWorker(w);
    if (worker == null) {
      _logI("Worker not found");
      return;
    }

    switch (message.state) {
      case IState.listen:
        worker.resume();
        break;
      case IState.cancel:
        killWorker(worker);
        break;
      case IState.pause:
        worker.pause();
        break;
    }
  }

  void killWorker(IWorker worker) {
    worker.dispose();
    _workers.remove(worker.name);
    _logI("Worker ${worker.name} killed");
  }

  @override
  String toString() => name;

  //Lifecycle
  void _init() {
    // _setLogLevel();
    if (_logLevel == Level.info) {
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
    killAllWorker();
  }
}

abstract class IWorker {
  IWorker(
      {required this.name,
      required this.managerSendPort,
      required this.errorSendPort,
      required this.stateSendPort,
      required this.onReceiveMessage,
      required Level logging,
      dynamic Function(IWorker worker)? onCancelMessageSubscription,
      dynamic Function(IWorker worker)? onPauseMessageSubscription,
      dynamic Function(IWorker worker)? onResumeMessageSubscription,
      this.onWorkerStateChange})
      : _logging = logging {
    try {
      workerReceivePort = ReceivePort(name);

      _workerMessagesKit = _StreamKit(
          receivePort: workerReceivePort,
          onListen: _onReceiveMessage,
          onStateChange: _informManagerOfStateChange,
          debugName: 'IWorker : Message');

      _workKit = _StreamKit<IWork>(
          debugName: "IWorker : Work",
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

  //Create Worker
  static Future<IWorker> _create(String name, SendPort managerSendPort,
      SendPort errorSendPort, SendPort stateSendPort,
      {required Level logging,
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
  final Level _logging;
  late final ReceivePort workerReceivePort;
  late final SendPort errorSendPort;
  late final SendPort stateSendPort;

  SendPort get workerSendPort => workerReceivePort.sendPort;
  final SendPort managerSendPort;

  //Messaging
  late final _StreamKit<IMessage<dynamic>> _workerMessagesKit;
  IState get messageState => _workerMessagesKit.state;

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
        stateSendPort.send(IMessage._resume(
            name: name, from: workerSendPort, to: stateSendPort));
        break;
      case IState.cancel:
        stateSendPort.send(IMessage._cancel(
            name: name, from: workerSendPort, to: stateSendPort));
        break;
      case IState.pause:
        stateSendPort.send(IMessage._pause(
            name: name, from: workerSendPort, to: stateSendPort));
        break;
    }
  }

  //work
  Future<void> _doWork(IWork work) async {
    Isolate.spawn<IWork>((work) {
      _logI("Starting work ${work.name}");
      work.setStatus(IWorkStatus.active);
      work.work.call().then((result) {
        _logI("Finished work ${work.name}");
        work.setStatus(IWorkStatus.done, result: result);
      }).catchError((e, trace) {
        work.setStatus(IWorkStatus.failed);
        _logI("Failed work ${work.name}", error: trace);
      });
    }, work);
  }

  void _removeWorkListener() {
    _workKit.dispose();
  }

  void addWork<T>(Future<T> Function() work,
      {Function(IWorkStatus workStatus)? onWorkStatusNotifier,
      Function(T? result)? onResult}) {
    IWork<T> newWork = IWork<T>(work,
        onWorkStatusNotifier: onWorkStatusNotifier, onResult: onResult);
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
        IMessage<IState> message = IMessage._resume(
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
    _logI("$name disposing");
  }
}

abstract class IException {
  final String message;
  final dynamic trace;

  IException(this.message, {this.trace});

  @override
  String toString() => message;
}
