class ClientError extends Error {
  final String message;

  ClientError({required this.message});
}
