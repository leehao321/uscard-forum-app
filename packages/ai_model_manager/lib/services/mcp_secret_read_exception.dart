/// 读不到已保存的凭据（Token、请求头）。不能当成「没有凭据」继续请求，也不能把它写回去。
class McpSecretReadException implements Exception {
  const McpSecretReadException([this.message = '读不到已保存的 Token']);

  final String message;

  @override
  String toString() => message;
}
