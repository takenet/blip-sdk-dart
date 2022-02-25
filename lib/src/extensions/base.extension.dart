import 'package:lime/lime.dart';

import '../client.dart';

class BaseExtension {
  final Client client;
  final Node? to;

  BaseExtension(this.client, {this.to});

  Command createGetCommand(String uri, {String? id}) {
    final command = Command(
      id: id,
      method: CommandMethod.get,
      uri: uri,
    );

    if (to != null) {
      command.to = to;
    }

    return command;
  }

  Command createSetCommand(String uri, String? type, resource, {String? id}) {
    final command = Command(id: id, method: CommandMethod.set, uri: uri, resource: resource);

    if (type?.isNotEmpty ?? false) {
      command.type = type;
    }

    if (to != null) {
      command.to = to;
    }

    return command;
  }

  Command createMergeCommand(String uri, String? type, resource, {String? id}) {
    final command = Command(id: id, method: CommandMethod.merge, uri: uri, type: type, resource: resource);

    if (to != null) {
      command.to = to;
    }

    return command;
  }

  Command createDeleteCommand(String uri, {String? id}) {
    final command = Command(id: id, method: CommandMethod.delete, uri: uri);

    if (to != null) {
      command.to = to;
    }

    return command;
  }

  Future<Command> processCommand(final Command command) async => client.sendCommand(command);

  String buildResourceQuery(String uri, Map<String, dynamic> query) {
    var i = 0;
    var options = '';

    for (final key in query.keys) {
      var value = query[key];
      if (value != null) {
        options += i == 0 ? '?' : '&';

        if (value is List) {
          value = value.join(',');
        }

        options += '$key=$value';
        i += 1;
      }
    }

    return '$uri${Uri.encodeFull(options)}';
  }

  String buildUri(String uri, List args) {
    for (int i = 0; i < args.length; i++) {
      final arg = args[i];

      uri = uri.replaceAll('{$i}', Uri.encodeComponent(arg));
    }

    return uri;
  }
}
