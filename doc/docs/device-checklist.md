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

## While waiting

| Step | Expected |
|---|---|
| Watch the prompt as fields are found | It names what is still missing, and a spinner runs |
| With haptics on, let it move from one prompt to the next | One light tap per change, no buzzing |
