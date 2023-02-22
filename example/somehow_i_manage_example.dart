import 'package:somehow_i_manage/somehow_i_manage.dart';

class FizzBuzz {
  final int n;
  final bool? fizz;
  final bool? buzz;

  FizzBuzz(this.n, {this.fizz, this.buzz});

  FizzBuzz copyWith({bool? fizz, bool? buzz}) {
    return FizzBuzz(n, fizz: fizz ?? this.fizz, buzz: buzz ?? this.buzz);
  }
}

Future<void> main() async {
  IManager fizzbuzzManager =
      IManager.create(name: "FizzBuzz Manager", log: true);

  IWorker fizzWorker = await fizzbuzzManager.addWorker("Fizz");

  IWorker fizzBuzzWorker = await fizzbuzzManager.addWorker("FizzBuzz",
      onReceiveMessage: (message, worker) {
    if (message.tag != null && message.tag == "FizzBuzz") {
      FizzBuzz n = message.data as FizzBuzz;

      String p = "";

      if (n.fizz ?? false) {
        p = "Fizz";
      }

      if (n.buzz ?? false) {
        p = "${p}Buzz";
      }

      print("${n.n} : $p");
      worker.sendMessage(
          info: "${n.n} : $p", sendPort: fizzbuzzManager.managerSendPort);
    }
  });

  IWorker buzzWorker = await fizzbuzzManager.addWorker("Buzz",
      onReceiveMessage: (message, worker) {
    if (message.tag != null && message.tag == "Buzz") {
      FizzBuzz fizzBuzz = message.data as FizzBuzz;
      bool buzz = fizzBuzz.n % 5 == 0;

      worker.sendMessage(
          info: "Sending Buzz ${fizzBuzz.n}",
          tag: "FizzBuzz",
          sendPort: fizzBuzzWorker.workerSendPort,
          data: fizzBuzz.copyWith(buzz: buzz));
    }
  });

  List<int> items = List.generate(100, (index) => index);
  /*for (int i in items) {
    //if fizz is divisible by 3 type fizz
    bool fizz = i % 3 == 0;

    fizzWorker.sendMessage(
        info: "Sending Fizz $i",
        tag: "Buzz",
        sendPort: buzzWorker.workerSendPort,
        data: FizzBuzz(i, fizz: fizz));
  }*/

  fizzbuzzManager.stateStream.listen((message) {
    print(message.name);
  });

  fizzbuzzManager.messageStream.listen((event) {
    print(event);
  });

  fizzbuzzManager.errorStream.listen((event) {
    print(event);
  });

  fizzWorker.pauseMessageListening();
  fizzWorker.resumeMessageListening();
  fizzWorker.pause();
  fizzWorker.resume();
  fizzWorker.cancel();
  fizzWorker.dispose();
  fizzbuzzManager.dispose();
}
