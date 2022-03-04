# BLip SDK

> Simple BLiP SDK for Flutter

[![pub version](https://img.shields.io/pub/v/blip_sdk.svg)](https://pub.dev/packages/blip_sdk)
[![Test Status](https://github.com/takenet/blip-sdk-dart/actions/workflows/tests.yml/badge.svg)](https://github.com/takenet/blip-sdk-dart/actions)

---

Read more about BLiP [here](https://blip.ai/)

### Installing

#### Flutter

Simply install the `blip_sdk` package from the [pub.dev](pub.dev) registry, to access the BLiP server:

    flutter pub add blip_sdk

### Instantiate the BlipSdk Client

You will need an `identifier` and an `access key` to connect a chatbot to **BLiP**. To get them:

- Go to [Painel BLiP](https://portal.blip.ai/) and login;
- Click **Create chatbot**;
- Choose the `Create from scratch` model option;
- Go to **Settings** and click in **Connection Information**;
- Get your bot's `identifier` and `access key`.

In order to instantiate the client use the `ClientBuilder` class informing the `identifier` and `access key`:

```dart
import 'package:blip_sdk/blip_sdk.dart';

// Create a client instance passing the identifier and access key of your chatbot
final client = ClientBuilder(transport: WebSocketTransport())
    .withIdentifier(IDENTIFIER)
    .withAccessKey(ACCESS_KEY)
    .build();

// Connect with the server asynchronously
// Connection will occurr via websocket on the 8081 port
final Session session = await client.connect().catch((err) { /* Connection failed */ });
/// session.state...

```

Each `client` instance represents a server connection and can be reused. To close a connection:

```dart
final Session session = client.close().catch(function(err) { /* Disconnection failed */ });
```

### Receiving

All messages sent to the chatbot are redirected to registered `receivers` of messages and notifications. You can define filters to specify which envelopes will be handled by each receiver.
The following example shows how to add a simple message receiver:

```dart
final onMessageListener = StreamController<Message>();

client.addMessageListener(onMessageListener);

onMessageListener.stream.listen((Message message) {
  // Process received message
});
```

The next sample shows how to add a notification listener with a filter for the `received` event type:

```dart
final onNotificationListener = StreamController<Notification>();

client.addNotificationListener(onNotificationListener, filters: (Notification notification) => notification.event == NotificationEvent.received);

onNotificationListener.stream.listen((Notification message) {
  // Process received notification
});
```

It's also possible to use a custom function as a filter:

Example of a message listener filtering by the originator:

```dart
final onMessageListener = StreamController<Message>();

client.addMessageListener(onMessageListener, filters: (Message message) => message.from == Node.parse('553199990000@0mn.io'));

onMessageListener.stream.listen((Message message) {
  // Process received message
});
```

Each registration of a listener returns a `handler` that can be used to cancel the registration:

```dart
final removeListener = client.addMessageReceiver(stream, filters: (Message message) => message.type == 'application/json');
// ...
removeListener();
```

### Sending

It's possible to send notifications and messages only after the session has been stablished.

The following sample shows how to send a message after the connection has been stablished:

```dart
final Session session = await client.connect();

final msg = Message(type: 'text/plain', content: 'Hello, world', to: Node.parse('553199990000@0mn.io'));
client.sendMessage(msg);
```

The following sample shows how to send a notification after the connection has been stablished:

```dart
final Session session = await client.connect();

// Sending a "received" notification
final notification = Notification(id: 'ef16284d-09b2-4d91-8220-74008f3a5788', to: Node.parse('553199990000@0mn.io'), event: NotificationEvent.received);
client.sendNotification(notification);
```

## Contributing

For information on how to contribute to this package, please refer to our [Contribution guidelines](https://github.com/takenet/blip-sdk-dart/blob/master/CONTRIBUTING.md).
