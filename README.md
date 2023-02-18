
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
IManager manager = IManager.create();
```

Then you can add a worker like so

```dart
IWorker worker = manager.addWorker(name: "name");
```

## Additional information

Contributions are welcome
