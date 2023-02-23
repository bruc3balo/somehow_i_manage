import 'package:somehow_i_manage/somehow_i_manage.dart';
import 'package:test/test.dart';

void main() {
  group('IManager', () {
    final String managerName = "test-manager";

    setUp(() {
      // Additional setup goes here.
    });

    test('Name', () {
      final IManager iManager = IManager.create(name: managerName, log: true);
      final IManager noNameManager = IManager.create();
      expect(iManager.name, managerName);
      expect(noNameManager.name, "IsoManager");
    });

    test('Self message', () async {
      final IManager iManager = IManager.create(name: managerName, log: true);
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
  });

  group("IWorker", () {
    test('Create Worker "create"', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create", log: true);
      IWorker iWorker = await iManager.addWorker(workerName);
      expect(iManager.getWorker(workerName), iWorker);
    });
    test('isWorkerPresent', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create", log: true);
      IWorker iWorker = await iManager.addWorker(workerName);

      expect(iManager.isWorkerPresent(workerName), true);
      expect(iManager.isWorkerPresent(iWorker.name), true);
      expect(iManager.isWorkerPresent("create"), false);
    });
    test('getWorker', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create", log: true);
      IWorker iWorker = await iManager.addWorker(workerName);

      expect(iManager.getWorker(workerName), iWorker);
      expect(iManager.getWorker(iWorker.name), iWorker);
      expect(iManager.getWorker("create"), null);
    });
    test('killAllWorker', () async {
      String workerName = "create-test";
      IManager iManager = IManager.create(name: "create", log: true);
      IWorker iWorker = await iManager.addWorker(workerName);

      expect(iManager.getWorker(iWorker.name), iWorker);

      //todo endless
      await iManager.killAllWorker();
      // expect(iManager.getWorker(iWorker.name), null);
    });
  });

  group("IManager & IWorker", () {});
}
