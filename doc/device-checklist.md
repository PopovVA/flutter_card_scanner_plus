# Device checklist

What to run on a real phone and tablet after a change to the camera, the
orientation handling or the scan rules. Nothing here can be covered by the
test suite: it is all platform behaviour.

Run the example in release mode, since debug frame rates hide timing bugs:

```bash
cd example && flutter run --release
```

## Orientation

| Step | Expected |
|---|---|
| Hold the phone in landscape and scan a card | The card reads correctly, not just the number |
| An iPhone Pro, card held where the guide asks | The preview sharpens; the lens zooms in a little by itself to make that possible |
| The same phone, close the scanner and open the system camera | No leftover zoom |
| Same on an iPad in landscape | Preview is upright, moving the tablet pans the image the way it should |
| Rotate portrait to landscape and back, four times, then close and reopen | Preview is sharp and aligned, nothing drifts |
| Lock the example to portrait, then turn the phone sideways | Guide and preview both stay upright |
| Rotate while a number is already recognized | The recognized number is not replaced by a misread |

## Camera lifecycle

| Step | Expected |
|---|---|
| Open and close the scanner fifteen times quickly | Every open shows a preview, never a black screen or "unable to start camera" |
| Send the app to the background mid scan, come back | Preview returns, fields found so far are kept |
| Take a call, or open another camera app, while scanning | A message and a retry button, not a frozen preview |
| Refuse camera permission, then use the settings button, grant it, come back | The scanner recovers without being closed and reopened |
| Close the scanner the moment the preview appears | No flicker of a dying texture during the exit animation |

## Recognition

| Step | Expected |
|---|---|
| A card with the name on the back: front first, then turn it over | Number and expiry are kept while the card is turned, the name completes the scan |
| The same card, back first | The name is kept, turning it over completes the scan |
| Hold a card next to a laptop keyboard | No keyboard label is ever offered as the cardholder name |
| A card with a material claim printed beside the name block | The real name wins |
| Two cards in view at once | The result does not flip between them |
| Discover, JCB, Diners Club or UnionPay, if you have one | Recognized, correctly branded and grouped |
| A card whose name OCR splits into separate words | Full name, not one word |

## Browser

The camera needs a secure context, so the example has to be served over
HTTPS to reach a phone on the same network. `flutter run -d chrome` covers
a laptop; a phone needs a certificate:

```bash
cd example
dart run flutter_card_scanner_plus:install_web
flutter build web --release
# then serve build/web over HTTPS on the LAN, for instance
#   npx http-server build/web -S -C cert.pem -K key.pem -p 8443
```

Before any of this, two pages tell you without a camera whether anything
is broken. `example/web/ocr_harness.html` exercises the engine, and
`?fakeCamera=1` on the example itself exercises the whole scanner against
a drawing of a card. See `tool/ocr_worker/README.md`. What is left below
is what only hardware can answer.

| Step | Expected |
|---|---|
| iOS Safari and Android Chrome, scan a card | Reads it; the first frame takes a second or two while the engine loads |
| Close the scanner while the permission prompt is up, then answer it | The camera never turns on: no indicator, no green dot |
| Send the browser to the background while the camera is opening, come back | One camera, not two, and the preview returns |
| Turn the phone sideways | Preview and guide both follow, and the card still reads |
| The torch button | Present only when the browser admits to a torch, and it lights |
| A name with a colour in it, "ALICE GREEN" | Read whole, not cut down to "ALICE" |
| Refuse camera access, then press Retry | The message explains, Retry reopens, the close button works throughout |
| An embedded browser, a link opened inside another app | Either scans or says the browser cannot, never a black screen |
| Serve it over plain HTTP | Says the browser cannot open a camera, rather than failing silently |
| Watch the network tab during a scan | Requests only to your own origin |

## While waiting

| Step | Expected |
|---|---|
| Watch the prompt as fields are found | It names what is still missing, and a spinner runs |
| With haptics on, let it move from one prompt to the next | One light tap per change, no buzzing |

## NFC on a device

NFC cannot be checked anywhere but on a phone, and it fails in ways the
Dart side cannot see, so start by making the device talk.

`flutter run` has been seen to print nothing at all from an app on a
physical iPhone, in both debug and release, while `devicectl --console`
and `flutter logs` stayed empty too. The Dart VM Service is the channel
that does work. Take the websocket URI `flutter run` prints, connect to
it, and subscribe to `Stdout`:

```dart
final socket = await WebSocket.connect(uri); // ws://127.0.0.1:PORT/TOKEN=/ws
socket.add(jsonEncode({
  'jsonrpc': '2.0', 'id': '0',
  'method': 'streamListen', 'params': {'streamId': 'Stdout'},
}));
await for (final raw in socket) {
  final event = jsonDecode(raw as String)['params']?['event'];
  final bytes = event?['bytes'];
  if (bytes != null) stdout.write(utf8.decode(base64Decode(bytes)));
}
```

`CardNfcProbe.run` then reaches a laptop, and it stops before any record
is read, so nothing it prints is card data.

Two configuration mistakes refuse a session outright, and both look like
the app's fault rather than the plist's.

The identifiers in `com.apple.developer.nfc.readersession.iso7816.select-identifiers`
have to be hex. `2PAY.SYS.DDF01` written out as text is not the PPSE AID;
`325041592E5359532E4444463031` is. iOS selects each entry on the card
itself and hands the tag to the app only on a match, so a readable name
there means the system sheet opens and nothing ever happens.

Adding `.iso18092` to the polling option without
`com.apple.developer.nfc.readersession.felica.systemcodes` in the plist
fails the whole session with "Missing required entitlement", including
the ISO 14443 half that would otherwise have worked. MIFARE is ISO 14443
anyway, so a transit card or a hotel key is detected without widening the
polling at all, which makes them the cheapest tags to test with.

| Step | Expected |
|---|---|
| Hold a contactless card to the top edge of the back | The sheet reports success; the probe lists the AIDs the card offered |
| Dismiss the sheet by hand | `nfcCancelled`, no stuck session, the next attempt still works |
| Hold a transit card or hotel key instead | Reaches `didDetect`, then refuses it as not a payment card |
| Leave the sheet untouched | `nfcCancelled: Session timeout` after about a minute |
| A phone with no NFC, or NFC off | `nfcUnavailable`, and the rest of the app keeps working |

One failure is open and is not understood. On an iPhone on iOS 26.6 the
session reaches `tagReaderSessionDidBecomeActive`, so the entitlement and
the provisioning are right, and then `didDetect` is never called at all
for a full minute of polling against several contactless cards. Removing
the identifier list entirely, which should filter nothing, changed
nothing. Whatever this is, it sits below the plugin: no plugin code runs
between the session becoming active and the timeout. Before suspecting
the plugin again, check the same cards with an unrelated NFC reader on
the same phone.
