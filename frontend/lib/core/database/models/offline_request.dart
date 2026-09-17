/// A pending API request stored for offline queueing.
///
/// When the device is offline, requests are stored here and replayed
/// when connectivity is restored.
class OfflineRequest {
  const OfflineRequest({
    this.id,
    required this.method,
    required this.path,
    this.body,
    this.headers,
    this.createdAt,
    this.retryCount = 0,
    this.maxRetries = 3,
    this.status = OfflineRequestStatus.pending,
    this.errorMessage,
  });

  final int? id;
  final String method;
  final String path;
  final String? body;
  final String? headers;
  final DateTime? createdAt;
  final int retryCount;
  final int maxRetries;
  final OfflineRequestStatus status;
  final String? errorMessage;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'method': method,
        'path': path,
        'body': body,
        'headers': headers,
        'created_at': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
        'retry_count': retryCount,
        'max_retries': maxRetries,
        'status': status.value,
        'error_message': errorMessage,
      };

  factory OfflineRequest.fromMap(Map<String, dynamic> map) => OfflineRequest(
        id: map['id'] as int?,
        method: map['method'] as String,
        path: map['path'] as String,
        body: map['body'] as String?,
        headers: map['headers'] as String?,
        createdAt: map['created_at'] != null
            ? DateTime.parse(map['created_at'] as String)
            : null,
        retryCount: map['retry_count'] as int? ?? 0,
        maxRetries: map['max_retries'] as int? ?? 3,
        status: OfflineRequestStatus.fromString(map['status'] as String? ?? 'pending'),
        errorMessage: map['error_message'] as String?,
      );

  OfflineRequest copyWith({
    int? id,
    String? method,
    String? path,
    String? body,
    String? headers,
    DateTime? createdAt,
    int? retryCount,
    int? maxRetries,
    OfflineRequestStatus? status,
    String? errorMessage,
  }) =>
      OfflineRequest(
        id: id ?? this.id,
        method: method ?? this.method,
        path: path ?? this.path,
        body: body ?? this.body,
        headers: headers ?? this.headers,
        createdAt: createdAt ?? this.createdAt,
        retryCount: retryCount ?? this.retryCount,
        maxRetries: maxRetries ?? this.maxRetries,
        status: status ?? this.status,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  bool get canRetry => retryCount < maxRetries;
  bool get isPending => status == OfflineRequestStatus.pending;
  bool get isFailed => status == OfflineRequestStatus.failed;
  bool get isCompleted => status == OfflineRequestStatus.completed;
}

enum OfflineRequestStatus {
  pending('pending'),
  inProgress('in_progress'),
  completed('completed'),
  failed('failed');

  const OfflineRequestStatus(this.value);
  final String value;

  factory OfflineRequestStatus.fromString(String value) {
    return OfflineRequestStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => OfflineRequestStatus.pending,
    );
  }
}
