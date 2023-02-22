import 'package:somehow_i_manage/somehow_i_manage.dart';

class IManagerImpl extends IManager {
  IManagerImpl({
    String? name,
    bool? log,
  }) : super(name: name ?? "IsoManager", log: log ?? false);
}

class IWorkerImpl extends IWorker {
  IWorkerImpl(
      {required super.name,
      required super.managerSendPort,
      required super.errorSendPort,
      required super.stateSendPort,
      super.onReceiveMessage,
      super.onCancelMessageSubscription,
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
