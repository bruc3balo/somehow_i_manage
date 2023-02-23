import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:rxdart/rxdart.dart';
import 'package:somehow_i_manage/iso_implementation.dart';
import 'package:somehow_i_manage/somehow_i_manage.dart';
import 'package:test/test.dart';

void main() {
  group('Logic', () {
    test('Dummy', () async {
      DateTime start = DateTime.now();
      int secs = 5;
      await Future.delayed(Duration(seconds: secs)).then((_) {
        DateTime end = DateTime.now();
        Duration duration =
            Duration(seconds: end.millisecond - start.millisecond);
        print(duration.inSeconds);
        expect(duration.inSeconds >= secs, true);
      });
    });
  });

  group('IManager', () {
    final String managerName = "test-manager";

    setUp(() {
      // Additional setup goes here.
    });

    test('name', () {
      final IManager iManager =
          IManager.create(name: managerName, logLevel: Level.info);
      final IManager noNameManager = IManager.create();
      expect(iManager.name, managerName);
      expect(noNameManager.name, "IsoManager");
    });

    test('Self message', () async {
      final IManager iManager =
          IManager.create(name: managerName, logLevel: Level.info);
      iManager.messageStream.listen((m) {
        print(m.data);
        expect(m.data, "${iManager.name} created");
      });

      IMessage<String> adam = IMessage.createDataMessage<String>(
          name: iManager.name,
          from: iManager.managerSendPort,
          to: iManager.managerSendPort,
          data: "${iManager.name} created");
      iManager.managerSendPort.send(adam);
    });

    test('addWorker', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create", logLevel: Level.info);
      IWorker iWorker = await iManager.addWorker(workerName);
      expect(iManager.isWorkerPresent(iWorker.name), true);
    });

    test('isWorkerPresent', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create", logLevel: Level.info);
      IWorker iWorker = await iManager.addWorker(workerName);

      expect(iManager.isWorkerPresent(workerName), true);
      expect(iManager.isWorkerPresent(iWorker.name), true);
      expect(iManager.isWorkerPresent("create"), false);
    });

    test('getWorker', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create", logLevel: Level.info);
      IWorker iWorker = await iManager.addWorker(workerName);

      expect(iManager.getWorker(workerName), iWorker);
      expect(iManager.getWorker(iWorker.name), iWorker);
      expect(iManager.getWorker("create"), null);
    });

    test('killAllWorker', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create", logLevel: Level.info);
      IWorker iWorker = await iManager.addWorker(workerName);

      expect(iManager.getWorker(iWorker.name), iWorker);
      iManager.killAllWorker();
      expect(iManager.getWorker(iWorker.name), null);
    });

    test('killWorker', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create", logLevel: Level.info);
      IWorker iWorker = await iManager.addWorker(workerName);

      expect(iManager.getWorker(iWorker.name), iWorker);
      iManager.killWorker(iWorker);
      expect(iManager.getWorker(iWorker.name), null);
    });

    test('dispose', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create", logLevel: Level.info);
      IWorker iWorker = await iManager.addWorker(workerName);

      expect(iManager.isWorkerPresent(workerName), true);
      expect(iManager.isWorkerPresent(iWorker.name), true);
      expect(iManager.isWorkerPresent("create"), false);

      iManager.dispose();

      expect(iManager.isWorkerPresent(workerName), false);
      expect(iManager.isWorkerPresent(iWorker.name), false);
    });
  });

  group("IWorker", () {
    test('create', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create", logLevel: Level.info);
      IWorker iWorker = await iManager.addWorker(workerName);
      expect(iManager.getWorker(workerName), iWorker);
    });

    test('name', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create", logLevel: Level.info);
      IWorker iWorker = await iManager.addWorker(workerName);

      expect(iWorker.name, workerName);
    });

    test('Self Message', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create", logLevel: Level.info);
      IWorker iWorker = await iManager.addWorker(workerName);

      iWorker.sendMessage(sendPort: iWorker.workerSendPort, tag: "Selfie");
      expect((await iWorker.workerMessageStream.first).tag, "Selfie");
    });

    test('_onReceiveMessage', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create", logLevel: Level.info);
      IWorker iWorker = await iManager.addWorker(workerName,
          onReceiveMessage: (message, worker) {
        expect(message.tag, "Selfie");
        print("===Selfie====");
      });

      iWorker.sendMessage(sendPort: iWorker.workerSendPort, tag: "Selfie");

      //wait for first message
      await for (IMessage m in iWorker.workerMessageStream) {
        expect(m.tag, "Selfie");
        break;
      }
    });

    test('pauseMessageListening', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create");
      IWorker iWorker = await iManager.addWorker(workerName);

      iWorker.pauseMessageListening();
      int count = 0;
      Timer.periodic(Duration(seconds: 2), (timer) {
        if (count++ == 1) {
          timer.cancel();

          return;
        }
        iWorker.sendMessage(sendPort: iWorker.workerSendPort, tag: "Mic Check");
        iWorker.sendMessage(sendPort: iWorker.workerSendPort, tag: "Mic Check");

        timer.cancel();
      });

      //wait for first message
      bool success = false;
      try {
        await iWorker.workerMessageStream.first.then((m) {
          expect(m.tag, "Not Mic Check");
          success = false;
        }).timeout(Duration(seconds: 5));
      } on TimeoutException catch (e) {
        success = true;
        expect(TimeoutException, e.runtimeType);
      } catch (e) {
        expect(success, true);
      } finally {
        expect(success, true);
      }
    });

    test('resumeMessageListening', () async {
      String workerName = "create-test";
      String tag = "Mic Check 1";

      IManager iManager = IManager.create(name: "create");
      IWorker iWorker = await iManager.addWorker(workerName,
          onReceiveMessage: (m, w) => expect(m.tag, tag));

      Future.delayed(Duration(seconds: 2), () {
        iWorker.pauseMessageListening();
        iWorker.sendMessage(sendPort: iWorker.workerSendPort, tag: tag);
        iWorker.sendMessage(sendPort: iWorker.workerSendPort, tag: tag);
      });

      Future.delayed(
          Duration(seconds: 2), () => iWorker.resumeMessageListening());

      //wait for first message
      bool success = false;
      try {
        await iWorker.workerMessageStream.first.then((m) {
          expect(m.tag, tag);
          success = true;
        }).timeout(Duration(seconds: 5));
      } on TimeoutException {
        success = false;
      } catch (e) {
        expect(success, true);
      } finally {
        expect(success, true);
      }
    });

    test('cancelMessageListening', () async {
      String workerName = "create-test";
      String tag = "Mic Check 1";

      IManager iManager = IManager.create(name: "create");
      IWorker iWorker = await iManager.addWorker(workerName,
          onReceiveMessage: (m, w) => expect(false, true));

      bool success = false;

      Future<bool> getResult() async {
        DateTime start = DateTime.now();
        print(DateTime.now().millisecond);
        await Future.value(() {
          try {
            iWorker.cancelMessageListening();
            iWorker.sendMessage(sendPort: iWorker.workerSendPort, tag: tag);
            iWorker.sendMessage(sendPort: iWorker.workerSendPort, tag: tag);
            print("Sent $success");
          } on StreamKitCancelledException {
            success = true;
            print("Message stream cancel $success");
          } catch (e) {
            success = false;
            print("Message some other error $success");
          }
        });
        print(DateTime.now().millisecond);

        try {
          await Future.delayed(Duration(seconds: 2), () async {
            await for (IMessage m in iWorker.workerMessageStream) {
              success = false;
              print("Message $m $success");
            }
            // while (true) {}
          }).timeout(Duration(seconds: 15), onTimeout: () {
            success = true;
            print("Read timeout $success");
          });
        } on StreamKitCancelledException {
          success = true;
          print("Read stream kit $success");
        } catch (e) {
          success = false;
          print("Read some other error $success");
        } finally {
          print("Result is $success");
          print(DateTime.now().millisecond);
          DateTime end = DateTime.now();

          Duration time =
              Duration(milliseconds: end.millisecond - start.millisecond);
          print("Time taken ${time.inMilliseconds}");
          // expect(success, true);
        }

        return success;
      }

      expect(await getResult(), true);
    });

    test('addWork', () async {
      IManager iManager = IManager.create(name: "create");
      IWorker iWorker = await iManager.addWorker("create-worker");

      int a = 1;
      int b = 1;
      iWorker.addWork<int>(() async {
        return a + b;
      }, onWorkStatusNotifier: (status) {
        switch (status) {
          case IWorkStatus.undone:
            print("Starting work");
            break;
          case IWorkStatus.active:
            print("Doing work");
            break;
          case IWorkStatus.done:
            print("Did work");
            // expect(sum, a + b);
            break;
          case IWorkStatus.failed:
            print("Doing work failed");
            break;
        }
      }, onResult: (s) {
        print("Did work result $s");
        //todo expect(s, a + b);
      });
      // Future.delayed(Duration(seconds: 5));
    });

    test('pause', () async {
      IManager iManager = IManager.create(name: "create");
      IWorker iWorker = await iManager.addWorker("create-worker");
      iWorker.pause();
      iWorker.addWork<int>(() async => 0, onWorkStatusNotifier: (state) {
        expect(false, true);
      });
    });

    test('resume', () async {
      IManager iManager = IManager.create(name: "create");
      IWorker iWorker = await iManager.addWorker("create-worker");

      iWorker.pause();
      iWorker.resume();

      BehaviorSubject<IWorkStatus> status = BehaviorSubject()
        ..add(IWorkStatus.undone);
      iWorker.addWork<int>(() async => 0, onWorkStatusNotifier: (state) {
        expect(true, true);
        status.add(state);
        print("State is ${status.value}");
      }, onResult: (s) {
        expect(true, true);
        status.add(IWorkStatus.done);
        print("Result is ${status.value}");
      });

      Future<void> check() async {
        print("Checking ${status.value}");

        if (status.value != IWorkStatus.done) {
          return;
        }

        expect(status, IWorkStatus.done);
      }

      // await Future.delayed(Duration(seconds: 2));
      // await check();
      //
      // await Future.delayed(Duration(seconds: 2));
      // await check();
      //
      // await Future.delayed(Duration(seconds: 2));
      // await check();
    });

    test('cancel', () async {
      IManager iManager = IManager.create(name: "create");
      IWorker iWorker = await iManager.addWorker("create-worker");

      iWorker.cancel(initiator: "test");

      bool success = false;
      try {
        iWorker.addWork(() async => 0);
      } on StreamKitCancelledException {
        success = true;
      } catch (e) {
        success = false;
      } finally {
        expect(success, true);
      }
    });

    test('sendMessage & reply', () async {
      IManager iManager = IManager.create(name: "create");

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

      IWorker iWorker1 = await iManager.addWorker("create-worker-1",
          onReceiveMessage: iWorker1Messages);
      IWorker iWorker2 = await iManager.addWorker("create-worker-2",
          onReceiveMessage: iWorker2Messages);

      iWorker1.sendMessage(
          sendPort: iWorker2.workerSendPort,
          data: "Hi",
          tag: "Test",
          info: "Testing");

      iWorker2.sendMessage(
          sendPort: iWorker1.workerSendPort,
          data: "Hello",
          tag: "Test",
          info: "Testing");
    });

    test('_onStateChange', () async {
      BehaviorSubject<IState> sub = BehaviorSubject();
      IManager iManager = IManager.create(name: "create");
      IWorker iWorker = await iManager.addWorker("worker",
          onWorkerStateChange: (state, worker) =>
              {print('"State Change $state'), sub.add(state)});

      //pause
      iWorker.pause();
      Future.delayed(Duration(seconds: 2))
          .then((pause) => expect(sub.value, IState.pause))

          //resume
          .then((resume) => iWorker.resume())
          .then((resume) => Future.delayed(Duration(seconds: 2))
              .then((resume) => expect(sub.value, IState.listen))

              //cancel
              .then((cancel) => iWorker.cancel(initiator: "test"))
              .then((cancel) => Future.delayed(Duration(seconds: 2))
                  .then((cancel) => expect(sub.value, IState.cancel))));
    });

    test('dispose', () async {
      IManager iManager = IManager.create(name: "create");
      IWorker iWorker = await iManager.addWorker(
        "dispose",
      );

      await Future.delayed(Duration(seconds: 2));
      iWorker.dispose();
      // expect(iWorker.workerState, IState.cancel);
    });
  });

  group("IManager & IWorker", () {
    test('_informManagerOfStateChange', () async {
      String workerName = "create-test";
      String tag = "Mic Check 1";

      IManager iManager = IManager.create(name: "create");
      iManager.messageStream.listen((m) {
        print("SSS ${m.state}");
      });

      IWorker iWorker = await iManager.addWorker(workerName,
          onReceiveMessage: (m, w) => expect(false, true));
      DateTime start = DateTime.now();
      // print(timeFromDate(start));

      // iWorker.sendMessage(
      //     sendPort: iWorker.managerSendPort,
      //     data: IState.pause,
      //     info: "Pausing");
      iWorker.sendMessage(
          sendPort: iWorker.stateSendPort, data: IState.pause, info: "Pausing");
      iWorker.stateSendPort.send(IWorkerMessageImpl(IState.pause,
          name: iWorker.name,
          from: iWorker.workerSendPort,
          to: iManager.managerSendPort));

      // iWorker.cancel();
      iWorker.pause();
      iWorker.pause();
      iWorker.resume();

      /*await for (IMessage m in iManager.messageStream
          .timeout(Duration(seconds: 12), onTimeout: (_) {
        print("on timeout");
        expect(true, true);

        DateTime end = DateTime.now();
        print(timeFromDate(end));
      })) {
        // expect(present, true);
        print("List : $m");
      }*/
    });

    test('_sendError', () async {
      IManager iManager = IManager.create(name: "create");
      IWorker iWorker = await iManager.addWorker("create");
    });
  });
}

String timeFromDate(DateTime d) {
  return "${d.minute} : ${d.second} : ${d.millisecond}";
}
