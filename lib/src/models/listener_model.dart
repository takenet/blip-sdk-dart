import 'dart:async';
import 'package:lime/lime.dart';

class Listener<T extends Envelope> {
  final StreamController<T> stream;
  final bool Function(T) filter;

  Listener(this.stream, {bool Function(T)? filter}) : filter = (filter ?? (T env) => true);
}
