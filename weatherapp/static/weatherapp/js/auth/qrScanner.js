// your_app/static/your_app/js/qrScanner.js
import QrScanner from 'https://cdn.jsdelivr.net/npm/qr-scanner@1.4.2/qr-scanner.min.js';

// Point to the worker you copied
QrScanner.WORKER_PATH = '/staticfiles/qrscanner/js/qr-scanner-worker.min.js';

const QRScanner = (function() {
  const videoEl     = document.getElementById('qr-video');
  const scanBtn     = document.getElementById('scanPhilSysQR');
  const closeBtn    = document.getElementById('closeScannerBtn');
  const container   = document.getElementById('qrScannerContainer');
  const qrDataInput = document.getElementById('qrData');
  let   scanner     = null;

  function showToast(type, msg) {
    const c = document.getElementById('toastContainer');
    if (!c) return;
    const toast = document.createElement('div');
    toast.className = `toast show align-items-center text-white bg-${type==='success'?'success':'danger'} border-0`;
    toast.innerHTML = `
      <div class="d-flex">
        <div class="toast-body">${msg}</div>
        <button type="button" class="btn-close btn-close-white me-2 m-auto"
                data-bs-dismiss="toast"></button>
      </div>`;
    c.appendChild(toast);
    setTimeout(()=> toast.remove(), 5000);
  }

  function processData(text) {
    const parts = text.split(',').map(s => s.trim());
    if (parts.length < 2) {
      showToast('error','Invalid PhilSys data');
      return;
    }
    [['lastName',0],['firstName',1],['middleName',2]].forEach(([id,i])=>{
      const el = document.getElementById(id);
      if (el && !el.value && parts[i]) el.value = parts[i];
    });
  }

  async function start() {
    if (scanner) return;
    scanBtn.disabled = true;
    container.classList.remove('d-none');
    document.querySelector('.scanner-loading-fallback')?.classList.remove('d-none');

    scanner = new QrScanner(videoEl, result => {
      stop();
      qrDataInput.value = result;
      processData(result);
      showToast('success','QR code scanned');
    }, {
      preferredCamera: 'environment',
      maxScansPerSecond: 10
    });

    try {
      await scanner.start();
      videoEl.addEventListener('loadedmetadata', ()=>{
        document.querySelector('.scanner-loading-fallback')?.classList.add('d-none');
      });
    } catch (e) {
      console.error(e);
      showToast('error', e.message || 'Cannot start camera');
      stop();
    }
  }

  function stop() {
    if (!scanner) return;
    scanner.stop().then(()=> {
      scanner = null;
      container.classList.add('d-none');
      scanBtn.disabled = false;
    });
  }

  function init() {
    scanBtn.addEventListener('click', start);
    closeBtn.addEventListener('click', stop);
    document.getElementById('registerModal')
      ?.addEventListener('hidden.bs.modal', stop);
  }

  return { init, start, stop };
})();

export { QRScanner };