Map<String, String> apiAuthHeaders(String token) {
  final normalized = token.trim();
  return normalized.isEmpty ? const {} : {'Authorization': 'Bearer $normalized'};
}
