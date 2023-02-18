import 'package:somehow_i_manage/iso_implementation.dart';
import 'package:somehow_i_manage/somehow_i_manage.dart';

void main() {
  IManager manager = IManager.create(name: "test-manager", log: true);
  IWorker worker1 =
      manager.addWorker("test-work-1", onReceiveMessage: (message) {
    print("Worker1: Received message : ${message.info}");
  }, onCancelMessageSubscription: () {
    print("Worker1: Message cancelled");
  }, onPauseMessageSubscription: () {
    print("Worker1: Message paused");
  }, onResumeMessageSubscription: () {
    print("Worker1: Message resumed");
  });

  IWorker worker2 =
      manager.addWorker("test-work-2", onReceiveMessage: (message) {
    print("Worker2: Received message : ${message.info}");
  }, onCancelMessageSubscription: () {
    print("Worker2: Message cancelled");
  }, onPauseMessageSubscription: () {
    print("Worker2: Message paused");
  }, onResumeMessageSubscription: () {
    print("Worker2: Message resumed");
  });

  IMessage message = IMessage.sendData(info: " Sending from test-work-1");
  worker1.sendMessage(info: message.info, sendPort: worker2.workerSendPort);

  worker2.addWork(() async {
    for (int i = 0; i < 100; i++) {
      print("Sending $i");
      worker2.sendMessage<int>(
          info: "Sending from ${worker2.name}",
          data: i,
          sendPort: worker1.workerSendPort);
    }
  }, onWorkStatusNotifier: (workStatus) {
    switch (workStatus) {
      case IWorkStatus.undone:
        print("Work $workStatus");
        break;
      case IWorkStatus.active:
        print("Work $workStatus");
        break;
      case IWorkStatus.done:
        print("Work $workStatus");
        break;
      case IWorkStatus.failed:
        print("Work $workStatus");
        break;
    }
  });
}
