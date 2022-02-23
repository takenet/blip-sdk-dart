
import 'dart:async';
import 'dart:convert';
import 'package:lime/lime.dart';
import 'application.dart';
import 'client_error.dart';
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

    bool _listening = false;
    bool _closing = false;
    int _connectionTryCount = 0;
    
    // Client :: String -> Transport? -> Client
    Client({required uri, required transport, required application}) : _clientChannel = ClientChannel(transport) {
        sessionPromise = new Promise(() => { });
        sessionFinishedHandlers = [];
        sessionFailedHandlers = [];

        _initializeClientChannel();

        _extensions = {};
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
            throw Exception('Could not connect: Max connection try count of $maxConnectionTryCount reached. Please check you network and refresh the page.');
        }

        _connectionTryCount++;
        _closing = false;
        return transport
            .open(uri)
            .then((_) => _clientChannel.establishSession(
                application.identifier + '@' + application.domain,
                application.instance,
                application.authentication,))
            .then((session) => _sendPresenceCommand().then((_) => session))
            .then((session) => _sendReceiptsCommand().then((_) => session))
            .then((session) {
                _listening = true;
                _connectionTryCount = 0;
                return session;
            });
    }

    _initializeClientChannel() {
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
                sendNotification(Notification(
                    id: message.id,
                    to: message.pp ?? message.from,
                    event: NotificationEvent.received,
                    metadata: {
                        '#message.to': message.to,
                        '#message.uniqueId': message.metadata?['#uniqueId'],
                    },),
                );
            }

            _loop(shouldNotify, message);
        });

        _clientChannel.onReceiveNotification.stream.listen((notification) {
            for (final listener in _notificationListeners) {
              if(listener.filter(notification)) listener.stream.sink.add(notification);
            }
        },);

        _clientChannel.onReceiveCommand.stream.listen((Command command) {
            final resolve = _commandResolves[command.id];
            
            if (resolve != null) {
              resolve(command);
            }

            for(final listener in _commandListeners) {
              if (listener.filter(command)) {
                listener.stream.sink.add(command);
              }
            }
        },);

        sessionPromise = Promise((resolve, reject) {
            _clientChannel.onSessionFinished = (s) {
                resolve(s);
                sessionFinishedHandlers.forEach((handler) => handler(s));
            };
            _clientChannel.onSessionFailed = (s) {
                reject(s);
                sessionFailedHandlers.forEach((handler) => handler(s));
            };
        });
    }

    _loop(final bool shouldNotify, final Message message) {
        try {
          for(final listener in _messageListeners) {
            if(listener.filter(message)) {
              listener.stream.sink.add(message);
            }
          }

          notify(shouldNotify, message);
        }catch(e) {
          notify(shouldNotify, message, error: e);
        }
    }

    bool isForMe(Envelope envelope) => _clientChannel.isForMe(envelope);

    void notify(bool shouldNotify, Message message, {error}) {
        if (shouldNotify && error != null) {
            sendNotification(Notification(
                id: message.id,
                to: message.from,
                event: NotificationEvent.failed,
                reason: Reason(
                    code: 101,
                    description: error.message
                ),
            ),);
        }

        if (shouldNotify && application.notifyConsumed) {
            sendNotification(Notification(
                id: message.id,
                to: message.pp ?? message.from,
                event: NotificationEvent.consumed,
                metadata: {
                    '#message.to': message.to,
                    '#message.uniqueId': message.metadata?['#uniqueId'],
                }
            ),);
        }
    }

    Future _sendPresenceCommand() async {
        if (application.authentication is GuestAuthentication) {
            return;
        }
        return sendCommand(Command(
            id: guid(),
            method: CommandMethod.set,
            uri: '/presence',
            type: 'application/vnd.lime.presence+json',
            resource: application.presence
        ),);
    }

    Future _sendReceiptsCommand() async {
        if (application.authentication is GuestAuthentication) {
            return;
        }
        return sendCommand(Command(
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
                    'consumed'
                ]
            }
        ),);
    }

    _getExtension(type, {to}) {
        let extension = _extensions[type];
        if (!extension) {
            extension = new type(this, to);
            _extensions[type] = extension;
        }
        return extension;
    }

    // close :: Promise ()
    Future close() {
        _closing = true;

        if (_clientChannel.state == SessionState.established) {
            return _clientChannel.sendFinishingSession();
        }

        return Promise.resolve(
            sessionPromise
                .then(s => s)
                .catch(s => Promise.resolve(s))
        );
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
    Future<Command?> sendCommand(Command command, {int? timeout}) {
        final commandPromise = Future.any([
            Future<Command?>(() {
                final _completer = Completer<Command>();

                _commandResolves[command.id] = (Command c) {
                    if (c.status == null) return _completer.future;
                  
                    _commandResolves.remove(command.id);

                    if (c.status == CommandStatus.success) {
                        return Future.value(c);
                    }
                    
                    final cmd = jsonEncode(c);
                    return Future.error(ClientError(message: cmd));
                    
                };
            }),
            Future<Command?>(() {
              final _completer = Completer<Command>();

                Future.delayed(Duration(milliseconds: timeout ?? application.commandTimeout,),() {
                    if (_commandResolves[command.id] == null) return _completer.future;

                    _commandResolves.remove(command.id);
                    command.status = CommandStatus.failure;
                    
                    /// TODO: Review this attribuition
                    // command.timeout = true;

                    final cmd = jsonEncode(command);
                    return Future.error(ClientError(message: cmd));
                });
            }),
        ]);

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

    clearMessageListeners() {
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

    clearCommandListeners() {
        _commandListeners.forEach(_closeStream);
        _commandListeners.clear();
    }

    // addNotificationListener :: String -> (Notification -> ()) -> Function
    void Function() addNotificationListener(StreamController<Notification> stream, {bool Function(Notification)? filter}) {
        _notificationListeners.add(Listener<Notification>(stream, filter: filter));
        return () {
          stream.close();
          _notificationListeners.removeWhere(filterListener(stream, filter));
        };
    }

    clearNotificationListeners() {
      _notificationListeners.forEach(_closeStream);
      _notificationListeners.clear();
    }

    addSessionFinishedHandlers(callback) {
        sessionFinishedHandlers.push(callback);
        return () => sessionFinishedHandlers = sessionFinishedHandlers.filter(filterReceiver(null, callback));
    }

    clearSessionFinishedHandlers() {
        sessionFinishedHandlers = [];
    }

    addSessionFailedHandlers(callback) {
        sessionFailedHandlers.push(callback);
        return () => sessionFailedHandlers = sessionFailedHandlers.filter(filterReceiver(null, callback));
    }

    clearSessionFailedHandlers() {
        sessionFailedHandlers = [];
    }

    // processPredicate(predicate) {
    //     if (typeof predicate !== 'function') {
    //         if (predicate === true || !predicate) {
    //             predicate = () => true;
    //         } else {
    //             const value = predicate;
    //             predicate = (envelope) => envelope.event === value || envelope.type === value;
    //         }
    //     }

    //     return predicate;
    // }

    filterListener<T extends Envelope>(StreamController stream, bool Function(T)? filter) {
        return (Listener l) => l.stream == stream && l.filter == filter;
    }

    get listening() {
        return _listening;
    }

    set listening(listening) {
        listening = listening;
        if (onListeningChanged) {
            onListeningChanged(listening, this);
        }
    }

    void _closeStream(Listener listener) => listener.stream.close();

    get ArtificialIntelligence() {
        return _getExtension(ArtificialIntelligenceExtension, _application.domain);
    }

    get Media() {
        return _getExtension(MediaExtension, _application.domain);
    }

    get Chat() {
        return _getExtension(ChatExtension);
    }
}