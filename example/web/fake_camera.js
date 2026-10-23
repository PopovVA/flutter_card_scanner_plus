// A camera that is a drawing of a card, for testing the scanner without one.
//
// Loaded only when the page is opened with ?fakeCamera=1, so an ordinary
// run is untouched. It replaces navigator.mediaDevices.getUserMedia with a
// canvas stream, which is enough to exercise everything above the camera:
// the preview, the region of interest, the frame loop, the voting and the
// result. What it cannot test is the hardware, so a permission prompt, a
// torch and a lens that has to focus still want a real device.
(() => {
  const parameters = new URLSearchParams(location.search);
  if (parameters.get('fakeCamera') !== '1') return;

  const width = Number(parameters.get('w') || 1280);
  const height = Number(parameters.get('h') || 720);
  // The share of the frame the card takes, which is how close a hand is
  // holding it. The default fills the guide on a phone sized viewport.
  const cardWidth = Math.round(width * Number(parameters.get('card') || 0.58));
  const cardHeight = Math.round(cardWidth / (85.6 / 53.98));

  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const g = canvas.getContext('2d');

  function paint() {
    g.fillStyle = '#20242b';
    g.fillRect(0, 0, width, height);

    const x = Math.round((width - cardWidth) / 2);
    const y = Math.round((height - cardHeight) / 2);
    g.fillStyle = '#1b3a5c';
    g.fillRect(x, y, cardWidth, cardHeight);

    const scale = cardWidth / 960;
    g.save();
    g.translate(x, y);
    g.scale(scale, scale);
    g.fillStyle = '#ffffff';
    g.font = 'bold 44px "Courier New", monospace';
    g.fillText('ZEBRA MONEY', 40, 110);
    g.font = 'bold 72px "Courier New", monospace';
    g.fillText('4111 1111 1111 1111', 40, 320);
    g.font = 'bold 40px "Courier New", monospace';
    g.fillText('ALICE GREEN', 40, 470);
    g.fillText('12/28', 700, 470);
    g.restore();

    requestAnimationFrame(paint);
  }
  paint();

  const stream = canvas.captureStream(15);
  // The scanner asks the track whether it has a torch, and a canvas track
  // has no such thing. Saying so is the honest answer and the one that
  // hides the button.
  for (const track of stream.getVideoTracks()) {
    track.getCapabilities = () => ({ width, height });
    track.getSettings = () => ({ width, height });
  }

  navigator.mediaDevices.getUserMedia = async () => stream;
  // eslint-disable-next-line no-console
  console.log(`[fake camera] ${width}x${height}, card ${cardWidth}x${cardHeight}`);
})();
