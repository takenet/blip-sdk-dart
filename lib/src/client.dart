
import 'dart:async';
import 'dart:convert';
import 'package:lime/lime.dart';
import 'application.dart';
import 'client_error.dart';

identity (x) => x;
const maxConnectionTryCount = 10;

class Client {
    final String uri;
    final Application application;
    final Transport transport;

    bool _listening = false;
    bool _closing = false;
    int _connectionTryCount = 0;
    ClientChannel _clientChannel;
    final _messageReceivers = [];
    final _commandResolves = <String, dynamic>{};
    
    // Client :: String -> Transport? -> Client
    Client({required uri, required transport, required application}) : _clientChannel = ClientChannel(transport) {
        _notificationReceivers = [];
        _commandReceivers = [];
        _commandResolves = {};
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

        _clientChannel.onMessage = (message) {
            final shouldNotify =
                message.id &&
                (!message.to || _clientChannel.localNode?.substring(0, message.to.length).toLowerCase() == message.to.toLowerCase());

            if (shouldNotify) {
                sendNotification(Notification(
                    id: message.id,
                    to: message.pp ?? message.from,
                    event: NotificationEvent.received,
                    metadata: {
                        '#message.to': message.to,
                        '#message.uniqueId': message.metadata?['#uniqueId'],
                    },)
                );
            }

            _loop(0, shouldNotify, message);
        };

        _clientChannel.onNotification = (notification) =>
            _notificationReceivers
                .forEach((receiver) => receiver.predicate(notification) && receiver.callback(notification));

        _clientChannel.onCommand = (Command c) {
            (_commandResolves[c.id] || identity)(c);
            _commandReceivers.forEach((receiver) =>
                receiver.predicate(c) && receiver.callback(c));
        };

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

    _loop(i, shouldNotify, message) {
        try {
            if (i < _messageReceivers.length) {
                if (_messageReceivers[i].predicate(message)) {
                    return Promise.resolve(_messageReceivers[i].callback(message))
                        .then((result) {
                            return Promise((resolve, reject) {
                                if (result == false) {
                                    reject();
                                }
                                resolve();
                            });
                        })
                        .then(() => _loop(i + 1, shouldNotify, message));
                }
                else {
                    _loop(i + 1, shouldNotify, message);
                }
            }
            else {
                _notify(shouldNotify, message, null);
            }
        }
        catch (e) {
            _notify(shouldNotify, message, e);
        }
    }

    void _notify(shouldNotify, message, e) {
        if (shouldNotify && e) {
            sendNotification(Notification(
                id: message.id,
                to: message.from,
                event: NotificationEvent.failed,
                reason: Reason(
                    code: 101,
                    description: e.message
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
    addMessageReceiver(predicate, callback) {
        predicate = processPredicate(predicate);

        _messageReceivers.add({ predicate, callback });
        return () {
          _messageReceivers.clear();
          _messageReceivers.addAll(_messageReceivers.where(filterReceiver(predicate, callback)));
        };
    }

    clearMessageReceivers() {
        _messageReceivers.clear();
    }

    // addCommandReceiver :: Function -> (Command -> ()) -> Function
    addCommandReceiver(predicate, callback) {
        predicate = processPredicate(predicate);

        _commandReceivers.push({ predicate, callback });
        return () => _commandReceivers = _commandReceivers.filter(filterReceiver(predicate, callback));
    }

    clearCommandReceivers() {
        _commandReceivers = [];
    }

    // addNotificationReceiver :: String -> (Notification -> ()) -> Function
    addNotificationReceiver(predicate, callback) {
        predicate = processPredicate(predicate);

        _notificationReceivers.push({ predicate, callback });
        return () => _notificationReceivers = _notificationReceivers.filter(filterReceiver(predicate, callback));
    }

    clearNotificationReceivers() {
        _notificationReceivers = [];
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

    processPredicate(predicate) {
        if (typeof predicate !== 'function') {
            if (predicate === true || !predicate) {
                predicate = () => true;
            } else {
                const value = predicate;
                predicate = (envelope) => envelope.event === value || envelope.type === value;
            }
        }

        return predicate;
    }

    filterReceiver(predicate, callback) {
        return (r) => r.predicate != predicate && r.callback != callback;
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