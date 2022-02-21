import 'package:lime/lime.dart';
import 'application.dart';
import 'client.dart';

class ClientBuilder {
  Application application;
  Transport transport;

  ClientBuilder({required this.transport}) : application = Application();

  withApplication(Application application) {
    this.application = application;
    return this;
  }

  withIdentifier(String identifier) {
    application.identifier = identifier;
    return this;
  }

  withInstance(String instance) {
    application.instance = instance;
    return this;
  }

  // withDomain :: String -> ClientBuilder
  withDomain(String domain) {
    application.domain = domain;
    return this;
  }

  // withScheme :: String -> ClientBuilder
  withScheme(String scheme) {
    application.scheme = scheme;
    return this;
  }

  // withHostName :: String -> ClientBuilder
  withHostName(String hostName) {
    application.hostName = hostName;
    return this;
  }

  withPort(int port) {
    application.port = port;
    return this;
  }

  withAccessKey(String accessKey) {
    application.authentication = KeyAuthentication(key: accessKey);
    return this;
  }

  withPassword(String password) {
    application.authentication = PlainAuthentication(password: password);
    return this;
  }

  withToken(String token, String issuer) {
    application.authentication = ExternalAuthentication(token: token, issuer: issuer);
    return this;
  }

  // withCompression :: Lime.SessionCompression.NONE -> ClientBuilder
  withCompression(SessionCompression compression) {
    application.compression = compression;
    return this;
  }

  // withEncryption :: Lime.SessionEncryption.NONE -> ClientBuilder
  withEncryption(SessionEncryption encryption) {
    application.encryption = encryption;
    return this;
  }

  withRoutingRule(RoutingRule routingRule) {
    application.presence.routingRule = routingRule;
    return this;
  }

  withEcho(bool echo) {
    application.presence.echo = echo;
    return this;
  }

  withPriority(int priority) {
    application.presence.priority = priority;
    return this;
  }

  withRoundRobin(bool roundRobin) {
    application.presence.roundRobin = roundRobin;
    return this;
  }

  withNotifyConsumed(bool notifyConsumed) {
    application.notifyConsumed = notifyConsumed;
    return this;
  }

  withCommandTimeout(int timeoutInMilliSecs) {
    application.commandTimeout = timeoutInMilliSecs;
    return this;
  }

  build() {
    final uri = '${application.scheme}://${application.hostName}:${application.port}';
    return Client(uri: uri, transport: transport, application: application);
  }
}
