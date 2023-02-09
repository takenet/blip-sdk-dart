import 'package:lime/lime.dart';
import 'application.dart';
import 'client.dart';

class ClientBuilder {
  Application application;
  Transport transport;
  bool useMtls;
  Future<void> Function()? onConnect;

  ClientBuilder({
    required this.transport,
    this.useMtls = false,
  }) : application = Application();

  /// Allows you to set a custom application for configuration
  ClientBuilder withApplication(final Application application) {
    this.application = application;
    return this;
  }

  /// Sets a identifier
  ClientBuilder withIdentifier(final String identifier) {
    application.identifier = identifier;
    return this;
  }

  /// Sets an instance
  ClientBuilder withInstance(final String instance) {
    application.instance = instance;
    return this;
  }

  /// Sets a domain
  ClientBuilder withDomain(final String domain) {
    application.domain = domain;
    return this;
  }

  /// Sets a scheme
  ClientBuilder withScheme(final String scheme) {
    application.scheme = scheme;
    return this;
  }

  /// Sets a host name
  ClientBuilder withHostName(final String hostName) {
    application.hostName = hostName;
    return this;
  }

  /// Sets a port
  ClientBuilder withPort(final int port) {
    application.port = port;
    return this;
  }

  /// Sets authentication to [KeyAuthentication] type
  ClientBuilder withAccessKey(final String accessKey) {
    application.authentication = KeyAuthentication(key: accessKey);
    return this;
  }

  /// Sets authentication to [PlainAuthentication] type
  ClientBuilder withPassword(final String password) {
    application.authentication = PlainAuthentication(password: password);
    return this;
  }

  /// Sets authentication to [ExternalAuthentication] type
  ClientBuilder withToken(final String token, final String issuer) {
    application.authentication =
        ExternalAuthentication(token: token, issuer: issuer);
    return this;
  }

  /// Sets the [SessionCompression]
  ClientBuilder withCompression(final SessionCompression compression) {
    application.compression = compression;
    return this;
  }

  /// Sets the [SessionEncryption]
  ClientBuilder withEncryption(final SessionEncryption encryption) {
    application.encryption = encryption;
    return this;
  }

  /// Sets the presence routing rule
  ClientBuilder withRoutingRule(final RoutingRule routingRule) {
    application.presence.routingRule = routingRule;
    return this;
  }

  /// Sets the presence echo
  ClientBuilder withEcho(final bool echo) {
    application.presence.echo = echo;
    return this;
  }

  /// Sets the presence priority
  ClientBuilder withPriority(final int priority) {
    application.presence.priority = priority;
    return this;
  }

  /// Sets the presence round robin
  ClientBuilder withRoundRobin(final bool roundRobin) {
    application.presence.roundRobin = roundRobin;
    return this;
  }

  /// Send a [Notification] when consume the [Message]
  ClientBuilder withNotifyConsumed(final bool notifyConsumed) {
    application.notifyConsumed = notifyConsumed;
    return this;
  }

  /// Set a default timeout
  ClientBuilder withCommandTimeout(final int timeoutInMilliSecs) {
    application.commandTimeout = timeoutInMilliSecs;
    return this;
  }

  /// Set a secure connection
  ClientBuilder withMtls(final bool? useMtls) {
    this.useMtls = useMtls ?? false;
    return this;
  }

  /// Set a secure connection
  ClientBuilder withConnectionFunction(
      final Future<void> Function()? onConnect) {
    this.onConnect = onConnect;
    return this;
  }

  /// Returns a new instance of SDK Client
  Client build() {
    final uri =
        '${application.scheme}://${application.hostName}:${application.port}';
    return Client(
      uri: uri,
      transport: transport,
      application: application,
      useMtls: useMtls,
      onConnect: onConnect,
    );
  }
}
