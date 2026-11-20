// The first-run 「桌宠与悬浮窗」 step means "let the pet show": it turns the
// floating window on, and leaves the pack alone. No pet ships with the app, so
// nothing is chosen until a pack is brought in; a choice already made,
// 「不显示」 included, stays.

import 'package:dsh_app/performance/performance_state.dart';
import 'package:dsh_app/pets/overlay_channel.dart';
import 'package:dsh_app/pets/pet_prefs.dart';
import 'package:dsh_app/pets/pet_state.dart';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/access_state.dart';
import 'package:dsh_app/state/phone_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../performance/support.dart';
import '../pets/overlay/fake_overlay_native.dart';
import '../phone/support.dart';
import '../shell/golden_harness.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeOverlayNative pet;

  Future<ProviderContainer> container({Map<String, Object> prefs = const {}, DeviceTier tier = DeviceTier.low}) async {
    SharedPreferences.setMockInitialValues(prefs);
    FakePhoneNative(status: phoneStatus()).install();
    pet = FakeOverlayNative(permission: 'granted')..install();
    final c = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => FakeSettings(const AppSettings(loaded: true))),
        localRuntimeProvider.overrideWith(
          () => FakeRuntime(const LocalRuntimeState(loaded: true, status: RuntimeStatus(phase: RuntimePhase.notInstalled))),
        ),
        accessDriverProvider.overrideWithValue(FakeAccessDriver(offPhone)),
        performanceChannelProvider.overrideWithValue(FakePerformanceChannel(Future.value(snapshot(tier)))),
      ],
    );
    addTearDown(c.dispose);
    c.read(accessSetupProvider);
    c.read(petOverlayProvider);
    c.read(petPrefsProvider);
    await Future<void>.delayed(Duration.zero);
    await c.read(phoneProvider.notifier).refreshStatus();
    return c;
  }

  Future<String?> storedPack() async => (await SharedPreferences.getInstance()).getString(PetPrefsController.keys.pack);

  test('picked, granted, no pet brought: the floating window goes on, the pack stays 「不显示」', () async {
    final c = await container();
    expect(c.read(petPrefsProvider).packId, noPetId, reason: 'no pet ships with the app');
    await c.read(accessSetupProvider.notifier).choose({AccessFeature.pet});
    await c.read(accessSetupProvider.notifier).apply(readingsWith(offPhone, overlay: true));
    expect(c.read(petPrefsProvider).packId, noPetId);
    expect(c.read(petPrefsProvider).packExplicit, isFalse);
    expect(await storedPack(), isNull);
    expect(pet.calls.where((m) => m.method == 'setEnabled').single.arguments, {'enabled': true});
  });

  test('picked but the floating window still off: nothing else changes', () async {
    final c = await container();
    await c.read(accessSetupProvider.notifier).choose({AccessFeature.pet});
    await c.read(accessSetupProvider.notifier).apply(offPhone);
    expect(c.read(petPrefsProvider).packId, noPetId);
    expect(pet.methods, isNot(contains('setEnabled')));
  });

  test('the whole step through 继续 leaves the pack alone', () async {
    final c = await container();
    await c.read(accessSetupProvider.notifier).choose({AccessFeature.pet});
    await c.read(accessSetupProvider.notifier).finish();
    expect(c.read(petPrefsProvider).packId, noPetId);
    expect(await storedPack(), isNull);
  });

  for (final chosen in [noPetId, 'user-brought']) {
    test('a pet choice already made stays: $chosen', () async {
      final c = await container(prefs: {PetPrefsController.keys.pack: chosen});
      await c.read(accessSetupProvider.notifier).choose({AccessFeature.pet});
      await c.read(accessSetupProvider.notifier).apply(readingsWith(offPhone, overlay: true));
      expect(c.read(petPrefsProvider).packId, chosen);
      expect(await storedPack(), chosen);
    });
  }

  test('not picked: nothing changes, nothing stored', () async {
    final c = await container();
    await c.read(accessSetupProvider.notifier).choose({AccessFeature.voice});
    await c.read(accessSetupProvider.notifier).apply(readingsWith(offPhone, overlay: true));
    expect(c.read(petPrefsProvider).packId, noPetId);
    expect(c.read(petPrefsProvider).packExplicit, isFalse);
    expect(await storedPack(), isNull);
  });

  test('a full phone does not invent a pet either', () async {
    final c = await container(tier: DeviceTier.high);
    await c.read(accessSetupProvider.notifier).choose({AccessFeature.pet});
    await c.read(accessSetupProvider.notifier).apply(readingsWith(offPhone, overlay: true));
    expect(c.read(petPrefsProvider).packId, noPetId);
    expect(await storedPack(), isNull);
  });
}