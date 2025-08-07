import QrScannerNative from 'https://cdn.jsdelivr.net/npm/qr-scanner@1.4.2/qr-scanner.min.js';

export class QRScanner {
  constructor(videoEl, canvasEl, onDecode, options = {}) {
    this._videoEl  = videoEl;
    this._canvasEl = canvasEl;

    this._scanner = new QrScannerNative(
      videoEl,
      onDecode,
      {
        ...options,
        canvas: canvasEl,
        highlightScanRegion: false 
      }
    );
  }

  async start() {
    // 2. Inject your custom painter before starting
    this._scanner.setCanvasContextOverride((ctx, scanRegion) => {
      // full‐screen dark mask
      ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
      ctx.fillStyle = 'rgba(0, 0, 0, 0.4)';
      ctx.fillRect(0, 0, ctx.canvas.width, ctx.canvas.height);

      // clear the window
      ctx.clearRect(
        scanRegion.x,
        scanRegion.y,
        scanRegion.width,
        scanRegion.height
      );

      // crosshairs
      ctx.strokeStyle = '#00FF00';
      ctx.lineWidth   = 2;
      ctx.beginPath();
      ctx.moveTo(scanRegion.x, scanRegion.y + scanRegion.height / 2);
      ctx.lineTo(scanRegion.x + scanRegion.width, scanRegion.y + scanRegion.height / 2);
      ctx.moveTo(scanRegion.x + scanRegion.width / 2, scanRegion.y);
      ctx.lineTo(scanRegion.x + scanRegion.width / 2, scanRegion.y + scanRegion.height);
      ctx.stroke();
    });

    return this._scanner.start();
  }

  stop() {
    return this._scanner.stop();
  }
}
