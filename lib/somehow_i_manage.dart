/// Support for doing something awesome.
///
/// More dartdocs go here.
library somehow_i_manage;

export 'src/somehow_i_manage_base.dart';
export 'package:logger/logger.dart';

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'package:rxdart/rxdart.dart';
import 'package:somehow_i_manage/somehow_i_manage.dart';
// import 'package:rxdart/rxdart.dart';

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

///Work
class IWork<T> {
  IWork(this.work,
      {this.name = "anonymous", this.onWorkStatusNotifier, this.onResult});

  final String name;
  final Future<T> Function() work;
  final Function(IWorkStatus workStatus)? onWorkStatusNotifier;
  final Function(T? result)? onResult;
  final DateTime time = DateTime.now();

  //status

  IWorkStatus _workStatus = IWorkStatus.undone;

  IWorkStatus get status => _workStatus;

  @override
  int get hashCode =>
      Object.hash(name, work, onWorkStatusNotifier, onResult, time);

  void setStatus(IWorkStatus status, {T? result}) {
    _workStatus = status;
    onWorkStatusNotifier?.call(status);
    if (status == IWorkStatus.success) {
      onResult?.call(result);
    }
  }

  @override
  String toString() => "{name : $name, status : $status}";

  @override
  bool operator ==(Object other) {
    if (other.hashCode != hashCode) return false;
    return super == other;
  }
}

///Classes
abstract class IMessage<T> {
  IMessage(
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
  final SendPort from;
  final SendPort to;
  final DateTime time = DateTime.now();

  @override
  int get hashCode => Object.hash(time, info, tag, data, from, to, name);

  @override
  String toString() =>
      "{name: $name, info: $info, tag:$tag , data: $data, time: $time";

  Map<String, dynamic> toMap() =>
      {"name": name, "info": info, "tag": tag, "data": data, "time": time};

  static IMessage<T> createDataMessage<T>(
      {String? info,
      String? tag,
      T? data,
      required String name,
      required SendPort from,
      required SendPort to}) {
    return IWorkerMessageImpl(
        info: info ?? "Sending data message",
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
        info: info ?? "Error", data: data, from: from, to: to, name: name);
  }

  @override
  bool operator ==(Object other) {
    if (other.hashCode != hashCode) return false;
    return super == other;
  }

  /*

    static IMessage<IState> _cancel(
        {required String name, required SendPort from, required SendPort to}) {
      return IWorkerMessageImpl<IState>(
          info: "Stopping worker $name",
          data: IState.cancel,
          from: from,
          to: to,
          name: name);
    }

    static IMessage<IState> _pause(
        {required String name, required SendPort from, required SendPort to}) {
      return IWorkerMessageImpl<IState>(
          info: "Pausing worker $name",
          data: IState.pause,
          from: from,
          to: to,
          name: name);
    }

    static IMessage<IState> _resume(
        {required String name, required SendPort from, required SendPort to}) {
      return IWorkerMessageImpl(
          info: "Resuming worker $name",
          data: IState.listen,
          from: from,
          to: to,
          name: name);
    }*/
}

abstract class IWorker {
  IWorker(
      {required this.name,
      required Level logging,
      Function(IMessage<dynamic> message, IWorker worker)? onReceiveMessage,
      Function(IState iState, IWorker worker)? onMessageStateChange,
      Function(IState state, IWorker worker)? onWorkerStateChange})
      : _logging = logging,
        _onReceiveMessage = onReceiveMessage,
        _onWorkerStateChange = onWorkerStateChange,
        _onWorkerMessageStateChange = onMessageStateChange;

  //Create Worker
  static Future<IWorker> create(String name,
      {Level logging = Level.nothing,
      dynamic Function(IMessage<dynamic>, IWorker worker)? onReceiveMessage,
      dynamic Function(IState state, IWorker worker)? onMessageStateChange,
      dynamic Function(IState state, IWorker worker)?
          onWorkStateChange}) async {
    IWorker iWorker = IWorkerImpl(
      name: name,
      logging: logging,
      onReceiveMessage: onReceiveMessage,
      onMessageStateChange: onMessageStateChange,
      onWorkerStateChange: onWorkStateChange,
    );

    try {
      await iWorker._init();
    } catch (e, trace) {
      iWorker._sendError(info: e.toString(), data: trace);
    }
    return iWorker;
  }

  //IWorker meta
  final String name;
  final Level _logging;
  SendPort get messageSendPort => _messageReceivePort.sendPort;
  late SendPort _isolateSendPort;

  ///Messaging
  final HashMap<int, IMessage> _ignoredMessages = HashMap();
  late final ReceivePort _messageReceivePort =
      ReceivePort("Worker ($name) : Message")
        ..takeWhile((e) => e is IMessage<dynamic>)
            .cast<IMessage<dynamic>>()
            .listen((message) => _onReceiveMessageCallback(message));

  //list
  final List<IMessage<dynamic>> _workerMessages = [];
  List<IMessage<dynamic>> get workerMessages => _workerMessages;

  //state
  IState _messageState = IState.listen;
  IState get messageState => _messageState;

  //callback
  final Function(IMessage<dynamic> message, IWorker worker)? _onReceiveMessage;
  final Function(IState state, IWorker worker)? _onWorkerMessageStateChange;

  ///Work
  IState _workState = IState.listen;
  IState get workState => _workState;
  final Function(IState state, IWorker worker)? _onWorkerStateChange;
  final HashMap<int, IWork> _ignoredWork = HashMap();

  ///Errors
  /////todo linked list also on messages
  final List<IMessage> _workerErrors = [];
  List<IMessage> get allErrors => _workerErrors;

  //messages
  void _onReceiveMessageCallback(IMessage iMessage) {
    switch (_messageState) {
      case IState.listen:
        if (_ignoredMessages[iMessage.hashCode] != null) {
          return;
        }

        _workerMessages.add(iMessage);
        _onReceiveMessage?.call(iMessage, this);

        break;
      case IState.cancel:
      case IState.pause:
        _ignoredMessages.putIfAbsent(iMessage.hashCode, () => iMessage);
        break;
    }
  }

  Future<void> pauseProcessingMessage() async {
    switch (_messageState) {
      case IState.listen:
        _messageState = IState.pause;
        _onMessageStateChange(_messageState);
        break;
      case IState.cancel:
        throw StreamKitCancelledException(
            "Message processing has been cancelled");
      case IState.pause:
        return;
    }
  }

  Future<void> resumeProcessingMessage() async {
    switch (_messageState) {
      case IState.listen:
        return;
      case IState.cancel:
        throw StreamKitCancelledException(
            "Message processing has been cancelled");
      case IState.pause:
        _messageState = IState.listen;
        _onMessageStateChange(_messageState);
        break;
    }
  }

  Future<void> stopProcessingMessage() async {
    switch (_messageState) {
      case IState.listen:
      case IState.pause:
        _messageState = IState.cancel;
        _onMessageStateChange(_messageState);
        break;
      case IState.cancel:
        throw StreamKitCancelledException(
            "Message processing has already been cancelled");
    }
  }

  Future<void> _createIsolate() async {
    ReceivePort tempPort = ReceivePort(name);
    Isolate.spawn<SendPort>((masterPort) async {
      ReceivePort isolateReceivePort = ReceivePort(name);
      masterPort.send(isolateReceivePort.sendPort);

      await for (IWork work
          in isolateReceivePort.takeWhile((e) => e is IWork)) {
        if (_ignoredWork[work.hashCode] != null) {
          continue;
        }
        _actualWork(work);
      }
    }, tempPort.sendPort);
    _isolateSendPort = await tempPort.first;
    tempPort.close();
  }

  //work
  void _actualWork<T>(IWork<T> work) {
    _logI("Starting work ${work.name}", level: _logging);
    work.setStatus(IWorkStatus.active);
    work.work.call().then((result) {
      _logI("Finished work ${work.name}", level: _logging);
      work.setStatus(IWorkStatus.success, result: result);
    }).catchError((e, trace) {
      work.setStatus(IWorkStatus.failed);
      _logI("Failed work ${work.name}", error: trace, level: Level.error);
    });
  }

  void _removeWorkListener() {
    _workState = IState.cancel;
    _messageReceivePort.close();
  }

  Future<void> addWork<T>(Future<T> Function() work,
      {Function(IWorkStatus workStatus)? onWorkStatusNotifier,
      Function(T? result)? onResult}) async {
    IWork<T> newWork = IWork<T>(work,
        onWorkStatusNotifier: onWorkStatusNotifier, onResult: onResult);

    switch (_workState) {
      case IState.listen:
        _isolateSendPort.send(newWork);
        break;
      case IState.cancel:
        throw StreamKitCancelledException("Work processing already cancelled");
      case IState.pause:
        _ignoredWork.putIfAbsent(newWork.hashCode, () => newWork);
        break;
    }
  }

  //state

  Future<void> pauseProcessingWork() async {
    switch (_workState) {
      case IState.listen:
        _workState = IState.pause;
        _onWorkStateChange(_workState);
        break;
      case IState.cancel:
        throw StreamKitCancelledException("Work processing already cancelled");
      case IState.pause:
        return;
    }
  }

  Future<void> resumeProcessingWork() async {
    switch (_workState) {
      case IState.listen:
        return;
      case IState.cancel:
        throw StreamKitCancelledException("Work processing already cancelled");
      case IState.pause:
        _workState = IState.listen;
        _onWorkStateChange(_workState);
        break;
    }
  }

  Future<void> stopProcessingWork({String initiator = "Anonymous"}) async {
    switch (_workState) {
      case IState.listen:
      case IState.pause:
        _workState = IState.cancel;
        _onWorkStateChange(_workState);
        break;
      case IState.cancel:
        throw StreamKitCancelledException("Work processing already cancelled");
    }
  }

  //messages
  IMessage<T> sendMessage<T>(
      {String? info, T? data, String? tag, required SendPort sendPort}) {
    IMessage<T> message = IMessage.createDataMessage(
        info: info,
        data: data,
        tag: tag,
        from: messageSendPort,
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
        from: messageSendPort,
        to: message.from,
        name: name);
    message.from.send(m);
    return m;
  }

  IMessage<T> _sendError<T>({required String info, T? data}) {
    IMessage<T> message = IMessage._error(
        info: info,
        data: data,
        from: messageSendPort,
        name: name,
        to: messageSendPort);
    _workerErrors.add(message);
    return message;
  }

  void _onWorkStateChange(IState iState) {
    _onWorkerStateChange?.call(iState, this);
  }

  void _onMessageStateChange(IState iState) {
    _onWorkerMessageStateChange?.call(iState, this);
  }

  @override
  String toString() => name;

  //Lifecycle
  Future<void> _init() async {
    print("Init $name worker");
    await _createIsolate();
  }

  void dispose() {
    _removeWorkListener();
    _logI("$name disposing", level: _logging);
  }
}

abstract class IException implements Exception {
  final String message;
  final dynamic trace;

  IException(this.message, {this.trace});

  @override
  String toString() => message;
}
