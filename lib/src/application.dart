import 'package:lime/lime.dart';

class Application {
  String identifier;
  SessionCompression compression;
  SessionEncryption encryption;
  String instance;
  String domain;
  String scheme;
  String hostName;
  int port;
  Presence presence;
  bool notifyConsumed;
  Authentication authentication;
  int commandTimeout;

  Application({
    String? identifier,
    this.compression = SessionCompression.none,
    this.encryption = SessionEncryption.none,
    this.instance = 'default',
    this.domain = 'msging.net',
    this.scheme = 'wss',
    this.hostName = 'ws.msging.net',
    this.port = 443,
    Presence? presence,
    this.notifyConsumed = true,
    Authentication? authentication,
    this.commandTimeout = 6000,
  })  : identifier = identifier ?? guid(),
        presence = presence ?? Presence(status: PresenceStatus.available, routingRule: RoutingRule.identity),
        authentication = authentication ?? GuestAuthentication();
}
