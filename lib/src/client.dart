
import 'package:lime/lime.dart';
import 'application.dart';

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
    
    // Client :: String -> Transport? -> Client
    Client({required this.uri, required this.transport, required this.application}) : _clientChannel = ClientChannel(transport) {
        this._messageReceivers = [];
        this._notificationReceivers = [];
        this._commandReceivers = [];
        this._commandResolves = {};
        this.sessionPromise = new Promise(() => { });
        this.sessionFinishedHandlers = [];
        this.sessionFailedHandlers = [];

        _initializeClientChannel();

        this._extensions = {};
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
        //     this.listening = false;
        //     if (!this._closing) {
        //         // Use an exponential backoff for the timeout
        //         let timeout = 100 * Math.pow(2, _connectionTryCount);

        //         // try to reconnect after the timeout
        //         setTimeout(() => {
        //             if (!this._closing) {
        //                 this._transport = this._transportFactory();
        //                 this._initializeClientChannel();
        //                 this.connect();
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

        _clientChannel.onCommand = (c) {
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

    _getExtension(type, to = null) {
        let extension = this._extensions[type];
        if (!extension) {
            extension = new type(this, to);
            this._extensions[type] = extension;
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
            this.sessionPromise
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
    Future sendCommand(Command command, {int? timeout}) {
        var commandPromise = Promise.race([
            new Promise((resolve, reject) => {
                this._commandResolves[command.id] = (c) => {
                    if (!c.status)
                        return;

                    if (c.status === Lime.CommandStatus.SUCCESS) {
                        resolve(c);
                    }
                    else {
                        const cmd = JSON.stringify(c);
                        reject(new ClientError(cmd));
                    }

                    delete this._commandResolves[command.id];
                };
            }),
            new Promise((_, reject) => {
                setTimeout(() => {
                    if (!this._commandResolves[command.id])
                        return;

                    delete this._commandResolves[command.id];
                    command.status = 'failure';
                    command.timeout = true;

                    const cmd = JSON.stringify(command);
                    reject(new ClientError(cmd));
                }, timeout);
            })
        ]);

        this._clientChannel.sendCommand(command);
        return commandPromise;
    }

    // processCommand :: Command -> Number -> Promise Command
    processCommand(command, timeout = this._application.commandTimeout) {
        return this._clientChannel.processCommand(command, timeout);
    }

    // addMessageReceiver :: String -> (Message -> ()) -> Function
    addMessageReceiver(predicate, callback) {
        predicate = this.processPredicate(predicate);

        this._messageReceivers.push({ predicate, callback });
        return () => this._messageReceivers = this._messageReceivers.filter(this.filterReceiver(predicate, callback));
    }

    clearMessageReceivers() {
        this._messageReceivers = [];
    }

    // addCommandReceiver :: Function -> (Command -> ()) -> Function
    addCommandReceiver(predicate, callback) {
        predicate = this.processPredicate(predicate);

        this._commandReceivers.push({ predicate, callback });
        return () => this._commandReceivers = this._commandReceivers.filter(this.filterReceiver(predicate, callback));
    }

    clearCommandReceivers() {
        this._commandReceivers = [];
    }

    // addNotificationReceiver :: String -> (Notification -> ()) -> Function
    addNotificationReceiver(predicate, callback) {
        predicate = this.processPredicate(predicate);

        this._notificationReceivers.push({ predicate, callback });
        return () => this._notificationReceivers = this._notificationReceivers.filter(this.filterReceiver(predicate, callback));
    }

    clearNotificationReceivers() {
        this._notificationReceivers = [];
    }

    addSessionFinishedHandlers(callback) {
        this.sessionFinishedHandlers.push(callback);
        return () => this.sessionFinishedHandlers = this.sessionFinishedHandlers.filter(this.filterReceiver(null, callback));
    }

    clearSessionFinishedHandlers() {
        this.sessionFinishedHandlers = [];
    }

    addSessionFailedHandlers(callback) {
        this.sessionFailedHandlers.push(callback);
        return () => this.sessionFailedHandlers = this.sessionFailedHandlers.filter(this.filterReceiver(null, callback));
    }

    clearSessionFailedHandlers() {
        this.sessionFailedHandlers = [];
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
        return r => r.predicate !== predicate && r.callback !== callback;
    }

    get listening() {
        return this._listening;
    }

    set listening(listening) {
        listening = listening;
        if (this.onListeningChanged) {
            this.onListeningChanged(listening, this);
        }
    }

    get ArtificialIntelligence() {
        return this._getExtension(ArtificialIntelligenceExtension, this._application.domain);
    }

    get Media() {
        return this._getExtension(MediaExtension, this._application.domain);
    }

    get Chat() {
        return this._getExtension(ChatExtension);
    }
}

class ClientError extends Error {
    constructor(message) {
        super();

        this.name = '';
        this.message = message;
    }
}