import 'package:lime/lime.dart';
import 'application.dart';
import 'client.dart';

class ClientBuilder {
  Application application;
  Transport transport;

  ClientBuilder({required this.transport}) : application = Application();

  ClientBuilder withApplication(Application application) {
    this.application = application;
    return this;
  }

  ClientBuilder withIdentifier(String identifier) {
    application.identifier = identifier;
    return this;
  }

  ClientBuilder withInstance(String instance) {
    application.instance = instance;
    return this;
  }

  // withDomain :: String -> ClientBuilder
  ClientBuilder withDomain(String domain) {
    application.domain = domain;
    return this;
  }

  // withScheme :: String -> ClientBuilder
  ClientBuilder withScheme(String scheme) {
    application.scheme = scheme;
    return this;
  }

  // withHostName :: String -> ClientBuilder
  ClientBuilder withHostName(String hostName) {
    application.hostName = hostName;
    return this;
  }

  ClientBuilder withPort(int port) {
    application.port = port;
    return this;
  }

  ClientBuilder withAccessKey(String accessKey) {
    application.authentication = KeyAuthentication(key: accessKey);
    return this;
  }

  ClientBuilder withPassword(String password) {
    application.authentication = PlainAuthentication(password: password);
    return this;
  }

  ClientBuilder withToken(String token, String issuer) {
    application.authentication =
        ExternalAuthentication(token: token, issuer: issuer);
    return this;
  }

  // withCompression :: Lime.SessionCompression.NONE -> ClientBuilder
  ClientBuilder withCompression(SessionCompression compression) {
    application.compression = compression;
    return this;
  }

  // withEncryption :: Lime.SessionEncryption.NONE -> ClientBuilder
  ClientBuilder withEncryption(SessionEncryption encryption) {
    application.encryption = encryption;
    return this;
  }

  ClientBuilder withRoutingRule(RoutingRule routingRule) {
    application.presence.routingRule = routingRule;
    return this;
  }

  ClientBuilder withEcho(bool echo) {
    application.presence.echo = echo;
    return this;
  }

  ClientBuilder withPriority(int priority) {
    application.presence.priority = priority;
    return this;
  }

  ClientBuilder withRoundRobin(bool roundRobin) {
    application.presence.roundRobin = roundRobin;
    return this;
  }

  ClientBuilder withNotifyConsumed(bool notifyConsumed) {
    application.notifyConsumed = notifyConsumed;
    return this;
  }

  ClientBuilder withCommandTimeout(int timeoutInMilliSecs) {
    application.commandTimeout = timeoutInMilliSecs;
    return this;
  }

  Client build() {
    final uri =
        '${application.scheme}://${application.hostName}:${application.port}';
    return Client(uri: uri, transport: transport, application: application);
  }
}
