
THis package helps it easier to work with threads i.e. Isolates to make task distribuion easier

## Features

1. Pausing work
2. Inter Isolate communication

## Getting started
Add the package to your project by using this command

```shell
dart pub add somehow_i_manage
```

## Usage

To use this package create a worker like so


```dart
IWorker worker = IWorker.create(name: "name");
```

You can add callbacks for receiving messages from isolates like below

```dart

IWorker iWorker = await IWorker.create("create-test", onReceiveMessage: (message, _) {
print("message received");
expect(message.tag, "Selfie");
});

IWorker iWorker2 = await IWorker.create("create-test-2", onReceiveMessage: (message, _) {
print("message received 2");
expect(message.tag, "Selfie");
});

iWorker.sendMessage(sendPort: iWorker2.messageSendPort, tag: "Selfie");
await Future.delayed(Duration(seconds: 1));
print("Sent message");

```

Do not forget to dispose the worker when done using it

```dart
IWorker iWorker = await IWorker.create("create-test");

//computation here

iWorker.dispose();
```


This makes it easy to spawn Isolates and keep them alive for future jobs

## Additional information

Contributions are welcome
