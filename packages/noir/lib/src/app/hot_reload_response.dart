import 'package:meta/meta.dart';

/// Whether the Noir reassemble service extension explicitly rebuilt its app.
@internal
bool hotReloadResponseSucceeded(Map<String, dynamic>? response) =>
    response?['reassembled'] == true;
