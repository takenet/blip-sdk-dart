import 'dart:async';
import 'dart:convert';
import 'package:lime/lime.dart';
import 'application.dart';
import 'client_error.dart';
import 'extensions/base.extension.dart';
import 'extensions/enums/extension_type.enum.dart';
import 'extensions/media/media.extension.dart';
import 'models/listener_model.dart';

const maxConnectionTryCount = 10;

class Client {
  final String uri;
  final Application application;
  final Transport transport;

  final ClientChannel _clientChannel;
  final _notificationListeners = <Listener<Notification>>[];
  final _commandListeners = <Listener<Command>>[];
  final _messageListeners = <Listener<Message>>[];
  final _commandResolves = <String, dynamic>{};
  final _sessionFinishedHandlers = <StreamController>[];
  final _sessionFailedHandlers = <StreamController>[];
  final _extensions = <ExtensionType, BaseExtension>{};

  bool _listening = false;
  bool _closing = false;
  int _connectionTryCount = 0;

  // Client :: String -> Transport? -> Client
  Client({required this.uri, required this.transport, required this.application})
      : _clientChannel = ClientChannel(transport) {
    // sessionPromise = new Promise(() => { });

    _initializeClientChannel();
  }

  // connectWithGuest :: String -> Promise Session
  connectWithGuest(identifier) {
    if (!identifier) throw ArgumentError.notNull('The identifier is required');
    application.identifier = identifier;
    application.authentication = GuestAuthentication();
    return connect();
  }

  // connectWithPassword :: String -> String -> Promise Session
  connectWithPassword(identifier, password, presence) {
    if (!identifier) throw ArgumentError.notNull('The identifier is required');
    if (!password) throw ArgumentError.notNull('The password is required');

    application.identifier = identifier;
    application.authentication = PlainAuthentication(password: password);

    if (presence) application.presence = presence;
    return connect();
  }

  // connectWithKey :: String -> String -> Promise Session
  connectWithKey(identifier, key, presence) {
    if (!identifier) throw ArgumentError.notNull('The identifier is required');
    if (!key) throw ArgumentError.notNull('The key is required');

    application.identifier = identifier;
    application.authentication = KeyAuthentication(key: key);

    if (presence) application.presence = presence;

    return connect();
  }

  connect() {
    if (_connectionTryCount >= maxConnectionTryCount) {
      throw Exception(
          'Could not connect: Max connection try count of $maxConnectionTryCount reached. Please check you network and refresh the page.');
    }

    _connectionTryCount++;
    _closing = false;
    return transport
        .open(uri)
        .then((_) => _clientChannel.establishSession(
              application.identifier + '@' + application.domain,
              application.instance,
              application.authentication,
            ))
        .then((session) => _sendPresenceCommand().then((_) => session))
        .then((session) => _sendReceiptsCommand().then((_) => session))
        .then((session) {
      _listening = true;
      _connectionTryCount = 0;
      return session;
    });
  }

  void _initializeClientChannel() {
    // transport.onClose = () => {
    //     listening = false;
    //     if (!_closing) {
    //         // Use an exponential backoff for the timeout
    //         let timeout = 100 * Math.pow(2, _connectionTryCount);

    //         // try to reconnect after the timeout
    //         setTimeout(() => {
    //             if (!_closing) {
    //                 _transport = _transportFactory();
    //                 _initializeClientChannel();
    //                 connect();
    //             }
    //         }, timeout);
    //     }
    // };

    // onMessage
    _clientChannel.onReceiveMessage.stream.listen((Message message) {
      final shouldNotify = _clientChannel.isForMe(message);

      if (shouldNotify) {
        sendNotification(
          Notification(
            id: message.id,
            to: message.pp ?? message.from,
            event: NotificationEvent.received,
            metadata: {
              '#message.to': message.to,
              '#message.uniqueId': message.metadata?['#uniqueId'],
            },
          ),
        );
      }

      _loop(shouldNotify, message);
    });

    _clientChannel.onReceiveNotification.stream.listen(
      (notification) {
        for (final listener in _notificationListeners) {
          if (listener.filter(notification)) {
            listener.stream.sink.add(notification);
          }
        }
      },
    );

    _clientChannel.onReceiveCommand.stream.listen(
      (Command command) {
        final resolve = _commandResolves[command.id];

        if (resolve != null) {
          resolve(command);
        }

        for (final listener in _commandListeners) {
          if (listener.filter(command)) {
            listener.stream.sink.add(command);
          }
        }
      },
    );

    _clientChannel.onSessionFinished.stream.listen((Session session) {
      for (final stream in _sessionFinishedHandlers) {
        stream.sink.add(session);
      }
    });

    _clientChannel.onSessionFailed.stream.listen((Session session) {
      for (final stream in _sessionFailedHandlers) {
        stream.sink.add(session);
      }
    });

    // sessionPromise = Promise((resolve, reject) {
    //     _clientChannel.onSessionFinished = (s) {
    //         resolve(s);
    //         sessionFinishedHandlers.forEach((handler) => handler(s));
    //     };
    //     _clientChannel.onSessionFailed = (s) {
    //         reject(s);
    //         sessionFailedHandlers.forEach((handler) => handler(s));
    //     };
    // });
  }

  void _loop(final bool shouldNotify, final Message message) {
    try {
      for (final listener in _messageListeners) {
        if (listener.filter(message)) {
          listener.stream.sink.add(message);
        }
      }

      notify(shouldNotify, message);
    } catch (e) {
      notify(shouldNotify, message, error: e);
    }
  }

  bool isForMe(Envelope envelope) => _clientChannel.isForMe(envelope);

  void notify(bool shouldNotify, Message message, {error}) {
    if (shouldNotify && error != null) {
      sendNotification(
        Notification(
          id: message.id,
          to: message.from,
          event: NotificationEvent.failed,
          reason: Reason(code: 101, description: error.message),
        ),
      );
    }

    if (shouldNotify && application.notifyConsumed) {
      sendNotification(
        Notification(id: message.id, to: message.pp ?? message.from, event: NotificationEvent.consumed, metadata: {
          '#message.to': message.to,
          '#message.uniqueId': message.metadata?['#uniqueId'],
        }),
      );
    }
  }

  Future _sendPresenceCommand() async {
    if (application.authentication is GuestAuthentication) {
      return;
    }
    return sendCommand(
      Command(
          id: guid(),
          method: CommandMethod.set,
          uri: '/presence',
          type: 'application/vnd.lime.presence+json',
          resource: application.presence),
    );
  }

  Future _sendReceiptsCommand() async {
    if (application.authentication is GuestAuthentication) {
      return;
    }
    return sendCommand(
      Command(
          id: guid(),
          method: CommandMethod.set,
          uri: '/receipt',
          type: 'application/vnd.lime.receipt+json',
          resource: {
            'events': ['failed', 'accepted', 'dispatched', 'received', 'consumed']
          }),
    );
  }

  // close :: Promise ()
  Future<void> close() async {
    _closing = true;

    if (_clientChannel.state == SessionState.established) {
      await _clientChannel.sendFinishingSession();
    }

    // return Promise.resolve(
    //     sessionPromise
    //         .then(s => s)
    //         .catch(s => Promise.resolve(s))
    // );
  }

  // sendMessage :: Message -> ()
  void sendMessage(Message message) {
    _clientChannel.sendMessage(message);
  }

  // sendNotification :: Notification -> ()
  void sendNotification(Notification notification) {
    _clientChannel.sendNotification(notification);
  }

  // sendCommand :: Command -> Number -> Promise Command
  Future<Command> sendCommand(Command command, {int? timeout}) {
    final commandPromise = Future.any(
      [
        Future<Command>(() {
          final c = Completer<Command>();

          _commandResolves[command.id] = (Command command) {
            _commandResolves.remove(command.id);

            if (command.status == CommandStatus.success) {
              c.complete(command);
            } else {
              c.completeError(ClientError(message: 'Error on sendCommand: ${jsonEncode(command.toJson())}'));
            }
          };

          return c.future;
        }),
        Future(() {
          final c = Completer<Command>();

          Future.delayed(Duration(milliseconds: timeout ?? application.commandTimeout), () {
            return c.completeError(ClientError(message: 'Timeout reached - command: ${jsonEncode(command.toJson())}'));
          });

          return c.future;
        }),
      ],
    );

    _clientChannel.sendCommand(command);
    return commandPromise;
  }

  // // processCommand :: Command -> Number -> Promise Command
  // Future processCommand(Command command, {int? timeout}) {
  //     return _clientChannel.processCommand(command, timeout: timeout ?? application.commandTimeout);
  // }

  // addMessageReceiver :: String -> (Message -> ()) -> Function
  void Function() addMessageListener(StreamController<Message> stream, {bool Function(Message)? filter}) {
    _messageListeners.add(Listener<Message>(stream, filter: filter));

    return () {
      stream.close();
      _messageListeners.removeWhere(filterListener<Message>(stream, filter));
    };
  }

  void clearMessageListeners() {
    _messageListeners.forEach(_closeStream);
    _messageListeners.clear();
  }

  // addCommandListener :: Function -> (Command -> ()) -> Function
  void Function() addCommandListener(StreamController<Command> stream, {bool Function(Command)? filter}) {
    _commandListeners.add(Listener<Command>(stream, filter: filter));

    return () {
      stream.close();
      _commandListeners.removeWhere(filterListener(stream, filter));
    };
  }

  void clearCommandListeners() {
    _commandListeners.forEach(_closeStream);
    _commandListeners.clear();
  }

  // addNotificationListener :: String -> (Notification -> ()) -> Function
  void Function() addNotificationListener(StreamController<Notification> stream,
      {bool Function(Notification)? filter}) {
    _notificationListeners.add(Listener<Notification>(stream, filter: filter));
    return () {
      stream.close();
      _notificationListeners.removeWhere(filterListener(stream, filter));
    };
  }

  void clearNotificationListeners() {
    _notificationListeners.forEach(_closeStream);
    _notificationListeners.clear();
  }

  void Function() addSessionFinishedHandlers(StreamController<Session> stream) {
    _sessionFinishedHandlers.add(stream);
    return () {
      stream.close();
      _sessionFinishedHandlers.removeWhere((element) => element == stream);
    };
  }

  void clearSessionFinishedHandlers() {
    for (var element in _sessionFinishedHandlers) {
      element.close();
    }
    _sessionFinishedHandlers.clear();
  }

  void Function() addSessionFailedHandlers(StreamController<Session> stream) {
    _sessionFailedHandlers.add(stream);
    return () {
      stream.close();
      _sessionFailedHandlers.removeWhere((element) => element == stream);
    };
  }

  void clearSessionFailedHandlers() {
    for (var element in _sessionFailedHandlers) {
      element.close();
    }
    _sessionFailedHandlers.clear();
  }

  bool Function(Listener) filterListener<T extends Envelope>(StreamController stream, bool Function(T)? filter) {
    return (Listener l) => l.stream == stream && l.filter == filter;
  }

  // get listening() {
  //     return _listening;
  // }

  // set listening(listening) {
  //     listening = listening;
  //     if (onListeningChanged) {
  //         onListeningChanged(listening, this);
  //     }
  // }

  void _closeStream(Listener listener) => listener.stream.close();

  T _getExtension<T extends BaseExtension>(ExtensionType type, String to) {
    var _extension = _extensions[type];
    if (_extension == null) {
      switch (type) {
        case ExtensionType.media:
          _extension = MediaExtension(this, to);
          break;
      }

      _extensions[type] = _extension;
    }
    return _extension as T;
  }

  MediaExtension get media => _getExtension<MediaExtension>(ExtensionType.media, application.domain);
}
