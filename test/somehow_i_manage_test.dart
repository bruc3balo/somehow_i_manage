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

      List<IMessage> message = await iManager.messageStream.toList();
      print(message.length);

    });
  });

  group("IWorker", () {

  });

  group("IManager & IWorker", () {

  });


}