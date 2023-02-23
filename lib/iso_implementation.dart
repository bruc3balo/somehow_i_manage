import 'package:somehow_i_manage/somehow_i_manage.dart';

class IManagerImpl extends IManager {
  IManagerImpl({
    String? name,
    Level? logLevel,
  }) : super(name: name ?? "IsoManager", logLevel: logLevel ?? Level.error);
}

class IWorkerImpl extends IWorker {
  IWorkerImpl(
      {required super.name,
      required super.managerSendPort,
      required super.errorSendPort,
      required super.stateSendPort,
      super.onReceiveMessage,
      super.onCancelMessageSubscription,
      required super.logging,
      super.onPauseMessageSubscription,
      super.onResumeMessageSubscription,
      super.onWorkerStateChange});
}

class IWorkerMessageImpl<T> extends IMessage<T> {
  IWorkerMessageImpl(IState state,
      {super.info,
      super.data,
      super.tag,
      required super.name,
      required super.from,
      required super.to})
      : super(state);
}

class IWorkerPresentException extends IException {
  IWorkerPresentException(String message, {dynamic trace})
      : super(message, trace: trace);
}

class StreamKitCancelledException extends IException {
  StreamKitCancelledException(String message, {dynamic trace})
      : super(message, trace: trace);
}
