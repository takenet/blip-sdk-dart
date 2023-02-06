import 'dart:async';
import 'dart:math';
import 'package:lime/lime.dart';
import 'application.dart';
import 'extensions/base.extension.dart';
import 'extensions/enums/extension_type.enum.dart';
import 'extensions/media/media.extension.dart';
import 'models/listener_model.dart';

const maxConnectionTryCount = 10;

/// Allows communication between the client application and the server
class Client {
  final String uri;
  final Application application;
  final Transport transport;
  final bool useMtls;

  ClientChannel _clientChannel;
  final _notificationListeners = <Listener<Notification>>[];
  final _commandListeners = <Listener<Command>>[];
  final _messageListeners = <Listener<Message>>[];
  final _commandResolves = <String, dynamic>{};
  final _sessionFinishedHandlers = <StreamController>[];
  final _sessionFailedHandlers = <StreamController>[];
  final _extensions = <ExtensionType, BaseExtension>{};

  late StreamController<bool> onConnectionDone;
  var onListeningChanged = StreamController<bool>();

  bool _listening = false;
  bool _closing = false;
  int _connectionTryCount = 0;

  ClientChannel get clientChannel => _clientChannel;

  Client({
    required this.uri,
    required this.transport,
    required this.application,
    this.useMtls = false,
  }) : _clientChannel = ClientChannel(transport) {
    _initializeClientChannel();
  }

  /// Allows connection with an identifier
  Future<Session> connectWithGuest(String identifier) {
    application.identifier = identifier;
    application.authentication = GuestAuthentication();
    return connect();
  }

  /// Allows connection with an identifier and password
  Future<Session> connectWithPassword(String identifier, String password,
      {Presence? presence}) {
    application.identifier = identifier;
    application.authentication = PlainAuthentication(password: password);

    if (presence != null) application.presence = presence;
    return connect();
  }

  /// Allows connection with an identifier and key
  Future<Session> connectWithKey(String identifier, String key,
      {Presence? presence}) {
    application.identifier = identifier;
    application.authentication = KeyAuthentication(key: key);

    if (presence != null) application.presence = presence;

    return connect();
  }

  /// Starts the process of connecting to the server and establish a session
  Future<Session> connect() async {
    if (_connectionTryCount >= maxConnectionTryCount) {
      throw Exception(
          'Could not connect: Max connection try count of $maxConnectionTryCount reached. Please check you network and refresh the page.');
    }

    _connectionTryCount++;
    _closing = false;
    return transport
        .open(uri, useMtls: useMtls)
        .then(
          (_) => _clientChannel.establishSession(
            application.identifier + '@' + application.domain,
            application.instance,
            application.authentication,
          ),
        )
        .then((session) => _sendPresenceCommand().then((_) => session))
        .then((session) => _sendReceiptsCommand().then((_) => session))
        .then((session) {
      _listening = true;
      _connectionTryCount = 0;
      return session;
    });
  }

  /// Start listening to streams
  void _initializeClientChannel() {
    // Allows Take an action when the connection to the server is closed
    transport.onClose.stream.listen((event) async {
      _listening = false;
      if (!_closing) {
        // Use an exponential backoff for the timeout
        num timeout = 100 * pow(2, _connectionTryCount);

        // try to reconnect after the timeout
        Future.delayed(Duration(milliseconds: timeout.round()), () async {
          if (!_closing) {
            transport.onEnvelope?.close();
            transport.onEnvelope = StreamController<Map<String, dynamic>>();

            transport.onConnectionDone?.close();
            transport.onConnectionDone = StreamController<bool>();

            transport.onClose.close();
            transport.onClose = StreamController<bool>();

            _clientChannel = ClientChannel(transport);

            _initializeClientChannel();

            await connect();
          }
        });
      }
    });

    // Allows executing an action whenever a message type envelope is received by the client
    _clientChannel.onReceiveMessage.stream.listen((Message message) {
      final shouldNotify = _clientChannel.isForMe(message);

      if (shouldNotify) {
        sendNotification(
          Notification(
            id: message.id,
            to: message.pp ?? message.from,
            event: NotificationEvent.received,
            metadata: {
              '#message.to': message.to.toString(),
              '#message.uniqueId': message.metadata?['#uniqueId'],
            },
          ),
        );
      }

      _loop(shouldNotify, message);
    });

    // Allows executing an action whenever a notification type envelope is received by the client
    // Notifies the notification listeners with the received notification
    _clientChannel.onReceiveNotification.stream.listen(
      (notification) {
        for (final listener in _notificationListeners) {
          if (listener.filter(notification)) {
            listener.stream.sink.add(notification);
          }
        }
      },
    );

    // Allows executing an action whenever a command type envelope is received by the client
    // Notifies the command listeners with the received command
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

    // When a session ends in the client, the session finished handlers are notified
    _clientChannel.onSessionFinished.stream.listen((Session session) {
      for (final stream in _sessionFinishedHandlers) {
        stream.sink.add(session);
      }
    });

    // When a session failed in the client, the session failed handlers are notified
    _clientChannel.onSessionFailed.stream.listen((Session session) {
      for (final stream in _sessionFailedHandlers) {
        stream.sink.add(session);
      }
    });

    onConnectionDone = _clientChannel.onConnectionDone;
  }

  /// Notifies the [Message] listeners with the received [Message]
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

  /// Sends a [Notification] with the received [Message] data
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
        Notification(
          id: message.id,
          to: message.pp ?? message.from,
          event: NotificationEvent.consumed,
          metadata: {
            '#message.to': message.to.toString(),
            '#message.uniqueId': message.metadata?['#uniqueId'],
          },
        ),
      );
    }
  }

  /// Sends a presence [Command]
  Future<Command?> _sendPresenceCommand() async {
    if (application.authentication is GuestAuthentication) {
      return null;
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

  /// Sends a receipts [Command]
  Future<Command?> _sendReceiptsCommand() async {
    if (application.authentication is GuestAuthentication) {
      return null;
    }
    return sendCommand(
      Command(
          id: guid(),
          method: CommandMethod.set,
          uri: '/receipt',
          type: 'application/vnd.lime.receipt+json',
          resource: {
            'events': [
              'failed',
              'accepted',
              'dispatched',
              'received',
              'consumed',
            ]
          }),
    );
  }

  /// Sends an [Envelope] to finish a [Session]
  Future<Session?> close() async {
    Session? result;
    _closing = true;

    if (_clientChannel.state == SessionState.established &&
        transport.socket?.closeCode == null) {
      result = await _clientChannel.sendFinishingSession();
    }

    onListeningChanged.close();
    onListeningChanged = StreamController<bool>();

    _clientChannel.onConnectionDone.close();
    _clientChannel.onConnectionDone = StreamController<bool>();
    onConnectionDone = _clientChannel.onConnectionDone;

    await transport.close();

    return result;
  }

  /// Allows sending a [Message] type [Envelope]
  void sendMessage(Message message) {
    _clientChannel.sendMessage(message);
  }

  /// Allows sending a [Notification] type [Envelope]
  void sendNotification(Notification notification) {
    _clientChannel.sendNotification(notification);
  }

  /// Allows sending a [Command] type [Envelope]
  Future<Command> sendCommand(Command command, {int? timeout}) {
    final commandPromise = Future.any(
      [
        // A future that will be resolved when the envelope is successful received by the client
        Future<Command>(() {
          final c = Completer<Command>();

          _commandResolves[command.id] = (Command command) {
            _commandResolves.remove(command.id);

            if (command.status == CommandStatus.success) {
              c.complete(command);
            } else {
              c.completeError(
                LimeException(
                  command.status!,
                  command.reason!.code,
                  description: command.reason!.description,
                ),
              );
            }
          };

          return c.future;
        }),
        // A future that will be resolved if time out happens
        Future(() {
          final c = Completer<Command>();

          Future.delayed(
            Duration(milliseconds: timeout ?? application.commandTimeout),
            () {
              command.status = CommandStatus.failure;
              return c.completeError(
                LimeException(
                  command.status!,
                  ReasonCodes.timeoutError,
                  description: 'Timeout Reached',
                ),
              );
            },
          );

          return c.future;
        }),
      ],
    );

    _clientChannel.sendCommand(command);
    return commandPromise;
  }

  /// Allow to add a new [Message] listeners, returns a function that can be called to delete this listener from the list
  void Function() addMessageListener(
    StreamController<Message> stream, {
    bool Function(Message)? filter,
  }) {
    _messageListeners.add(Listener<Message>(stream, filter: filter));

    return () {
      stream.close();
      _messageListeners.removeWhere(filterListener<Message>(stream, filter));
    };
  }

  /// Clean all [Message] listeners
  void clearMessageListeners() {
    _messageListeners.forEach(_closeStream);
    _messageListeners.clear();
  }

  /// Allow to add a new [Command] listeners, returns a function that can be called to delete this listener from the list
  void Function() addCommandListener(StreamController<Command> stream,
      {bool Function(Command)? filter}) {
    _commandListeners.add(Listener<Command>(stream, filter: filter));

    return () {
      stream.close();
      _commandListeners.removeWhere(filterListener(stream, filter));
    };
  }

  /// Clear all [Command] listeners
  void clearCommandListeners() {
    _commandListeners.forEach(_closeStream);
    _commandListeners.clear();
  }

  /// Allow to add a new [Notification] listeners, returns a function that can be called to delete this listener from the list
  void Function() addNotificationListener(StreamController<Notification> stream,
      {bool Function(Notification)? filter}) {
    _notificationListeners.add(Listener<Notification>(stream, filter: filter));

    return () {
      stream.close();
      _notificationListeners.removeWhere(filterListener(stream, filter));
    };
  }

  /// Clear all [Notification] listeners
  void clearNotificationListeners() {
    _notificationListeners.forEach(_closeStream);
    _notificationListeners.clear();
  }

  /// Allows adding listerner that will be notified when a [Session] ends
  void Function() addSessionFinishedHandlers(StreamController<Session> stream) {
    _sessionFinishedHandlers.add(stream);
    return () {
      stream.close();
      _sessionFinishedHandlers.removeWhere((element) => element == stream);
    };
  }

  /// Clear all [Session] finished handlers
  void clearSessionFinishedHandlers() {
    for (var element in _sessionFinishedHandlers) {
      element.close();
    }
    _sessionFinishedHandlers.clear();
  }

  /// Allows adding listerner that will be notified when a [Session] failed
  void Function() addSessionFailedHandlers(StreamController<Session> stream) {
    _sessionFailedHandlers.add(stream);
    return () {
      stream.close();
      _sessionFailedHandlers.removeWhere((element) => element == stream);
    };
  }

  /// Clear all [Session] failed handlers
  void clearSessionFailedHandlers() {
    for (var element in _sessionFailedHandlers) {
      element.close();
    }
    _sessionFailedHandlers.clear();
  }

  /// A function to filter a listener
  bool Function(Listener<T>) filterListener<T extends Envelope>(
      StreamController<T> stream, bool Function(T)? filter) {
    return (Listener<T> l) => l.stream == stream && l.filter == filter;
  }

  /// Returns the current value of listening variable
  bool get listening => _listening;

  /// Returns the current value of listening variable
  bool get closing => _closing;

  /// Allows Change the listening value and notify your listeners
  set listening(bool listening) {
    _listening = listening;

    onListeningChanged.sink.add(listening);
  }

  /// Close a [Stream]
  void _closeStream(Listener listener) => listener.stream.close();

  /// Allows to get a extension
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

  /// Returns a media extension
  MediaExtension get media =>
      _getExtension<MediaExtension>(ExtensionType.media, application.domain);
}
