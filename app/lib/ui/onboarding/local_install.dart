// 「安装运行环境」 after first run — for a phone that started on a remote host, or
// after an uninstall. Every install entry (the engine page, the host switcher,
// the empty chat and drawer, the web page) opens this one page; a build without
// the runtime (LocalRuntimeState.available) opens the host list instead.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../runtime/runtime_state.dart';
import '../../state/account_state.dart';
import '../../state/engine_control.dart';
import '../../state/hosts_state.dart';
import '../../state/onboarding_state.dart';
import '../../state/settings_state.dart';
import '../remote/remote_screen.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import 'connect_page.dart';
import 'runtime_setup_page.dart';

/// Opens the install page over whatever is showing; the host list on a build
/// without the runtime.
Future<void> openLocalInstall(BuildContext context, {bool useWhenDone = false}) {
  final available = ProviderScope.containerOf(context, listen: false).read(localRuntimeProvider).available;
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => available ? LocalInstallPage(useWhenDone: useWhenDone) : const RemoteScreen(),
    ),
  );
}

/// What a 本机 entry says with no runtime: install it, or on a build without
/// one, use a remote host. Both actions go through [openLocalInstall].
({String title, String action}) localMissingCopy(L10n l10n, {required bool available}) => available
    ? (title: l10n.localEnvNotInstalled, action: l10n.phoneEngineInstallRuntime)
    : (title: l10n.localEnvUnavailable, action: l10n.localEnvUseRemote);

/// Unpacks the bundled runtime and shows the progress; the environment ships
/// inside the app, so nothing is downloaded and there is no step to confirm.
/// Once installed the engine starts, and a phone with no model yet goes on to
/// 「连接 DeepSeek」.
///
/// The back key leaves at any point: an install already running carries on
/// in the background (its notification shows the progress) and this page
/// picks it up again when reopened.
class LocalInstallPage extends ConsumerStatefulWidget {
  const LocalInstallPage({super.key, this.useWhenDone = false});

  /// Make 本机 the active host once installed (opened from the host list).
  final bool useWhenDone;

  @override
  ConsumerState<LocalInstallPage> createState() => _LocalInstallPageState();
}

class _LocalInstallPageState extends ConsumerState<LocalInstallPage> {
  Future<void> _done() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    unawaited(EngineControl.ensureStarted(container));
    if (widget.useWhenDone) container.read(activeHostProvider.notifier).select(HostRef.local);
    final hasModel = container.read(settingsProvider).hasModelAccess || container.read(accountProvider).signedIn;
    if (hasModel || container.read(onboardingPrefsProvider).keySkipped) {
      navigator.pop();
      return;
    }
    await navigator.pushReplacement<void, void>(
      MaterialPageRoute(builder: (context) => ConnectPage(onDone: () => Navigator.of(context).pop())),
    );
    // Left without a key or a sign-in: don't bring the step back at launch.
    if (!container.read(settingsProvider).hasModelAccess && !container.read(accountProvider).signedIn) {
      await container.read(onboardingPrefsProvider.notifier).setKeySkipped(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RuntimeSetupPage(
      onDone: () => unawaited(_done()),
      leading: GlassIconButton(
        icon: AppIcons.back,
        tooltip: context.l10n.commonBack,
        grouped: false,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
