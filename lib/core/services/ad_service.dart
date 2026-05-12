import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Reward types served by the Shop "Earn Free" section.
///
/// Per AdMob console wiring, each type has its own ad unit (placement) per
/// platform.  The server decides how many ad watches map to a credit — see
/// `grantAdReward` in `functions/src/index.ts` — so the client just plays one
/// ad per tap and forwards the result.
enum RewardType { icebreaker, liveSession }

/// Google's official rewarded-ad test unit IDs.  These ALWAYS fill, so debug
/// builds use them to avoid the "no fill" period that hits brand-new AdMob
/// units (Google often takes 12–24 hrs to begin serving live ads on a fresh
/// unit).  Release builds use the real publisher units below.
///
/// Source: https://developers.google.com/admob/flutter/test-ads
const String _kTestRewardedIosId = 'ca-app-pub-3940256099942544/1712485313';
const String _kTestRewardedAndroidId = 'ca-app-pub-3940256099942544/5224354917';

extension _RewardTypeAdUnit on RewardType {
  /// AdMob rewarded ad unit ID for this reward type on the current platform.
  /// Returns Google's test ID in debug builds so the flow is exercisable
  /// before publisher units have warmed up.
  String get adUnitId {
    if (kDebugMode) {
      return Platform.isIOS ? _kTestRewardedIosId : _kTestRewardedAndroidId;
    }
    if (Platform.isIOS) {
      switch (this) {
        case RewardType.icebreaker:
          return 'ca-app-pub-9291120751046044/3245738330';
        case RewardType.liveSession:
          return 'ca-app-pub-9291120751046044/7153193756';
      }
    } else {
      // Android (and fallback)
      switch (this) {
        case RewardType.icebreaker:
          return 'ca-app-pub-9291120751046044/9881475048';
        case RewardType.liveSession:
          return 'ca-app-pub-9291120751046044/8342986491';
      }
    }
  }
}

/// Outcome of a single rewarded-ad attempt, surfaced to the Shop UI.
///
/// `success` means the user fully watched the ad AND the server accepted the
/// grant call.  `granted` then says whether the watch actually crossed the
/// threshold (1 ad → icebreaker is always true; live session may need a 2nd
/// watch).  `progress` / `required` describe the running count so the UI can
/// show "1 of 2 ads watched."
class AdShowResult {
  const AdShowResult({
    required this.status,
    this.granted = false,
    this.progress,
    this.required,
    this.errorMessage,
  });

  final AdShowStatus status;
  final bool granted;
  final int? progress;
  final int? required;
  final String? errorMessage;
}

enum AdShowStatus {
  /// Server granted (or accumulated progress toward) the reward.
  success,

  /// User dismissed the ad before earning the reward.
  dismissed,

  /// No cached ad was ready; retry shortly while the next one preloads.
  notReady,

  /// AdMob failed to render the cached ad.
  failedToShow,

  /// Reward type is in its 24h cooldown window — user already claimed today.
  cooldown,

  /// Network or Cloud Function error while granting the reward.
  error,
}

/// Front door for AdMob rewarded ads.  One cached ad per [RewardType] is
/// preloaded at app boot and replaced after each show; the Shop tap simply
/// calls [showRewarded] and acts on the returned [AdShowResult].
///
/// Reward accounting is server-side: a successful watch fires the
/// `grantAdReward` Cloud Function with a per-show nonce, and the function
/// decides whether to bump progress or actually credit the user (see
/// AppConstants.adWatchLimitPerDay for the daily cap).
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  bool _initialized = false;
  final Random _rng = Random.secure();

  RewardedAd? _icebreakerAd;
  RewardedAd? _liveSessionAd;
  bool _loadingIcebreaker = false;
  bool _loadingLiveSession = false;

  /// Initializes the AdMob SDK and kicks off the first preload for each
  /// rewarded ad unit.  Safe to call multiple times.  Should be invoked from
  /// `main.dart` after the ATT prompt (iOS) so personalized-ad eligibility is
  /// settled before the first ad request goes out.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('[Ads] MobileAds.initialize threw: $e');
      return;
    }

    _loadFor(RewardType.icebreaker);
    _loadFor(RewardType.liveSession);
  }

  /// True if a cached ad is ready for [type].  The Shop uses this to keep
  /// the CTA enabled vs showing a "loading" hint.
  bool isReady(RewardType type) {
    return switch (type) {
      RewardType.icebreaker => _icebreakerAd != null,
      RewardType.liveSession => _liveSessionAd != null,
    };
  }

  void _loadFor(RewardType type) {
    final loading = type == RewardType.icebreaker
        ? _loadingIcebreaker
        : _loadingLiveSession;
    final cached = type == RewardType.icebreaker
        ? _icebreakerAd
        : _liveSessionAd;
    if (loading || cached != null) return;

    _setLoading(type, true);

    final unitId = type.adUnitId;
    debugPrint('[Ads] load(${type.name}) requesting $unitId');
    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('[Ads] load(${type.name}) ready');
          _setLoading(type, false);
          _setCached(type, ad);
        },
        onAdFailedToLoad: (err) {
          debugPrint('[Ads] load(${type.name}) failed: $err');
          _setLoading(type, false);
          _setCached(type, null);
        },
      ),
    );
  }

  void _setLoading(RewardType type, bool v) {
    if (type == RewardType.icebreaker) {
      _loadingIcebreaker = v;
    } else {
      _loadingLiveSession = v;
    }
  }

  void _setCached(RewardType type, RewardedAd? ad) {
    if (type == RewardType.icebreaker) {
      _icebreakerAd = ad;
    } else {
      _liveSessionAd = ad;
    }
  }

  /// Plays a single rewarded ad for [type].  On reward earned, forwards a
  /// per-show nonce to the `grantAdReward` CF and surfaces the result.
  /// Always preloads the next ad before returning so the user can chain
  /// watches (e.g. live session needs 2).
  Future<AdShowResult> showRewarded(RewardType type) async {
    final ad = type == RewardType.icebreaker
        ? _icebreakerAd
        : _liveSessionAd;
    if (ad == null) {
      _loadFor(type);
      return const AdShowResult(status: AdShowStatus.notReady);
    }

    // Detach from the cache up front — the SDK requires a one-shot show, so
    // even on dismiss we don't want a stale reference around.
    _setCached(type, null);

    final completer = Completer<AdShowResult>();
    var earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadFor(type);
        if (!earned && !completer.isCompleted) {
          completer.complete(
            const AdShowResult(status: AdShowStatus.dismissed),
          );
        }
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        debugPrint('[Ads] show(${type.name}) failed: $error');
        a.dispose();
        _loadFor(type);
        if (!completer.isCompleted) {
          completer.complete(
            AdShowResult(
              status: AdShowStatus.failedToShow,
              errorMessage: error.message,
            ),
          );
        }
      },
    );

    await ad.show(
      onUserEarnedReward: (a, reward) async {
        earned = true;
        final result = await _grantReward(type);
        if (!completer.isCompleted) completer.complete(result);
      },
    );

    return completer.future;
  }

  Future<AdShowResult> _grantReward(RewardType type) async {
    try {
      final nonce =
          '${DateTime.now().microsecondsSinceEpoch}-${_rng.nextInt(1 << 32).toRadixString(16)}';
      final res = await FirebaseFunctions.instance
          .httpsCallable('grantAdReward')
          .call(<String, dynamic>{'type': type.name, 'nonce': nonce});
      final data = (res.data as Map?)?.cast<String, dynamic>();
      return AdShowResult(
        status: AdShowStatus.success,
        granted: data?['granted'] == true,
        progress: (data?['progress'] as num?)?.toInt(),
        required: (data?['required'] as num?)?.toInt(),
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[Ads] grantAdReward CF rejected for ${type.name}: ${e.code} ${e.message}',
      );
      if (e.code == 'resource-exhausted') {
        return AdShowResult(
          status: AdShowStatus.cooldown,
          errorMessage: e.message,
        );
      }
      return AdShowResult(
        status: AdShowStatus.error,
        errorMessage: e.message,
      );
    } catch (e) {
      debugPrint('[Ads] grantAdReward CF failed for ${type.name}: $e');
      return AdShowResult(
        status: AdShowStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}
