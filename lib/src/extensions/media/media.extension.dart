import 'package:lime/lime.dart';

import '../base.extension.dart';
import 'uri_templates.dart';

const postmasterName = 'postmaster';
const postmasterDomain = 'media';

class MediaExtension extends BaseExtension {
  MediaExtension(super.client, final String domain)
      : super(
          to: Node(
            name: postmasterName,
            domain: '$postmasterDomain.$domain',
          ),
        );

  Future<Command> getUploadToken({bool secure = false}) {
    return processCommand(
      buildUploadTokenComand(
        secure: secure,
      ),
    );
  }

  Command buildUploadTokenComand({bool secure = false}) {
    return createGetCommand(
      buildResourceQuery(
        UriTemplates.mediaUpload,
        {
          'secure': secure,
        },
      ),
    );
  }

  Future<Command> refreshMedia(id) {
    return processCommand(
      buildRefreshMediaCommand(id),
    );
  }

  Command buildRefreshMediaCommand(id) {
    return createGetCommand(
      buildUri(
        UriTemplates.refreshMedia,
        [
          id,
        ],
      ),
    );
  }
}
