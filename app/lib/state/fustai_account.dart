/// Fustai 账号登录，PKCE 全程在 App 内完成：回环回调是本进程自己起的
/// [HttpServer]，授权码、账号 token 和模型密钥都不经过本机引擎。
///
/// 线上协议（账号中心，响应信封 `{code, data:{biz_code, biz_data}}`）：
/// ```text
/// POST /auth-api/v0/dsh/auth_init     {code_challenge, code_challenge_method, state,
///                                      redirect_uri, locale, login_source}
///   -> {authorize_url, authorize_id, expires_in}
/// GET  {callbackOrigin}/oauth/callback?code&state
/// POST /auth-api/v0/dsh/auth_exchange {code, code_verifier, redirect_uri}
///   -> {token, authorized_url, user:{id,email,mobile,id_profile:{name,picture}}}
/// GET  /api/v0/credentials            x-dsh-auth-token -> {account, api_key, base_url}
/// GET  /auth-api/v0/users/current     x-dsh-auth-token -> 用户
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:http/http.dart' as http;

import '../secrets/secure_storage.dart';
import 'account_api.dart';

/// 账号中心地址；发版时可用 `--dart-define=FUSTAI_ACCOUNT_ORIGIN=...` 覆盖。
const String fustaiAccountOrigin = String.fromEnvironment(
  'FUSTAI_ACCOUNT_ORIGIN',
  defaultValue: 'https://account.fustai.com',
);

const Duration _requestTimeout = Duration(seconds: 20);

class FustaiAccountApi implements AccountApi {
  /// [client] 是本机引擎连接：登录后把账号中心的模型密钥推进它的凭据库。
  FustaiAccountApi(
    this.client, {
    this.origin = fustaiAccountOrigin,
    http.Client? httpClient,
    AppSecureStorage? storage,
  }) : _http = httpClient ?? http.Client(),
       _storage = storage ?? const AppSecureStorage() {
    _restored = _restore();
  }

  final DshClient client;

  /// Releases the loopback server, timers and the HTTP connection pool.
  void dispose() {
    final run = _run;
    _run = null;
    run?.timer?.cancel();
    final server = run?.server;
    if (server != null) unawaited(server.close(force: true));
    unawaited(_controller.close());
    _http.close();
  }

  /// 账号中心 origin，不带尾斜杠。
  final String origin;

  final http.Client _http;
  final AppSecureStorage _storage;

  static const _tokenKey = 'fustai_grant';
  static const _modelKeyKey = 'fustai_model_key';
  static const _baseUrlKey = 'fustai_model_base_url';
  static const _profileKey = 'fustai_profile';

  final _controller = StreamController<AccountView>.broadcast();
  late final Future<void> _restored;

  AccountView _view = const AccountView(status: AccountStatus.signedOut);
  _Run? _run;
  String? _token;
  String? _modelKey;
  AccountProfile? _profile;

  @override
  String get callbackOrigin {
    final server = _run?.server;
    return server == null ? '' : 'http://127.0.0.1:${server.port}';
  }

  @override
  Future<AccountView> getState() async {
    await _restored;
    return _view;
  }

  @override
  Stream<AccountView> watch() {
    late final StreamController<AccountView> out;
    StreamSubscription<AccountView>? sub;
    var stopped = false;

    out = StreamController<AccountView>(
      onListen: () {
        sub = _controller.stream.listen(
          (view) {
            if (!stopped) out.add(view);
          },
          onError: (Object error, StackTrace stack) {
            if (!stopped) out.addError(error, stack);
          },
        );
        unawaited(
          _restored.then((_) {
            if (!stopped && !out.isClosed) out.add(_view);
          }),
        );
      },
      onCancel: () async {
        stopped = true;
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<AccountView> startSignIn({LoginSource source = LoginSource.web}) async {
    await _restored;
    final active = _run;
    if (active != null && active.phase.isActive) return _view;

    final run = _Run(_randomToken(16));
    _run = run;
    _enter(run, SignInPhase.initializing);

    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      run.server = server;
      run.verifier = _randomToken(32);
      run.state = _randomToken(16);
      server.listen((request) => unawaited(_onCallback(run, request)));

      final body = await _post('/auth-api/v0/dsh/auth_init', {
        'code_challenge': _challenge(run.verifier!),
        'code_challenge_method': 'S256',
        'state': run.state,
        'redirect_uri': callbackOrigin,
        'locale': 'zh_CN',
        'login_source': source.wire,
      });
      final authorizeUrl = _text(body?['authorize_url']);
      if (authorizeUrl == null) return _fail(run, SignInErrorCode.protocol);

      final expiresIn = body?['expires_in'];
      final ttl = expiresIn is num && expiresIn > 0 ? Duration(seconds: expiresIn.toInt()) : const Duration(minutes: 10);
      _enter(
        run,
        SignInPhase.waitingBrowser,
        attempt: SignInAttempt(
          id: run.id,
          phase: SignInPhase.waitingBrowser,
          authorizeUrl: authorizeUrl,
          expiresAt: DateTime.now().add(ttl),
        ),
      );
      run.timer = Timer(ttl, () => _fail(run, SignInErrorCode.expired, phase: SignInPhase.expired));
      return _view;
    } on Object catch (error) {
      return _fail(run, _errorCode(error));
    }
  }

  @override
  Future<AccountView> cancelSignIn(String attemptId) async {
    final run = _run;
    if (run == null || run.id != attemptId || !run.phase.isActive) return _view;
    await _close(run);
    _enter(run, SignInPhase.cancelled);
    return _view;
  }

  @override
  Future<AccountView> signOut() async {
    final run = _run;
    if (run != null) await _close(run);
    _run = null;
    final pushed = _modelKey;
    _token = null;
    _modelKey = null;
    _profile = null;
    await _clearStorage();
    if (pushed != null) {
      try {
        await client.clearProviderKey();
      } on Object {
        // 引擎离线：本地 token 已删，密钥下次连接时由 [initializeDefaultModel] 覆盖。
      }
    }
    _publish(const AccountView(status: AccountStatus.signedOut));
    return _view;
  }

  @override
  Future<AccountProfile?> getProfile() async {
    await _restored;
    final token = _token;
    if (token == null) return null;
    try {
      final body = await _get('/auth-api/v0/users/current', token: token);
      final profile = _profileFrom(body);
      if (profile != null) {
        _profile = profile;
        await _storage.write(key: _profileKey, value: jsonEncode(_profileJson(profile)));
      }
      return profile ?? _profile;
    } on _Unauthorized {
      await _forgetGrant();
      return null;
    } on Object {
      return _profile;
    }
  }

  /// 账号密钥是本机引擎的普通 provider key，退出登录不会取消运行中的任务。
  @override
  Future<bool> hasRunningAccountTasks() async => false;

  @override
  Future<void> initializeDefaultModel() async {
    await _restored;
    await _pushModelKey();
  }

  // ── 登录流程 ────────────────────────────────────────────────────────────────

  Future<void> _onCallback(_Run run, HttpRequest request) async {
    if (request.uri.path != '/oauth/callback') {
      await _respond(request, 404, '未找到页面', 'Not found.');
      return;
    }
    if (!identical(_run, run) || !run.phase.isActive) {
      await _respond(request, 409, '登录已结束', 'Sign-in already finished.');
      return;
    }
    final query = request.uri.queryParameters;
    final code = _text(query['code']);
    final state = _text(query['state']);
    if (code == null || state == null || state != run.state) {
      await _respond(request, 400, '登录请求无效', 'Invalid sign-in request.');
      return;
    }
    if (await _exchange(run, code)) {
      await _respond(request, 200, '登录成功', 'Signed in. You can close this page and return to the app.');
      // 回完这一页再关回环端口，否则浏览器拿到的是断开的连接。
      _run = null;
      await _close(run);
    } else {
      await _respond(request, 400, '登录失败', 'Sign-in failed. Return to the app and try again.');
      _run = null;
      await _close(run);
    }
  }

  Future<bool> _exchange(_Run run, String code) async {
    final server = run.server;
    final redirect = server == null ? callbackOrigin : 'http://127.0.0.1:${server.port}';
    _enter(run, SignInPhase.exchanging);

    try {
      final exchanged = await _post('/auth-api/v0/dsh/auth_exchange', {
        'code': code,
        'code_verifier': run.verifier,
        'redirect_uri': redirect,
      });
      final token = _text(exchanged?['token']);
      if (token == null) {
        _fail(run, SignInErrorCode.protocol, close: false);
        return false;
      }
      final profile = _profileFrom(exchanged?['user']);

      _enter(run, SignInPhase.committing);
      final credentials = await _get('/api/v0/credentials', token: token);

      try {
        await _storage.write(key: _tokenKey, value: token);
      } on Object {
        _fail(run, SignInErrorCode.storage, close: false);
        return false;
      }
      _token = token;
      if (profile != null) {
        _profile = profile;
        await _storage.write(key: _profileKey, value: jsonEncode(_profileJson(profile)));
      }
      await _acceptCredentials(credentials);
    } on Object catch (error) {
      _fail(run, _errorCode(error), close: false);
      return false;
    }

    _publish(const AccountView(status: AccountStatus.credentialStored, attempt: _succeeded));
    return true;
  }

  Future<void> _acceptCredentials(Map<String, Object?>? body) async {
    final key = _text(body?['api_key']);
    if (key == null) return;
    _modelKey = key;
    await _storage.write(key: _modelKeyKey, value: key);
    await _storage.write(key: _baseUrlKey, value: _text(body?['base_url']));
    await _pushModelKey();
  }

  /// 把账号密钥推进本机引擎；引擎离线时留在本地，下次连接由 [initializeDefaultModel] 补推。
  Future<void> _pushModelKey() async {
    final key = _modelKey;
    if (key == null) return;
    try {
      await client.setProviderKey(key);
    } on Object {
      // 引擎可能拒绝由环境变量提供的 key；凭据仍在本地，重连后再推。
    }
  }

  Future<void> _restore() async {
    try {
      _token = await _storage.read(key: _tokenKey);
      _modelKey = await _storage.read(key: _modelKeyKey);
      _profile = _profileFromPayload(await _storage.read(key: _profileKey));
    } on Object {
      _token = null;
      _modelKey = null;
      _profile = null;
    }
    if (_token == null) {
      _publish(const AccountView(status: AccountStatus.signedOut));
      return;
    }
    _publish(const AccountView(status: AccountStatus.credentialStored));
    await _refreshCredentials();
  }

  Future<void> _refreshCredentials() async {
    final token = _token;
    if (token == null) return;
    try {
      await _acceptCredentials(await _get('/api/v0/credentials', token: token));
    } on _Unauthorized {
      await _forgetGrant();
    } on Object {
      // 离线或账号中心不可达：保留已存凭据，登录态不变。
    }
  }

  Future<void> _forgetGrant() async {
    _token = null;
    _modelKey = null;
    _profile = null;
    await _clearStorage();
    _publish(const AccountView(status: AccountStatus.signedOut));
  }

  Future<void> _clearStorage() async {
    for (final key in const [_tokenKey, _modelKeyKey, _baseUrlKey, _profileKey]) {
      try {
        await _storage.delete(key: key);
      } on Object {
        // 单项删除失败不影响剩余凭据与内存状态。
      }
    }
  }

  AccountView _fail(
    _Run run,
    SignInErrorCode code, {
    SignInPhase phase = SignInPhase.failed,
    bool close = true,
  }) {
    if (close) unawaited(_close(run));
    _enter(run, phase, errorCode: code);
    return _view;
  }

  void _enter(_Run run, SignInPhase phase, {SignInAttempt? attempt, SignInErrorCode? errorCode}) {
    run.phase = phase;
    _publish(
      AccountView(
        status: _view.status,
        links: _view.links,
        attempt: attempt ?? SignInAttempt(id: run.id, phase: phase, errorCode: errorCode),
      ),
    );
  }

  void _publish(AccountView view) {
    _view = view;
    if (!_controller.isClosed) _controller.add(view);
  }

  Future<void> _close(_Run run) async {
    run.timer?.cancel();
    run.timer = null;
    await run.server?.close(force: true);
    run.server = null;
  }

  // ── HTTP ───────────────────────────────────────────────────────────────────

  Future<Map<String, Object?>?> _post(String path, Map<String, Object?> body) async {
    final response = await _http
        .post(
          Uri.parse('$origin$path'),
          headers: const {'content-type': 'application/json', 'accept': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);
    return _decode(response);
  }

  Future<Map<String, Object?>?> _get(String path, {required String token}) async {
    final response = await _http
        .get(Uri.parse('$origin$path'), headers: {'x-dsh-auth-token': token, 'accept': 'application/json'})
        .timeout(_requestTimeout);
    return _decode(response);
  }

  Map<String, Object?>? _decode(http.Response response) {
    if (response.statusCode == 401) throw const _Unauthorized();
    if (response.statusCode != 200) throw _HttpFailure(response.statusCode);
    final envelope = _map(jsonDecode(utf8.decode(response.bodyBytes)));
    if (envelope == null || envelope['code'] != 0) throw const _ProtocolFailure();
    final data = _map(envelope['data']);
    if (data == null || data['biz_code'] != 0) throw const _ProtocolFailure();
    return _map(data['biz_data']);
  }

  Future<void> _respond(HttpRequest request, int status, String title, String detail) async {
    final body =
        '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>$title</title><style>'
        'body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;'
        'font:16px/1.6 -apple-system,system-ui,"Noto Sans SC",sans-serif;background:#f6f7f9;color:#1d2129}'
        'main{max-width:22rem;padding:2rem;text-align:center}'
        'h1{font-size:1.25rem;margin:0 0 .75rem}p{margin:0;color:#4e5969}'
        '</style></head><body><main><h1>$title</h1><p>$detail</p></main></body></html>';
    try {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.html
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..write(body);
      await request.response.close();
    } on Object {
      // 浏览器已断开（用户退回 App），无需回写。
    }
  }

  SignInErrorCode _errorCode(Object error) => switch (error) {
    TimeoutException() || SocketException() || http.ClientException() => SignInErrorCode.noResponse,
    _HttpFailure() => SignInErrorCode.network,
    _Unauthorized() || _ProtocolFailure() || FormatException() => SignInErrorCode.protocol,
    _ => SignInErrorCode.unknown,
  };

  // ── 编解码 ─────────────────────────────────────────────────────────────────

  AccountProfile? _profileFrom(Object? json) {
    final map = _map(json);
    if (map == null) return null;
    final idProfile = _map(map['id_profile']) ?? const <String, Object?>{};
    return AccountProfile(
      id: _text(map['id']),
      name: _text(idProfile['name']) ?? _text(map['name']),
      contact: _text(map['email']) ?? _text(map['mobile']),
      avatarUrl: _text(idProfile['picture']) ?? _text(map['picture']),
    );
  }

  AccountProfile? _profileFromPayload(String? raw) {
    if (raw == null) return null;
    try {
      return _profileFrom(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> _profileJson(AccountProfile profile) => {
    'id': profile.id,
    'name': profile.name,
    'contact': profile.contact,
    'picture': profile.avatarUrl,
  };

  static String _challenge(String verifier) =>
      base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');

  static String _randomToken(int bytes) {
    final random = Random.secure();
    return base64Url.encode(List<int>.generate(bytes, (_) => random.nextInt(256))).replaceAll('=', '');
  }

  static Map<String, Object?>? _map(Object? value) =>
      value is Map ? {for (final entry in value.entries) '${entry.key}': entry.value} : null;

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

const SignInAttempt _succeeded = SignInAttempt(id: 'fustai', phase: SignInPhase.succeeded);

class _Run {
  _Run(this.id);

  final String id;
  SignInPhase phase = SignInPhase.initializing;
  HttpServer? server;
  Timer? timer;
  String? verifier;
  String? state;
}

class _HttpFailure implements Exception {
  const _HttpFailure(this.status);
  final int status;
}

class _Unauthorized implements Exception {
  const _Unauthorized();
}

class _ProtocolFailure implements Exception {
  const _ProtocolFailure();
}