import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/drawer_view_state.dart';
import '../../state/sessions_state.dart';
import '../account/account_page.dart';
import '../common/empty_view.dart';
import '../shell/drawer/drawer_list.dart';
import '../theme/app_icons.dart';
import '../web/mode_home.dart';

/// 登录后的第一页：全部对话。
///
/// Opening a row (or 新对话) hands the chat itself to [ModeHome], whose own
/// drawer keeps the folder, search and bulk-selection features.
class TaskDirectoryPage extends ConsumerWidget {
  const TaskDirectoryPage({super.key});

  void _open(BuildContext context, WidgetRef ref, String? sessionId) {
    ref.read(currentSessionProvider.notifier).select(sessionId);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModeHome()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scope = ref.watch(drawerScopeProvider);
    final sessions = ref.watch(sessionsProvider);
    final Widget body;
    if (scope == null) {
      body = sessions.hasError
          ? EmptyView(
              icon: AppIcons.offline,
              title: l10n.shellChatsLoadFailed,
              actionLabel: l10n.commonRetry,
              onAction: () => ref.read(sessionsProvider.notifier).refresh(),
            )
          : const SizedBox.shrink();
    } else if (scope.sessions.isEmpty) {
      body = EmptyView(icon: AppIcons.chat, title: l10n.shellNoChatsYet);
    } else {
      body = DrawerConversationList(
        onOpen: (id) => _open(context, ref, id),
        onLongPress: (s) => _open(context, ref, s.sessionId),
        onNewChat: () => _open(context, ref, null),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l10n.shellChatList, style: theme.textTheme.headlineSmall),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => const AccountPage())),
                    icon: const Icon(AppIcons.account),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.commonNewChat,
        onPressed: () => _open(context, ref, null),
        child: const Icon(AppIcons.newChat),
      ),
    );
  }
}