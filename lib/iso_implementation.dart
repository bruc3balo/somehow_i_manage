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
      super.onReceiveMessage,
      super.onCancelMessageSubscription,
      super.onPauseMessageSubscription,
      super.onResumeMessageSubscription});
}

class IWorkerMessageImpl<T> extends IMessage<T> {
  IWorkerMessageImpl(String info, IState state, {super.data})
      : super(info, state);
}

enum IWorkStatus { undone, active, done, failed }

enum IState { listen, cancel, pause }
