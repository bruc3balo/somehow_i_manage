import 'dart:async';
import 'package:somehow_i_manage/iso_implementation.dart';
import 'package:somehow_i_manage/somehow_i_manage.dart';
import 'package:test/test.dart';

void main() {
  group("IWorker", () {
    test('create', () async {
      String workerName = "create-test";

      await IWorker.create(workerName);
      expect(true, true);
    });

    test('name', () async {
      String workerName = "create-test";
      IWorker iWorker = await IWorker.create(workerName);
      expect(iWorker.name, workerName);
    });

    test('Self Message', () async {
      String workerName = "create-test";
      IWorker iWorker =
          await IWorker.create(workerName, onReceiveMessage: (message, _) {
        print("message received");
        expect(message.tag, "Selfie");
      });

      iWorker.sendMessage(sendPort: iWorker.messageSendPort, tag: "Selfie");
      await Future.delayed(Duration(seconds: 1));
      print("Sent message");
    });

    test('_onReceiveMessage', () async {
      String workerName = "create-test";
      IWorker iWorker =
          await IWorker.create(workerName, onReceiveMessage: (message, worker) {
        expect(message.tag, "Selfie");
        print("===Selfie====");
      });

      iWorker.sendMessage(sendPort: iWorker.messageSendPort, tag: "Selfie");

      //wait for first message
      await Future.delayed(Duration(seconds: 2));

      expect(iWorker.workerMessages.isNotEmpty, true);
      expect(iWorker.workerMessages.first.tag, "Selfie");
    });

    test('pauseMessageListening', () async {
      String workerName = "create-test";
      IWorker iWorker = await IWorker.create(workerName);

      iWorker.pauseProcessingMessage();
      print("Message paused");
      iWorker.sendMessage(sendPort: iWorker.messageSendPort, tag: "Mic Check");

      await Future.delayed(Duration(seconds: 2));

      expect(iWorker.workerMessages.isEmpty, true);
    });

    test('resumeMessageListening', () async {
      String workerName = "create-test";
      String tag = "Mic Check 1";
      IWorker iWorker = await IWorker.create(workerName);

      iWorker.pauseProcessingMessage();
      print("Message paused");

      iWorker.sendMessage(sendPort: iWorker.messageSendPort, tag: tag);

      await Future.delayed(Duration(seconds: 2));

      expect(iWorker.workerMessages.isEmpty, true);

      iWorker.resumeProcessingMessage();
      print("Message resumed");

      iWorker.sendMessage(
          sendPort: iWorker.messageSendPort, tag: tag.replaceAll("1", "2"));

      await Future.delayed(Duration(seconds: 2));

      expect(iWorker.workerMessages.isEmpty, false);
      expect(iWorker.workerMessages.first.tag, tag.replaceAll("1", "2"));
    });

    test('cancelMessageListening', () async {
      String workerName = "create-test";
      String tag = "Mic Check 1";
      IWorker iWorker = await IWorker.create(workerName);

      iWorker.sendMessage(sendPort: iWorker.messageSendPort, tag: tag);

      await Future.delayed(Duration(seconds: 2));

      expect(iWorker.workerMessages.isEmpty, false);
      expect(iWorker.workerMessages.last.tag, tag);

      iWorker.stopProcessingMessage();
      print("Message cancelled");

      iWorker.sendMessage(
          sendPort: iWorker.messageSendPort, tag: tag.replaceAll("1", "2"));

      await Future.delayed(Duration(seconds: 2));

      expect(iWorker.workerMessages.isEmpty, false);
      expect(iWorker.workerMessages.last.tag, tag);

      iWorker.resumeProcessingMessage().then((_) {
        print("cancelled ex not thrown");
        expect(false, true);
      }).catchError((e, trace) {
        print("Throwing cancelled ex");
        expect(e.runtimeType, StreamCancelledException);
      });
    });

    test('addWork', () async {
      String workerName = "create-test";
      IWorker iWorker = await IWorker.create(workerName);

      int n = 0;
      iWorker.addWork<int>(() async => n + 1, onWorkStatusNotifier: (status) {
        print("Status is $status");
      }, onResult: (result) {
        n = result ?? n;
        print("Result is $result");
      });

      await Future.delayed(Duration(seconds: 2));

      //todo
      // expect(n, 1);
      print("Work test passed");
    });

    test('pause', () async {
      IWorker iWorker = await IWorker.create("create-worker");
      iWorker.pauseProcessingWork();
      iWorker.addWork<int>(() async => 0, onWorkStatusNotifier: (state) {
        throw AssertionError("Work was not supposed to happen");
      });

      await Future.delayed(Duration(seconds: 2));
    });

    test('resume', () async {
      IWorker iWorker = await IWorker.create("create-worker");
      iWorker.pauseProcessingWork();
      iWorker.addWork<int>(() async => 0, onWorkStatusNotifier: (state) {
        throw AssertionError("Work was not supposed to happen");
      });

      await Future.delayed(Duration(seconds: 2));
      iWorker.resumeProcessingWork();
      iWorker.addWork<int>(() async => 0, onWorkStatusNotifier: (state) {
        print("Work resumed $state");
      });

      await Future.delayed(Duration(seconds: 2));
    });

    test('onWorkStateChange', () async {
      IWorker iWorker =
          await IWorker.create("worker", onWorkStateChange: (state, worker) {
        print('State Change $state');
      });

      //pause
      iWorker.pauseProcessingWork();
      await Future.delayed(Duration(seconds: 2))
          .then((pause) => expect(iWorker.workState, IState.pause))

          //resume
          .then((resume) => iWorker.resumeProcessingWork())
          .then((resume) => Future.delayed(Duration(seconds: 2))
              .then((resume) => expect(iWorker.workState, IState.listen))

              //cancel
              .then((cancel) => iWorker.stopProcessingWork(initiator: "test"))
              .then((cancel) => Future.delayed(Duration(seconds: 2))
                  .then((cancel) => expect(iWorker.workState, IState.cancel))));
    });

    test('onMessageStateChange', () async {
      IWorker iWorker =
          await IWorker.create("worker", onMessageStateChange: (state, worker) {
        print('State Change $state');
      });

      //pause
      iWorker.pauseProcessingMessage();
      await Future.delayed(Duration(seconds: 2))
          .then((pause) => expect(iWorker.messageState, IState.pause))

          //resume
          .then((resume) => iWorker.resumeProcessingMessage())
          .then((resume) => Future.delayed(Duration(seconds: 2))
              .then((resume) => expect(iWorker.messageState, IState.listen))

              //cancel
              .then((cancel) => iWorker.stopProcessingMessage())
              .then((cancel) => Future.delayed(Duration(seconds: 2)).then(
                  (cancel) => expect(iWorker.messageState, IState.cancel))));
    });

    test('sendMessage & reply', () async {
      void iWorker1Messages(IMessage<dynamic> m, IWorker w) {
        print(m);
        if (m.tag == "Test") {
          switch (m.data) {
            case "Hello":
              w.reply(message: m, info: "Reply Hi", data: "Hello ${m.name}");
              break;
          }
        }
      }

      void iWorker2Messages(IMessage<dynamic> m, IWorker w) {
        print(m);
        if (m.tag == "Test") {
          switch (m.data) {
            case "Hi":
              w.reply(message: m, info: "Reply Hi", data: "Hi ${m.name}");
              break;
          }
        }
      }

      IWorker iWorker1 = await IWorker.create("create-worker-1",
          onReceiveMessage: iWorker1Messages);
      IWorker iWorker2 = await IWorker.create("create-worker-2",
          onReceiveMessage: iWorker2Messages);

      iWorker1.sendMessage(
          sendPort: iWorker2.messageSendPort,
          data: "Hi",
          tag: "Test",
          info: "Testing");

      iWorker2.sendMessage(
          sendPort: iWorker1.messageSendPort,
          data: "Hello",
          tag: "Test",
          info: "Testing");

      await Future.delayed(Duration(seconds: 2));
    });

    test('dispose', () async {
      IWorker iWorker = await IWorker.create(
        "dispose worker",
      );

      await Future.delayed(Duration(seconds: 2));
      iWorker.dispose();
      expect(iWorker.workState, IState.cancel);
      expect(iWorker.messageState, IState.cancel);
    });
  });
}

String timeFromDate(DateTime d) {
  return "${d.minute} : ${d.second} : ${d.millisecond}";
}
