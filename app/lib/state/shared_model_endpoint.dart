/// 账号的模型密钥与它所属的推理端点。
///
/// 桌面端、账号中心和手机端存的是同一把 key 与同一个 base URL；手机端不再
/// 另存一套，而是把这份凭据装进本机引擎里对应 base URL 的 provider 路由，
/// 并把默认模型指到该路由，否则对话仍会用一条没配密钥的模型报「密钥无效」。
library;

import 'dart:async';

import 'package:dsh_client/dsh_client.dart';

import 'model_defaults_state.dart';
import 'models_state.dart' show defaultModelSettingsNs;
import 'providers_state.dart' show newProviderId, normalizeBaseUrl;

/// DeepSeek 官方推理端点：账号中心没给 base URL 时密钥按它使用。
const String deepSeekOfficialBaseUrl = 'https://api.deepseek.com';

/// 把账号的 base URL 规范化成可比较的端点；空、非法或非 HTTP(S) 时为 null。
String? normalizeSharedBaseUrl(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !(uri.isScheme('http') || uri.isScheme('https')) ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return normalizeBaseUrl(text, ProviderApi.openaiCompletions);
}

/// [baseUrl] 是否就是 DeepSeek 官方端点：那种情况沿用内置 `DEEPSEEK_API_KEY`。
bool isDeepSeekOfficialEndpoint(String? baseUrl) {
  final endpoint = normalizeSharedBaseUrl(baseUrl);
  if (endpoint == null) return false;
  final host = Uri.parse(endpoint).host.toLowerCase();
  return host == 'api.deepseek.com' || host == 'platform.deepseek.com';
}

Future<void> _pending = Future<void>.value();

Future<void> _enqueue(Future<void> Function() task) {
  final run = _pending.then((_) => task());
  // 队列继续往下走，即使本次失败；失败仍抛给本次调用方。
  _pending = run.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
  return run;
}

/// 把账号密钥装进本机引擎：官方端点用内置路由，其他端点用它自己的路由。
///
/// 同一个 base URL 已有路由就复用，没有就按端点下发的模型新建一条
/// `custom-*` 路由。登录回填、连接建立、设置变化都会调用；排队串行执行，
/// 避免并发新建出重复路由。失败抛给调用方，下一次同步会重试。
Future<void> installSharedModelKey(DshClient client, {required String key, String? baseUrl}) {
  final secret = key.trim();
  if (secret.isEmpty) return Future<void>.value();
  final endpoint = normalizeSharedBaseUrl(baseUrl);
  return _enqueue(() => _install(client, secret, endpoint));
}

/// 退出登录后清掉本机引擎里的账号密钥；只清这份凭据，其他 provider 不动。
Future<void> removeSharedModelKey(DshClient client, {String? baseUrl}) {
  final endpoint = normalizeSharedBaseUrl(baseUrl);
  return _enqueue(() => _remove(client, endpoint));
}

Future<void> _install(DshClient client, String key, String? endpoint) async {
  if (endpoint == null || isDeepSeekOfficialEndpoint(endpoint)) {
    await client.setProviderKey(key);
    return;
  }
  final settings = await client.providerSettings();
  if (settings == null) return;
  var profile = _profileFor(settings, endpoint);
  if (profile == null) {
    final models = await client.discoverModels(
      baseUrl: endpoint,
      api: ProviderApi.openaiCompletions,
      apiKey: key,
    );
    if (models.isEmpty) return;
    final route = newProviderId(
      name: '',
      baseUrl: endpoint,
      taken: {for (final candidate in settings.profiles) candidate.route},
    );
    final created = ProviderProfile(
      route: route,
      displayName: Uri.parse(endpoint).host,
      api: ProviderApi.openaiCompletions.wire,
      baseUrl: endpoint,
      apiKeyEnv: deriveProviderKeyRef(route),
      models: [for (final model in models) model.toSpec()],
    );
    final next = await client.saveProvider(created, expectedRevision: settings.revision);
    profile = next.byRoute(route) ?? created;
  }
  var env = profile.apiKeyEnv;
  if (env == null || env.isEmpty) {
    env = deriveProviderKeyRef(profile.route);
    await client.updateProvider(profile.route, apiKeyEnv: env);
  }
  await client.setProviderKey(key, ref: env);
  await _alignDefaultModel(client, profile);
}

Future<void> _remove(DshClient client, String? endpoint) async {
  if (endpoint == null || isDeepSeekOfficialEndpoint(endpoint)) {
    await client.clearProviderKey();
    return;
  }
  final settings = await client.providerSettings();
  final profile = settings == null ? null : _profileFor(settings, endpoint);
  final env = profile?.apiKeyEnv;
  if (env == null || env.isEmpty) return;
  await client.clearProviderKey(ref: env);
}

ProviderProfile? _profileFor(ProviderSettings settings, String endpoint) {
  final target = _endpointKey(endpoint);
  for (final profile in settings.profiles) {
    final url = profile.baseUrl;
    if (url == null || url.isEmpty) continue;
    if (_endpointKey(url) == target) return profile;
  }
  return null;
}

String _endpointKey(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return url.trim().replaceFirst(RegExp(r'/+$'), '');
  return '${uri.host.toLowerCase()}${uri.path.replaceFirst(RegExp(r'/+$'), '')}';
}

/// 默认模型指到共享路由：本机已选另一条 provider 路由时保留用户的选择。
Future<void> _alignDefaultModel(DshClient client, ProviderProfile profile) async {
  if (profile.models.isEmpty) return;
  final section = await client.settingsSection(defaultModelSettingsNs);
  if (section == null || !section.writable) return;
  final current = section.value['provider'];
  final currentModel = section.value['model'];
  if (current is String && current.isNotEmpty && current != profile.route) {
    final settings = await client.providerSettings();
    if (settings != null && settings.byRoute(current) != null) return;
  }
  final model = (currentModel is String && profile.models.any((m) => m.id == currentModel))
      ? currentModel
      : profile.models.first.id;
  if (current == profile.route && currentModel == model) return;
  await client.mutateSettings(
    defaultModelSettingsNs,
    defaultModelOps(ModelSelection(provider: profile.route, model: model)),
    expectedRevision: section.revision,
  );
}