import 'package:lime/lime.dart';

import '../../client.dart';
import '../base.extension.dart';
import 'uri_templates.dart';

const postmasterName = 'postmaster';
const postmasterDomain = 'media';

class MediaExtension extends BaseExtension {
  MediaExtension(final Client client, final String domain)
      : super(client,
            to: Node(
                name: postmasterName, domain: '$postmasterDomain.$domain'));

  Future<Command> getUploadToken({bool secure = false}) {
    return processCommand(createGetCommand(
        buildResourceQuery(UriTemplates.mediaUpload, {'secure': secure})));
  }

  Future<Command> refreshMedia(id) {
    return processCommand(
        createGetCommand(buildUri(UriTemplates.refreshMedia, [id])));
  }
}
