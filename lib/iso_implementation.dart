import 'package:somehow_i_manage/somehow_i_manage.dart';

class IWorkerImpl extends IWorker {
  IWorkerImpl(
      {required super.name,
      super.onReceiveMessage,
      super.onMessageStateChange,
      required super.logging,
      super.onWorkerStateChange});
}

class IWorkerMessageImpl<T> extends IMessage<T> {
  IWorkerMessageImpl({
    super.info,
    super.data,
    super.tag,
    required super.name,
    required super.from,
    required super.to,
  }) : super();
}

class IWorkerDuplicateNameException extends IException {
  IWorkerDuplicateNameException(String message, {dynamic trace})
      : super(message, trace: trace);
}

class StreamKitCancelledException extends IException {
  StreamKitCancelledException(String message, {dynamic trace})
      : super(message, trace: trace);
}
