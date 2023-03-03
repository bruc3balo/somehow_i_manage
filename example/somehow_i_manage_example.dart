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
  IWorker fizzWorker = await IWorker.create("Fizz");

  IWorker fizzBuzzWorker =
      await IWorker.create("FizzBuzz", onReceiveMessage: (message, worker) {
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
    }
  });

  IWorker buzzWorker =
      await IWorker.create("Buzz", onReceiveMessage: (message, worker) {
    if (message.tag != null && message.tag == "Buzz") {
      FizzBuzz fizzBuzz = message.data as FizzBuzz;
      bool buzz = fizzBuzz.n % 5 == 0;

      worker.sendMessage(
          info: "Sending Buzz ${fizzBuzz.n}",
          tag: "FizzBuzz",
          sendPort: fizzBuzzWorker.messageSendPort,
          data: fizzBuzz.copyWith(buzz: buzz));
    }
  });

  List<int> items = List.generate(100, (index) => index);
  for (int i in items) {
    //if fizz is divisible by 3 type fizz
    bool fizz = i % 3 == 0;

    fizzWorker.sendMessage(
        info: "Sending Fizz $i",
        tag: "Buzz",
        sendPort: buzzWorker.messageSendPort,
        data: FizzBuzz(i, fizz: fizz));
  }
}
