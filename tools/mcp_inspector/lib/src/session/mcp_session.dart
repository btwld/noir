import 'package:mcp_dart/mcp_dart.dart';

import 'protocol_log.dart';

/// The kind of control that presents one generated form field.
enum FormFieldKind {
  /// A single-line string field.
  text,

  /// A single-line field that must parse as a `num`.
  number,

  /// A single-line field that must parse as an `int`.
  integer,

  /// A two-state field.
  boolean,

  /// A closed list of string choices.
  select,

  /// A multi-line field holding raw JSON for a shape the tool cannot map.
  json,
}

/// One generated form field, described without any SDK type.
final class FormFieldSpec {
  /// Creates a field description.
  const FormFieldSpec({
    required this.name,
    required this.kind,
    required this.isRequired,
    this.title,
    this.description,
    this.options = const <String>[],
    this.initialText = '',
    this.initialFlag = false,
  });

  /// The property name sent in the arguments map.
  final String name;

  /// The control that presents this field.
  final FormFieldKind kind;

  /// Whether the schema lists this property as required.
  final bool isRequired;

  /// A human-readable title, when the schema supplies one.
  final String? title;

  /// A human-readable description, when the schema supplies one.
  final String? description;

  /// The closed list of choices for [FormFieldKind.select].
  final List<String> options;

  /// The starting text for every kind except [FormFieldKind.boolean].
  final String initialText;

  /// The starting state for [FormFieldKind.boolean].
  final bool initialFlag;

  /// The label shown beside the control.
  String get label => title ?? name;
}

/// An ordered set of generated form fields.
///
/// A [FormSpec] is the tool's own description of a schema. It is what crosses
/// the session boundary, so the user-interface layer never sees a
/// `package:mcp_dart` schema type.
final class FormSpec {
  /// Creates a specification over an explicit field list.
  const FormSpec(this.fields);

  /// Builds a specification from an MCP input schema.
  ///
  /// A null schema, or any root that is not a JSON object, yields an empty
  /// specification. Object properties keep their declared order.
  factory FormSpec.fromJsonSchema(JsonSchema? schema) {
    if (schema is! JsonObject) return const FormSpec(<FormFieldSpec>[]);
    final properties = schema.properties;
    if (properties == null || properties.isEmpty) {
      return const FormSpec(<FormFieldSpec>[]);
    }
    final required = schema.required ?? const <String>[];
    return FormSpec(<FormFieldSpec>[
      for (final entry in properties.entries)
        _fieldFor(
          entry.key,
          entry.value,
          isRequired: required.contains(entry.key),
        ),
    ]);
  }

  /// Builds a specification from MCP prompt arguments.
  ///
  /// Prompt arguments are named strings, so every field is
  /// [FormFieldKind.text].
  factory FormSpec.fromPromptArguments(List<PromptArgument>? arguments) =>
      FormSpec(<FormFieldSpec>[
        for (final argument in arguments ?? const <PromptArgument>[])
          FormFieldSpec(
            name: argument.name,
            kind: FormFieldKind.text,
            isRequired: argument.required ?? false,
            title: argument.title,
            description: argument.description,
          ),
      ]);

  /// The fields in schema order.
  final List<FormFieldSpec> fields;

  /// Whether this specification has no fields.
  bool get isEmpty => fields.isEmpty;

  /// Whether this specification has at least one field.
  bool get isNotEmpty => fields.isNotEmpty;

  static FormFieldSpec _fieldFor(
    String name,
    JsonSchema schema, {
    required bool isRequired,
  }) {
    final options = _optionsOf(schema);
    final kind = switch (schema) {
      _ when options != null => FormFieldKind.select,
      JsonString() => FormFieldKind.text,
      JsonNumber() => FormFieldKind.number,
      JsonInteger() => FormFieldKind.integer,
      JsonBoolean() => FormFieldKind.boolean,
      _ => FormFieldKind.json,
    };
    final fallback = schema.defaultValue as Object?;
    return FormFieldSpec(
      name: name,
      kind: kind,
      isRequired: isRequired,
      title: schema.title,
      description: schema.description,
      options: options ?? const <String>[],
      initialText: kind == FormFieldKind.boolean || fallback == null
          ? ''
          : '$fallback',
      initialFlag: fallback is bool && fallback,
    );
  }

  static List<String>? _optionsOf(JsonSchema schema) {
    if (schema is JsonEnum) {
      return <String>[for (final value in schema.normalizedValues) '$value'];
    }
    if (schema is JsonString) {
      final values = schema.enumValues;
      if (values != null && values.isNotEmpty) return List<String>.of(values);
    }
    return null;
  }
}

/// Identity of the connected server.
final class McpServerInfo {
  /// Creates server identity.
  const McpServerInfo({required this.name, required this.version, this.title});

  /// The server's programmatic name.
  final String name;

  /// The server's version string.
  final String version;

  /// The server's display title, when it supplies one.
  final String? title;
}

/// One tool offered by the server.
final class McpToolInfo {
  /// Creates a tool summary.
  const McpToolInfo({
    required this.name,
    required this.form,
    this.title,
    this.description,
  });

  /// The tool name used by `tools/call`.
  final String name;

  /// The generated form for this tool's input schema.
  final FormSpec form;

  /// The tool's display title, when it supplies one.
  final String? title;

  /// The tool's description, when it supplies one.
  final String? description;
}

/// One resource offered by the server.
final class McpResourceInfo {
  /// Creates a resource summary.
  const McpResourceInfo({
    required this.uri,
    required this.name,
    this.title,
    this.description,
    this.mimeType,
  });

  /// The resource URI used by `resources/read`.
  final String uri;

  /// The resource's programmatic name.
  final String name;

  /// The resource's display title, when it supplies one.
  final String? title;

  /// The resource's description, when it supplies one.
  final String? description;

  /// The resource's MIME type, when the server reports one.
  final String? mimeType;
}

/// One prompt offered by the server.
final class McpPromptInfo {
  /// Creates a prompt summary.
  const McpPromptInfo({
    required this.name,
    required this.form,
    this.title,
    this.description,
  });

  /// The prompt name used by `prompts/get`.
  final String name;

  /// The generated form for this prompt's arguments.
  final FormSpec form;

  /// The prompt's display title, when it supplies one.
  final String? title;

  /// The prompt's description, when it supplies one.
  final String? description;
}

/// The rendered result of one tool call, resource read, or prompt get.
final class CallOutcome {
  /// Creates an outcome.
  const CallOutcome({
    required this.blocks,
    required this.elapsed,
    this.isError = false,
  });

  /// Creates a failed outcome carrying [message].
  factory CallOutcome.failure(String message, Duration elapsed) =>
      CallOutcome(blocks: <String>[message], elapsed: elapsed, isError: true);

  /// The rendered content blocks, in server order.
  final List<String> blocks;

  /// How long the request took.
  final Duration elapsed;

  /// Whether the server reported an error, or the request itself failed.
  final bool isError;

  /// Every block joined by a blank line, ready for a document view.
  String get text => blocks.join('\n\n');
}

/// What a `notifications/*` message told the client.
enum ServerNoticeKind {
  /// The tool list changed.
  toolsChanged,

  /// The resource list changed.
  resourcesChanged,

  /// The prompt list changed.
  promptsChanged,

  /// One resource changed.
  resourceUpdated,

  /// The server logged a message.
  message,

  /// Any other notification the tool does not model.
  other,
}

/// One `notifications/*` message, reduced to what the screen shows.
final class ServerNotice {
  /// Creates a notice.
  const ServerNotice({
    required this.kind,
    required this.method,
    required this.summary,
  });

  /// What the notification told the client.
  final ServerNoticeKind kind;

  /// The JSON-RPC method of the notification.
  final String method;

  /// A one-line description for the console pane.
  final String summary;
}

/// What the user chose in an elicitation form.
enum ElicitationAction {
  /// The user submitted the form.
  accept,

  /// The user refused the request.
  decline,

  /// The user dismissed the request without deciding.
  cancel,
}

/// A server-initiated request for user input.
final class ElicitationPrompt {
  /// Creates an elicitation prompt.
  const ElicitationPrompt({
    required this.message,
    required this.form,
    this.url,
  });

  /// The server's explanation of why it needs input.
  final String message;

  /// The generated form for the requested schema.
  final FormSpec form;

  /// The URL for a URL-mode elicitation, which this tool does not accept.
  final String? url;
}

/// The user's answer to an [ElicitationPrompt].
final class ElicitationOutcome {
  /// Creates an answer.
  const ElicitationOutcome({required this.action, this.content});

  /// The user chose to submit [content].
  const ElicitationOutcome.accept(Map<String, Object?> this.content)
    : action = ElicitationAction.accept;

  /// The user refused the request.
  const ElicitationOutcome.decline()
    : action = ElicitationAction.decline,
      content = null;

  /// The user dismissed the request.
  const ElicitationOutcome.cancel()
    : action = ElicitationAction.cancel,
      content = null;

  /// What the user chose.
  final ElicitationAction action;

  /// The submitted values, present only for [ElicitationAction.accept].
  final Map<String, Object?>? content;
}

/// Answers one server-initiated [ElicitationPrompt].
typedef ElicitationHandler =
    Future<ElicitationOutcome> Function(ElicitationPrompt prompt);

/// A failure the session reports to the screen verbatim.
final class McpSessionException implements Exception {
  /// Creates a failure describing [message].
  const McpSessionException(this.message);

  /// The text shown to the user.
  final String message;

  @override
  String toString() => message;
}

/// The boundary between the inspector screen and one MCP server.
///
/// Everything this interface returns is a value type owned by this package,
/// so the user-interface layer never depends on `package:mcp_dart`. Tests
/// substitute a fake in place of [McpSession] the same way
/// `example/src/pub_search/catalog.dart` substitutes a fake `PubCatalog`.
abstract interface class McpSession {
  /// Identity of the connected server, or null before [connect] succeeds.
  McpServerInfo? get serverInfo;

  /// The negotiated MCP protocol version, or null before [connect] succeeds.
  String? get protocolVersion;

  /// The capability names the server advertised, such as `tools`.
  Set<String> get capabilities;

  /// The server's usage instructions, when it supplies them.
  String? get instructions;

  /// Every JSON-RPC message this session carries.
  Stream<ProtocolEntry> get protocol;

  /// Every line the server wrote to its standard error stream.
  Stream<String> get console;

  /// Every `notifications/*` message the session did not handle itself.
  Stream<ServerNotice> get notices;

  /// The handler that answers server-initiated input requests.
  ElicitationHandler? get elicitationHandler;

  /// Sets the handler that answers server-initiated input requests.
  set elicitationHandler(ElicitationHandler? value);

  /// Opens the transport and completes the MCP handshake.
  Future<void> connect();

  /// Closes the session and releases every resource it owns.
  Future<void> close();

  /// Lists the server's tools.
  Future<List<McpToolInfo>> listTools();

  /// Lists the server's resources.
  Future<List<McpResourceInfo>> listResources();

  /// Lists the server's prompts.
  Future<List<McpPromptInfo>> listPrompts();

  /// Calls [name] with [arguments].
  Future<CallOutcome> callTool(String name, Map<String, Object?> arguments);

  /// Reads the resource identified by [uri].
  Future<CallOutcome> readResource(String uri);

  /// Gets the prompt [name] with [arguments].
  Future<CallOutcome> getPrompt(String name, Map<String, String> arguments);
}
