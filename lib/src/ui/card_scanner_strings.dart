import 'package:meta/meta.dart';

import '../core/card_scan_result.dart';

/// Every piece of text the built-in scanner UI can show.
///
/// The defaults are English. Build one from your own localizations and pass
/// it to [CardScannerPage] or [CardFrameOverlay] to translate the scanner:
///
/// ```dart
/// CardScannerPage.show(
///   context,
///   strings: CardScannerStrings(
///     alignCard: AppLocalizations.of(context).alignCard,
///     // ...
///   ),
/// );
/// ```
@immutable
class CardScannerStrings {
  const CardScannerStrings({
    this.alignCard = 'Align the card inside the frame',
    this.lookingForExpiry = 'Number recognized. Looking for the expiry date',
    this.lookingForName =
        'Number and expiry recognized. Turn the card over '
        'to scan the name',
    this.lookingForNumber =
        'Name recognized. Turn the card over to scan the '
        'number and expiry date',
    this.permissionDenied = 'Camera access is needed to scan a card.',
    this.openSettings = 'Open settings',
    this.cameraFailed = 'The camera could not be started.',
    this.cameraBusy = 'Another app is using the camera.',
    this.retry = 'Try again',
  });

  /// Shown before anything has been recognized.
  final String alignCard;

  /// The number is in, the expiry date is not.
  final String lookingForExpiry;

  /// Number and expiry are in, the name is not. This is the prompt that
  /// tells someone holding a two-sided card what to do.
  final String lookingForName;

  /// The name is in but the number is not, which happens when a two-sided
  /// card is presented back first.
  final String lookingForNumber;

  /// Camera permission was refused.
  final String permissionDenied;

  /// Button that takes the user to the system settings for the app. Only
  /// shown when the host app provides a way to get there.
  final String openSettings;

  /// The camera could not be opened, or stopped working.
  final String cameraFailed;

  /// The camera is held by another app.
  final String cameraBusy;

  /// Button that tries the camera again.
  final String retry;

  static const defaults = CardScannerStrings();

  /// The prompt that matches what has been recognized so far.
  ///
  /// [wantsName] says whether the scan is still waiting for a cardholder
  /// name; without it the scanner would ask for one it does not need.
  String hintFor(CardScanResult result, {bool wantsName = true}) {
    if (result.hasNumber && !result.hasExpiry) return lookingForExpiry;
    if (result.hasName && !result.hasNumber) return lookingForNumber;
    if (result.hasNumber && result.hasExpiry && !result.hasName && wantsName) {
      return lookingForName;
    }
    return alignCard;
  }

  CardScannerStrings copyWith({
    String? alignCard,
    String? lookingForExpiry,
    String? lookingForName,
    String? lookingForNumber,
    String? permissionDenied,
    String? openSettings,
    String? cameraFailed,
    String? cameraBusy,
    String? retry,
  }) => CardScannerStrings(
    alignCard: alignCard ?? this.alignCard,
    lookingForExpiry: lookingForExpiry ?? this.lookingForExpiry,
    lookingForName: lookingForName ?? this.lookingForName,
    lookingForNumber: lookingForNumber ?? this.lookingForNumber,
    permissionDenied: permissionDenied ?? this.permissionDenied,
    openSettings: openSettings ?? this.openSettings,
    cameraFailed: cameraFailed ?? this.cameraFailed,
    cameraBusy: cameraBusy ?? this.cameraBusy,
    retry: retry ?? this.retry,
  );
}
