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

import 'iso_implementation.dart';

var _log = Logger();

class _StreamKit<T> {
  late final Stream<T> _stream;
  late final StreamController<T> controller;
  late final StreamSubscription<T> subscription;

  _StreamKit(
      {Stream<T>? stream,
      Function(T message)? onListen,
      Function()? onPause,
      Function()? onResume,
      Function()? onCancel}) {

    controller = StreamController.broadcast(
      onCancel: onCancel,
    );
    _stream = stream?.asBroadcastStream() ?? controller.stream;
    subscription = _stream.listen((event) => {
      print(event.runtimeType),
      onListen?.call(event)
    });


  }

  Stream<T> get stream => _stream.asBroadcastStream().cast<T>();

  void dispose() {
    _stream.drain();
    controller.close();
    subscription.cancel();
  }
}

///Work
class IWork {

  IWork(this.work, {this.name = "anonymous", this.onWorkStatusNotifier}) {
    _statusController.stream.listen((status) {
      onWorkStatusNotifier?.call(status);
    });
  }

  final String name;
  final Future<dynamic> Function() work;
  final Function(IWorkStatus workStatus)? onWorkStatusNotifier;

  //status
  final StreamController<IWorkStatus> _statusController =
      StreamController.broadcast()..add(IWorkStatus.undone);

  Future<IWorkStatus> get status async => await _statusController.stream.first;

  void setStatus(IWorkStatus status) => _statusController.add(status);

  @override
  String toString() => "{name : $name, status : $status}";

}

///Classes
abstract class IMessage<T>{
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

  static IMessage<dynamic> _pause(
      {required String name, required SendPort from, required SendPort to}) {
    return IWorkerMessageImpl(
        info: "Pausing worker $name",
        IState.pause,
        from: from,
        to: to,
        name: name);
  }

  static IMessage<dynamic> _resume(
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
        stream: _errorReceivePort
            .asBroadcastStream()
            .takeWhile((e) => e is IMessage)
            .cast(),
        onListen: (e) => _onErrorMessage(e));

    _allMessagesKit = _StreamKit(
        stream: _managerReceivePort
            .asBroadcastStream()
            .takeWhile((e) => e is IMessage)
            .cast(),
        onListen: (m) => _onReceiveMessage(m));

    _stateKit = _StreamKit(
        stream: _stateReceivePort
            .asBroadcastStream()
            .takeWhile((e) => e is IState)
            .cast(),
        onListen: (s) => _onStateMessage(s));

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
  Stream<IMessage<dynamic>> get messageStream => _allMessagesKit._stream.cast();

  //Errors
  late final _StreamKit<dynamic> _errorsKit;
  Stream<IMessage<dynamic>> get errorStream => _errorsKit._stream.cast();

  //State
  late final _StreamKit<dynamic> _stateKit;
  Stream<IMessage<dynamic>> get stateStream => _stateKit._stream.cast();

  static IManager create({String? name, bool? log}) {
    return IManagerImpl(name: name, log: log);
  }

  //Workers
  Future<IWorker> addWorker(String name,
      {dynamic Function(IMessage<dynamic>, IWorker worker)? onReceiveMessage,
      dynamic Function(IWorker worker)? onCancelMessageSubscription,
      dynamic Function(IWorker worker)? onPauseMessageSubscription,
      dynamic Function(IWorker worker)? onResumeMessageSubscription}) async {
    if (_isWorkerPresent(name)) throw Exception("Worker already present");
    IWorker isoWorker = await IWorker._create(name, managerSendPort,
        _errorReceivePort.sendPort, _stateReceivePort.sendPort,
        onReceiveMessage: onReceiveMessage);
    _workers.putIfAbsent(name, () => isoWorker);
    return isoWorker;
  }

  bool _isWorkerPresent(String name) {
    return getWorker(name) != null;
  }

  IWorker? getWorker(String name) {
    return _workers[name];
  }

  void killAllWorker() {
    for (IWorker w in _workers.values) {
      w.cancel(initiator: name);
    }
  }

  //Logging Listener
  void _setLogLevel() {
    Logger.level = _logging ? Level.warning : Level.info;
  }

  //Message Listener
  void _onReceiveMessage(IMessage message) {
    if (_logging) {
      _log.i(message.info);
    }
  }

  void _removeMessageListener() {
    _allMessagesKit.dispose();
  }

  void _removeErrorListener() {
    _errorsKit.dispose();
  }

  void _removeStateListener() {
    _stateKit.dispose();
  }

  //state
  void _onStateMessage(IMessage message) {
    String w = message.name;
    print(w);
    IWorker? worker = getWorker(w);
    if (worker == null) {
      _log.w("Worker not found");
      return;
    }

    switch (message.state) {
      case IState.listen:
        worker.resume();
        break;
      case IState.cancel:
        worker.dispose();
        _workers.remove(w);
        break;
      case IState.pause:
        worker.pause();
        break;
    }
  }

  void _onErrorMessage(IMessage message) {
    if (_logging) {
      _log.i(message.info);
    }
  }

  @override
  String toString() => name;

  //Lifecycle
  void _init() {
    _setLogLevel();
    if (_logging) {
      _managerReceivePort.sendPort.send(IMessage.createDataMessage(
          name: name,
          from: managerSendPort,
          to: managerSendPort,
          data: "$name created"));
      // _allMessagesKit.controller.add(IMessage.createDataMessage(
      //     name: name,
      //     from: managerSendPort,
      //     to: managerSendPort,
      //     data: "$name created"));
    }
  }

  void dispose() {
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
      dynamic Function(IMessage<dynamic> message, IWorker worker)?
          onReceiveMessage,
      dynamic Function(IWorker worker)? onCancelMessageSubscription,
      dynamic Function(IWorker worker)? onPauseMessageSubscription,
      dynamic Function(IWorker worker)? onResumeMessageSubscription,
      this.onWorkerStateChange}) {
    try {
      workerReceivePort = ReceivePort(name);

      _workerMessagesKit = _StreamKit(
          stream: workerReceivePort.asBroadcastStream().cast(),
          onListen: (message) => onReceiveMessage?.call(message, this));

      _workKit = _StreamKit<IWork>(
          onCancel: () => sendMessage(
              info: "$name work cancelled", sendPort: managerSendPort),
          onPause: () =>
              sendMessage(info: "$name work paused", sendPort: managerSendPort),
          onResume: () => sendMessage(
              info: "$name work resumed", sendPort: managerSendPort));

      // _workerIsolate = Isolate.spawn(actualWork, [_workKit.stream, _doWork],
      //     onError: errorSendPort, onExit: managerSendPort, debugName: name);
      _workerIsolate = Isolate.spawn<Stream<IWork>>((workStream) async {
        //todo
        // await for (IWork w in workStream) {}
      }, _workKit.stream,
          onError: errorSendPort, onExit: managerSendPort, debugName: name);
      _init();
    } catch (e, trace) {
      _sendError(info: e.toString(), data: trace);
    }
  }

  static void actualWork(List<dynamic> args) {
    //Stream<IWork> stream, Future<void> Function(IWork work) w
    Stream<IWork> stream = args[0] as Stream<IWork>;
    Future<void> Function(IWork work) w =
        args[1] as Future<void> Function(IWork work);
    stream.listen((work) => w.call(work));
  }

  static Future<IWorker> _create(String name, SendPort managerSendPort,
      SendPort errorSendPort, SendPort stateSendPort,
      {dynamic Function(IMessage<dynamic>, IWorker worker)? onReceiveMessage,
      dynamic Function(IWorker worker)? onCancelMessageSubscription,
      dynamic Function(IWorker worker)? onPauseMessageSubscription,
      dynamic Function(IWorker worker)? onResumeMessageSubscription,
      dynamic Function(IState state, IWorker worker)?
          onWorkerStateChange}) async {
    return IWorkerImpl(
      name: name,
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
  late final ReceivePort workerReceivePort;
  late final SendPort errorSendPort;
  late final SendPort stateSendPort;

  SendPort get workerSendPort => workerReceivePort.sendPort;
  final SendPort managerSendPort;

  //Messaging
  late final _StreamKit<IMessage<dynamic>> _workerMessagesKit;
  Stream<IMessage<dynamic>> get workerMessageStream =>
      _workerMessagesKit._stream.cast();

  //Messaging state
  final StreamController<IState> _workerMessageState =
      StreamController.broadcast()..add(IState.listen);
  Future<IState> get workerMessageState async =>
      (await _workerMessageState.stream.first);

  //Worker state
  late final StreamController<IState> _workerState =
      StreamController.broadcast()..add(IState.listen);
  Future<IState> get workerState async =>
      (await _workerState.stream.asBroadcastStream().first);
  dynamic Function(IState state, IWorker worker)? onWorkerStateChange;

  //work
  late final _StreamKit<IWork> _workKit;

  //isolate
  late Future<Isolate> _workerIsolate;
  Future<Isolate> get isolate async => await _workerIsolate;

  //messages
  Future<void> pauseMessageListening() async {
    IState iState = await workerMessageState;
    print("Pause state is $iState");

    switch (iState) {
      case IState.listen:
        _pauseMessage();
        break;
      case IState.cancel:
        throw Exception("Message subscription has already been cancelled");
      case IState.pause:
        throw Exception("Message subscription has already been paused");
    }
  }

  void _pauseMessage() {
    _workerMessagesKit.subscription.pause();
    _workerMessageState.add(IState.pause);
  }

  Future<void> resumeMessageListening() async {
    IState iState = await workerMessageState;

    switch (iState) {
      case IState.listen:
        throw Exception("Message subscription is already listening");

      case IState.cancel:
        throw Exception("Message subscription has already been cancelled");
      case IState.pause:
        _resumeMessage();
        break;
    }
  }

  void _resumeMessage() {
    _workerMessagesKit.subscription.resume();
    _workerMessageState.add(IState.listen);
  }

  Future<void> cancelMessageListening() async {
    IState iState = await workerMessageState;
    if (iState == IState.cancel) {
      throw Exception("Message subscription has already been cancelled");
    }

    _cancelMessage();
  }

  void _cancelMessage() {
    _workerMessagesKit.subscription.cancel();
    _workerMessageState.add(IState.cancel);
  }

  //work
  Future<void> _doWork(IWork? work) async {
    if (work == null) {
      sendMessage(info: "Null work", sendPort: managerSendPort);
      return;
    }

    sendMessage(info: "Starting work ${work.name}", sendPort: managerSendPort);
    work.setStatus(IWorkStatus.active);
    await work.work.call().then((_) {
      sendMessage(
          info: "Finished work ${work.name}", sendPort: managerSendPort);
      work.setStatus(IWorkStatus.done);
    }).catchError((e, trace) {
      work.setStatus(IWorkStatus.failed);
      sendMessage(
          info: "Failed work ${work.name}",
          data: work,
          sendPort: managerSendPort);
      _sendError(info: e.toString(), data: trace);
    });
  }

  void _removeWorkListener() {
    _workKit.subscription.cancel();
    _workKit.controller.close();
  }

  void addWork(Future<dynamic> Function() work,
      {Function(IWorkStatus workStatus)? onWorkStatusNotifier}) {
    IWork newWork = IWork(work, onWorkStatusNotifier: onWorkStatusNotifier);
    _workKit.controller.add(newWork);
  }

  //isolate
  //errors
  void _addErrorListener() {
    isolate.then((iso) => iso.addErrorListener(errorSendPort));
  }

  void _removeErrorListener() {
    isolate.then((iso) => iso.removeErrorListener(errorSendPort));
  }

  void _addExitListener() {
    IMessage message =
        IMessage._cancel(from: workerSendPort, to: managerSendPort, name: name);
    isolate.then((iso) =>
        iso.addOnExitListener(managerSendPort, response: message.toMap()));
  }

  void _removeExitListener() {
    isolate.then((iso) => iso.removeOnExitListener(managerSendPort));
  }

  //state
  void _addStateChangeListener() {
    _workerState.stream.listen((state) => _onStateChanged(state));
  }

  void _onStateChanged(IState state) {
    sendMessage(sendPort: stateSendPort, data: state);
    onWorkerStateChange?.call(state, this);
  }

  Future<void> pause() async {
    IState status = await workerState;
    switch (status) {
      case IState.cancel:
        throw Exception("Worker has been cancelled");
      case IState.pause:
        sendMessage(
            info: "$name isolate has already been paused",
            sendPort: managerSendPort);
        break;
      case IState.listen:
        _pause();
        break;
    }
  }

  void _pause() {
    _workerMessageState.add(IState.pause);
    _workKit.subscription.pause();
  }

  Future<void> resume() async {
    IState status = await workerState;

    switch (status) {
      case IState.listen:
        sendMessage(
            info: "$name isolate has not been paused",
            sendPort: managerSendPort);
        break;
      case IState.cancel:
        throw Exception("Worker has been cancelled");
      case IState.pause:
        _resume();
        break;
    }
  }

  void _resume() {
    _workerMessageState.add(IState.listen);
    _workKit.subscription.resume();
  }

  Future<void> cancel({String initiator = "Anonymous"}) async {
    IState status = await workerState;
    if (status == IState.cancel) {
      throw Exception("Worker has been cancelled");
    }
    dispose();
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

  @override
  String toString() => name;

  //Lifecycle
  void _init() {
    print("Init $name worker");
    _addStateChangeListener();
    _addExitListener();
    _addErrorListener();
  }

  void dispose() {
    _removeWorkListener();
    _removeExitListener();
    _removeErrorListener();
    Isolate.exit(stateSendPort,
        sendMessage(info: "$name disposed", sendPort: managerSendPort).toMap());
  }
}
