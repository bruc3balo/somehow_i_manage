/// Support for doing something awesome.
///
/// More dartdocs go here.
library somehow_i_manage;

// Export any libraries intended for clients of this package.

export 'src/somehow_i_manage_base.dart';
export 'package:logger/logger.dart';

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'package:logger/logger.dart';

import 'iso_implementation.dart';

var _log = Logger();

//Work
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
  final StreamController<IWorkStatus> _statusController = StreamController()
    ..add(IWorkStatus.undone);

  Future<IWorkStatus> get status async => await _statusController.stream.first;

  void setStatus(IWorkStatus status) => _statusController.add(status);

  @override
  String toString() => "{name : $name, status : $status}";
}

//Classes
abstract class IMessage<T> {
  const IMessage(this.info, this.state, {this.data});

  final String info;
  final T? data;
  final IState state;

  @override
  String toString() => "{info: $info, state : $state, data: $data}";

  static IMessage<T> _stop<T>({
    String? info,
    T? data,
  }) {
    return IWorkerMessageImpl<T>(info ?? "Stopping worker", IState.cancel,
        data: data);
  }

  static IMessage<T> sendData<T>({String? info, T? data}) {
    return IWorkerMessageImpl(info ?? "Sending data message", IState.listen,
        data: data);
  }

  static IMessage<T> _error<T>({String? info, T? data}) {
    return IWorkerMessageImpl(info ?? "Error", IState.listen, data: data);
  }

  static IMessage<dynamic> _pause({String? info}) {
    return IWorkerMessageImpl(info ?? "Pausing worker", IState.pause);
  }

  static IMessage<dynamic> _resume({String? info}) {
    return IWorkerMessageImpl(info ?? "Resuming worker", IState.listen);
  }
}

abstract class IManager {
  IManager({
    required this.name,
    required bool log,
  }) {
    _logging = log;
    managerReceivePort = ReceivePort(name);
    _errorReceivePort = ReceivePort("Error");
    _allMessageStream = StreamController<IMessage<dynamic>>();
    _errorStream = StreamController<IMessage<dynamic>>();
    _init();
  }

  //Meta IManager
  final String name;
  late final bool _logging;
  late final ReceivePort managerReceivePort;
  late final ReceivePort _errorReceivePort;

  //Workers
  final HashMap<String, IWorker> _workers = HashMap();

  //Messages
  late final StreamSubscription<IMessage<dynamic>> _allMessageSubscription;
  late final StreamController<IMessage<dynamic>> _allMessageStream;

  //Messages getters
  SendPort get managerSendPort => managerReceivePort.sendPort;
  Stream<IMessage<dynamic>> get messageStream => _allMessageStream.stream;
  Stream<IMessage<dynamic>> get _allMessages =>
      managerReceivePort.asBroadcastStream().cast<IMessage<dynamic>>();

  //error
  late final StreamSubscription<IMessage<dynamic>> _errorSubscription;
  late final StreamController<IMessage<dynamic>> _errorStream;
  //error getters
  Stream<IMessage<dynamic>> get errorStream => _allMessageStream.stream;
  Stream<IMessage<dynamic>> get _allErrors =>
      managerReceivePort.asBroadcastStream().cast<IMessage<dynamic>>();

  static IManager create({String? name, bool? log}) {
    return IManagerImpl(name: name, log: log);
  }

  //Workers
  IWorker addWorker(String name,
      {dynamic Function(IMessage<dynamic>)? onReceiveMessage,
      dynamic Function()? onCancelMessageSubscription,
      dynamic Function()? onPauseMessageSubscription,
      dynamic Function()? onResumeMessageSubscription}) {
    if (_isWorkerPresent(name)) throw Exception("Worker already present");
    IWorker isoWorker = IWorker._create(
        name, managerSendPort, _errorReceivePort.sendPort,
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
  void _addLogListener() {
    Logger.level = _logging ? Level.warning : Level.info;
  }

  void _removeLogListener() {
    _log.close();
  }

  //Message Listener
  void _addMessageListener() {
    _allMessageSubscription = _allMessageStream.stream.listen((message) async {
      if (_logging) {
        _log.i(message.info);
      }
    });
  }

  void _removeMessageListener() {
    _allMessageSubscription.cancel();
  }

  void _removeErrorListener() {
    _errorSubscription.cancel();
  }

  //Errors
  void _addErrorListener() {
    _errorSubscription = _errorStream.stream.listen((error) {
      _log.e(error.info, [error.info, error.data]);
    });
  }

  @override
  String toString() => name;

  //Lifecycle
  void _init() {
    _addLogListener();
    _addMessageListener();
    _addErrorListener();
  }

  void dispose() {
    _removeLogListener();
    _removeMessageListener();
    _removeErrorListener();
  }
}

abstract class IWorker {
  IWorker(
      {required this.name,
      required this.managerSendPort,
      required this.errorSendPort,
      dynamic Function(IMessage workerMessage)? onReceiveMessage,
      dynamic Function()? onCancelMessageSubscription,
      dynamic Function()? onPauseMessageSubscription,
      dynamic Function()? onResumeMessageSubscription}) {
    Isolate.spawn((_) => _addWorkListener(), managerSendPort)
        .then((iso) => {_workerIsolate = iso, _init()});
    workerReceivePort = ReceivePort(name);
    _onWorkerMessage = onReceiveMessage;
  }

  //IWorker meta
  final String name;
  late final ReceivePort workerReceivePort;
  late final SendPort errorSendPort;
  SendPort get workerSendPort => workerReceivePort.sendPort;
  final SendPort managerSendPort;
  late final Function(IMessage workerMessage)? _onWorkerMessage;

  //work
  late final StreamController<IWork> _work = StreamController(
      onCancel: () => sendMessage(info: "$name work cancelled"),
      onListen: () => sendMessage(info: "$name work listening"),
      onPause: () => sendMessage(info: "$name work paused"),
      onResume: () => sendMessage(info: "$name work resumed"));
  late final StreamSubscription<IWork> _workController;

  static IWorker _create(
      String name, SendPort managerSendPort, SendPort errorSendPort,
      {Function(IMessage workerMessage)? onReceiveMessage,
      dynamic Function()? onCancelMessageSubscription,
      dynamic Function()? onPauseMessageSubscription,
      dynamic Function()? onResumeMessageSubscription}) {
    return IWorkerImpl(
        name: name,
        managerSendPort: managerSendPort,
        errorSendPort: errorSendPort,
        onReceiveMessage: onReceiveMessage,
        onCancelMessageSubscription: onCancelMessageSubscription,
        onPauseMessageSubscription: onPauseMessageSubscription,
        onResumeMessageSubscription: onResumeMessageSubscription);
  }

  //messages
  final StreamController<IMessage<dynamic>> _messageStream =
      StreamController<IMessage<dynamic>>();
  late final StreamSubscription<IMessage<dynamic>> _workerMessagesSubscription;
  final StreamController<IState> _messageState = StreamController()
    ..add(IState.listen);

  Future<IState> get messageState async => await _messageState.stream.first;
  late final Stream<IMessage<dynamic>> workerMessages =
      workerReceivePort.asBroadcastStream().cast<IMessage<dynamic>>();

  //state
  final StreamController<IState> _state = StreamController()
    ..add(IState.listen);
  Future<IState> get state async => await _state.stream.first;

  //isolate
  late final Isolate _workerIsolate;

  //messages
  void _addInterWorkerMessageListener() {
    _workerMessagesSubscription = workerMessages
        .listen((message) async => _onWorkerMessage?.call(message));
  }

  void pauseMessageListening() {
    messageState.then((mState) {
      switch (mState) {
        case IState.listen:
          _workerMessagesSubscription.pause();
          _messageState.add(IState.pause);
          break;
        case IState.cancel:
          throw Exception("Message subscription has already been cancelled");
        case IState.pause:
          throw Exception("Message subscription has already been paused");
      }
    });
  }

  void resumeMessageListening() {
    messageState.then((mState) {
      switch (mState) {
        case IState.listen:
          throw Exception("Message subscription is already listening");

        case IState.cancel:
          throw Exception("Message subscription has already been cancelled");
        case IState.pause:
          _workerMessagesSubscription.resume();
          _messageState.add(IState.listen);
          break;
      }
    });
  }

  Future<void> cancelMessageListening() async {
    IState iState = await messageState;
    if (iState == IState.cancel) {
      throw Exception("Message subscription has already been cancelled");
    }
    _workerMessagesSubscription.cancel();
    _messageState.add(IState.cancel);
  }

  //work
  void _addWorkListener() {
    _workController = _work.stream.listen((work) async => _doWork(work));
  }

  Future<void> _doWork(IWork work) async {
    sendMessage(info: "Starting work ${work.name}");
    work.setStatus(IWorkStatus.active);
    await work.work.call().then((_) {
      sendMessage(info: "Finished work ${work.name}");
      work.setStatus(IWorkStatus.done);
    }).catchError((e, trace) {
      work.setStatus(IWorkStatus.failed);
      sendMessage(info: "Failed work ${work.name}", data: work);
      sendError(info: e.toString(), data: trace);
    });
  }

  void _removeWorkListener() {
    _workController.cancel();
    _work.close();
  }

  void addWork(Future<dynamic> Function() work,
      {Function(IWorkStatus workStatus)? onWorkStatusNotifier}) {
    IWork newWork = IWork(work, onWorkStatusNotifier: onWorkStatusNotifier);
    _work.sink.add(newWork);
  }

  //isolate
  //errors
  void _addErrorListener() {
    _workerIsolate.addErrorListener(errorSendPort);
  }

  void _removeErrorListener() {
    _workerIsolate.removeErrorListener(errorSendPort);
  }

  void _addExitListener() {
    IMessage message = IMessage._stop(info: "$name exited");
    // _workerIsolate.addOnExitListener(managerSendPort, response: message);
  }

  void _removeExitListener() {
    _workerIsolate.removeOnExitListener(managerSendPort);
  }

  //state
  void addStateChangeListener() {}

  Future<void> pause() async {
    IState status = await state;
    switch (status) {
      case IState.cancel:
        throw Exception("Worker has been cancelled");
      case IState.pause:
        sendMessage(info: "$name isolate has already been paused");
        break;
      case IState.listen:
        _state.add(IState.pause);
        _workController.pause();
        break;
    }
  }

  Future<void> resume() async {
    IState status = await state;

    switch (status) {
      case IState.listen:
        sendMessage(info: "$name isolate has not been paused");
        break;
      case IState.cancel:
        throw Exception("Worker has been cancelled");
      case IState.pause:
        _state.add(IState.listen);
        _workController.resume();
        break;
    }
  }

  Future<void> cancel({String initiator = "Anonymous"}) async {
    IState status = await state;

    if (status == IState.cancel) {
      throw Exception("Worker has been cancelled");
    }
    _state.add(IState.cancel);
    _removeWorkListener();
    IMessage message =
        IMessage._stop(info: "$name isolate killed by $initiator");
    Isolate.exit(managerSendPort, message);
  }

  //messages
  IMessage<T> sendMessage<T>(
      {required String info, T? data, SendPort? sendPort}) {
    SendPort port = sendPort ?? managerSendPort;
    IMessage<T> message = IMessage.sendData(info: info, data: data);
    port.send(message);
    return message;
  }

  IMessage<T> sendError<T>(
      {required String info, T? data, SendPort? sendPort}) {
    SendPort port = sendPort ?? errorSendPort;
    IMessage<T> message = IMessage._error(info: info, data: data);
    port.send(message);
    return message;
  }

  @override
  String toString() => name;

  //Lifecycle
  void _init() {
    _addInterWorkerMessageListener();
    _addWorkListener();
    _addExitListener();
    _addErrorListener();
  }

  void dispose() {
    _removeWorkListener();
    _removeExitListener();
    _removeErrorListener();
  }
}
