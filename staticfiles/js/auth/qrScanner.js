import QrScannerNative from 'https://cdn.jsdelivr.net/npm/qr-scanner@1.4.2/qr-scanner.min.js';

export class QRScanner {
  constructor(videoEl, canvasEl, onDecode, options = {}) {
    this._videoEl = videoEl;
    this._canvasEl = canvasEl;
    this._ctx = canvasEl.getContext('2d', { willReadFrequently: true });

    const mergedOptions = {
      preferredCamera: 'environment',
      maxScansPerSecond: 30,
      highlightScanRegion: true,
      highlightCodeOutline: true,
      overlay: canvasEl,
      returnDetailedScanResult: true, // Debug mode
      ...options
    };

    // Wrap the user's decode callback so we also log
    const wrappedDecode = (result) => {
      console.log('%c[DEBUG] Raw scan result object:', 'color: orange;', result);

      if (!result?.data) {
        console.warn('[DEBUG] No data detected in frame.');
        return;
      }

      // Call the original callback with just the string
      onDecode(result.data);
    };

    this._scanner = new QrScannerNative(videoEl, wrappedDecode, mergedOptions);

    const drawOverlay = () => {
      const { width, height } = this._canvasEl;
      this._ctx.clearRect(0, 0, width, height);

      // Style
      this._ctx.strokeStyle = 'rgba(0, 255, 0, 0.8)';
      this._ctx.lineWidth = 3;

      const guideSize = Math.min(width, height) * 0.8;
      const guideX = (width - guideSize) / 2;
      const guideY = (height - guideSize) / 2;
      const cornerLen = 25;

      // Corner guides
      this._ctx.beginPath();
      // Top-left
      this._ctx.moveTo(guideX, guideY + cornerLen);
      this._ctx.lineTo(guideX, guideY);
      this._ctx.lineTo(guideX + cornerLen, guideY);
      // Top-right
      this._ctx.moveTo(guideX + guideSize - cornerLen, guideY);
      this._ctx.lineTo(guideX + guideSize, guideY);
      this._ctx.lineTo(guideX + guideSize, guideY + cornerLen);
      // Bottom-left
      this._ctx.moveTo(guideX, guideY + guideSize - cornerLen);
      this._ctx.lineTo(guideX, guideY + guideSize);
      this._ctx.lineTo(guideX + cornerLen, guideY + guideSize);
      // Bottom-right
      this._ctx.moveTo(guideX + guideSize - cornerLen, guideY + guideSize);
      this._ctx.lineTo(guideX + guideSize, guideY + guideSize);
      this._ctx.lineTo(guideX + guideSize, guideY + guideSize - cornerLen);
      this._ctx.stroke();

      // Faint center cross
      this._ctx.strokeStyle = 'rgba(0, 255, 0, 0.5)';
      this._ctx.lineWidth = 1;
      const cx = width / 2;
      const cy = height / 2;
      const crossLen = 15;
      this._ctx.beginPath();
      this._ctx.moveTo(cx - crossLen, cy);
      this._ctx.lineTo(cx + crossLen, cy);
      this._ctx.moveTo(cx, cy - crossLen);
      this._ctx.lineTo(cx, cy + crossLen);
      this._ctx.stroke();

      requestAnimationFrame(drawOverlay);
    };

    requestAnimationFrame(drawOverlay);
  }

  async start() {
    console.log('[DEBUG] Starting camera & scanner...');
    await this._scanner.start();

    this._videoEl.addEventListener('loadeddata', () => {
      console.log('[DEBUG] Video is playing. Resolution:', this._videoEl.videoWidth, 'x', this._videoEl.videoHeight);
    }, { once: true });
  }

  stop() {
    console.log('[DEBUG] Stopping scanner...');
    return this._scanner.stop();
  }
}
