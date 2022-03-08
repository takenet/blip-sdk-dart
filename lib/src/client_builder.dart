import 'package:lime/lime.dart';
import 'application.dart';
import 'client.dart';

class ClientBuilder {
  Application application;
  Transport transport;

  ClientBuilder({required this.transport}) : application = Application();

  /// Allows you to set a custom application for configuration
  ClientBuilder withApplication(Application application) {
    this.application = application;
    return this;
  }

  /// Sets a identifier
  ClientBuilder withIdentifier(String identifier) {
    application.identifier = identifier;
    return this;
  }

  /// Sets an instance
  ClientBuilder withInstance(String instance) {
    application.instance = instance;
    return this;
  }

  /// Sets a domain
  ClientBuilder withDomain(String domain) {
    application.domain = domain;
    return this;
  }

  /// Sets a scheme
  ClientBuilder withScheme(String scheme) {
    application.scheme = scheme;
    return this;
  }

  /// Sets a host name
  ClientBuilder withHostName(String hostName) {
    application.hostName = hostName;
    return this;
  }

  /// Sets a port
  ClientBuilder withPort(int port) {
    application.port = port;
    return this;
  }

  /// Sets authentication to [KeyAuthentication] type
  ClientBuilder withAccessKey(String accessKey) {
    application.authentication = KeyAuthentication(key: accessKey);
    return this;
  }

  /// Sets authentication to [PlainAuthentication] type
  ClientBuilder withPassword(String password) {
    application.authentication = PlainAuthentication(password: password);
    return this;
  }

  /// Sets authentication to [ExternalAuthentication] type
  ClientBuilder withToken(String token, String issuer) {
    application.authentication =
        ExternalAuthentication(token: token, issuer: issuer);
    return this;
  }

  /// Sets the [SessionCompression]
  ClientBuilder withCompression(SessionCompression compression) {
    application.compression = compression;
    return this;
  }

  /// Sets the [SessionEncryption]
  ClientBuilder withEncryption(SessionEncryption encryption) {
    application.encryption = encryption;
    return this;
  }

  /// Sets the presence routing rule
  ClientBuilder withRoutingRule(RoutingRule routingRule) {
    application.presence.routingRule = routingRule;
    return this;
  }

  /// Sets the presence echo
  ClientBuilder withEcho(bool echo) {
    application.presence.echo = echo;
    return this;
  }

  /// Sets the presence priority
  ClientBuilder withPriority(int priority) {
    application.presence.priority = priority;
    return this;
  }

  /// Sets the presence round robin
  ClientBuilder withRoundRobin(bool roundRobin) {
    application.presence.roundRobin = roundRobin;
    return this;
  }

  /// Send a [Notification] when consume the [Message]
  ClientBuilder withNotifyConsumed(bool notifyConsumed) {
    application.notifyConsumed = notifyConsumed;
    return this;
  }

  /// Set a default timeout
  ClientBuilder withCommandTimeout(int timeoutInMilliSecs) {
    application.commandTimeout = timeoutInMilliSecs;
    return this;
  }

  /// Returns a new instance of SDK Client
  Client build() {
    final uri =
        '${application.scheme}://${application.hostName}:${application.port}';
    return Client(uri: uri, transport: transport, application: application);
  }
}
