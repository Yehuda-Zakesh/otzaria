import 'package:http/http.dart' as http;
import 'package:otzaria/library_update/services/github_rate_limit.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show PatchNetworkException;

/// משמר כשלים זמניים ככשלי רשת לפני שהמוריד ממפה אותם לנכס פגום.
class SemanticDownloadClient extends http.BaseClient {
  SemanticDownloadClient([http.Client? inner])
    : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    final status = response.statusCode;
    final rateLimit = GithubRateLimitAwareClient.rateLimitExceptionFor(
      status,
      response.headers,
    );
    if (rateLimit == null && status != 408 && status != 429 && status < 500) {
      return response;
    }
    await response.stream.listen((_) {}).cancel();
    if (rateLimit != null) throw rateLimit;
    if (status == 429) throw const GithubRateLimitException();
    throw PatchNetworkException(
      http.ClientException('Vector download returned $status', request.url),
    );
  }

  @override
  void close() => _inner.close();
}
