import QrScannerNative from 'https://cdn.jsdelivr.net/npm/qr-scanner@1.4.2/qr-scanner.min.js';

export class QRScanner {
  constructor(videoEl, onDecode, options = {}) {
    this._videoEl = videoEl;
    this._scanner = new QrScannerNative(videoEl, onDecode, options);
  }

  async start() {
    return this._scanner.start();
  }

  stop() {
    return this._scanner.stop();
  }
}
