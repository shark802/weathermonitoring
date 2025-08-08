import QrScannerNative from 'https://cdn.jsdelivr.net/npm/qr-scanner@1.4.2/qr-scanner.min.js';

export class QRScanner {
  constructor(videoEl, canvasEl, onDecode, options = {}) {
    this._videoEl = videoEl;

    const mergedOptions = {
      preferredCamera: 'environment',
      maxScansPerSecond: 10,
      highlightScanRegion: true,
      highlightCodeOutline: true,
      overlay: canvasEl, // ✅ pass canvas for custom overlay
      video: { width: { ideal: 1280 }, height: { ideal: 720 } },
      ...options
    };

    this._scanner = new QrScannerNative(videoEl, onDecode, mergedOptions);
  }

  async start() {
    return this._scanner.start();
  }

  stop() {
    return this._scanner.stop();
  }
}
