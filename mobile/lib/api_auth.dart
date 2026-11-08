import 'dart:async';
import 'dart:io';

Map<String, String> apiAuthHeaders(String token) {
  final normalized = token.trim();
  return normalized.isEmpty ? const {} : {'Authorization': 'Bearer $normalized'};
}

typedef SessionExpiredCallback = void Function(String token);

class ApiRequestException implements Exception {
  const ApiRequestException(this.statusCode);
  final int statusCode;
  String get safeMessage => switch (statusCode) {
    401 => 'Phiên đăng nhập đã hết hạn hoặc bị thu hồi. Vui lòng đăng nhập lại.',
    403 => 'Bạn không có quyền thực hiện thao tác này.',
    404 => 'Không tìm thấy tài nguyên hoặc API được yêu cầu.',
    409 => 'Dữ liệu đang xung đột hoặc đã tồn tại.',
    422 => 'Dữ liệu gửi lên chưa hợp lệ.',
    429 => 'Bạn thao tác quá thường xuyên. Vui lòng thử lại sau.',
    >= 500 => 'Máy chủ đang gặp sự cố. Vui lòng thử lại sau.',
    _ => 'Yêu cầu không thành công (HTTP $statusCode).',
  };
}

class SafeApiException implements Exception {
  const SafeApiException(this.safeMessage);
  final String safeMessage;
}

String safeApiErrorMessage(Object error, {required String fallback}) {
  if (error is ApiRequestException) return error.safeMessage;
  if (error is SafeApiException) return error.safeMessage;
  if (error is TimeoutException || error is SocketException) {
    return 'Không thể kết nối máy chủ. Vui lòng kiểm tra mạng và thử lại.';
  }
  return fallback;
}
