import { Html5Qrcode } from 'https://unpkg.com/html5-qrcode@2.3.8?module';

const QRScanner = (function() {
  const ScanType = window.Html5QrcodeScanType || { SCAN_TYPE_CAMERA: 0 };

  const SCANNER_CONFIG = {
    fps: 10,
    qrbox: { width: 250, height: 250 },
    aspectRatio: 1.0,
    supportedScanTypes: [ScanType.SCAN_TYPE_CAMERA],
    rememberLastUsedCamera: true,
    showTorchButtonIfSupported: true
  };

  let scannerInstance = null;
  let scannerRunning = false;

  // ⛔ Remove top-level DOM element declarations

  // Declare placeholders
  let scanButton, closeButton, scannerContainer, qrDataInput;

  // Permission Check
  async function checkCameraPermissions() {
    try {
      if (!navigator.mediaDevices?.getUserMedia) {
        throw new Error('Camera API not supported in this browser');
      }
      const stream = await navigator.mediaDevices.getUserMedia({ video: true });
      stream.getTracks().forEach(track => track.stop());
      return true;
    } catch (error) {
      console.error('Camera permission denied:', error);
      return false;
    }
  }

  async function start() {
    if (scannerRunning) return;
    
    try {
      setButtonLoading(true);

      if (typeof Html5Qrcode === 'undefined') {
        throw new Error('QR scanner library not loaded');
      }

      const hasPermission = await checkCameraPermissions();
      if (!hasPermission) {
        throw new Error('Please enable camera permissions to use the QR scanner');
      }

      const cameras = await Html5Qrcode.getCameras();
      if (cameras.length === 0) {
        throw new Error('No cameras found on this device');
      }

      scannerInstance = new Html5Qrcode('reader');
      scannerRunning = true;

      let cameraId = cameras[0].id;
      const backCamera = cameras.find(cam => cam.label.toLowerCase().includes('back'));
      if (backCamera) {
        cameraId = backCamera.id;
      }

      await scannerInstance.start(cameraId, SCANNER_CONFIG, onScanSuccess, onScanError);

      scannerContainer.classList.remove('d-none');
      scanButton.style.display = 'none';
      
    } catch (error) {
      console.error('QR Scanner Error:', error);
      scannerRunning = false;
      setButtonLoading(false);
      showToast('error', error.message);
      throw error;
    }
  }

  function stop() {
    if (scannerInstance && scannerRunning) {
      return scannerInstance.stop()
        .then(() => {
          scannerRunning = false;
          scannerContainer.classList.add('d-none');
          resetButtonState();
          return true;
        })
        .catch(error => {
          console.error('Error stopping scanner:', error);
          return false;
        });
    }
    return Promise.resolve(false);
  }

  function onScanSuccess(decodedText) {
    stop().then(() => {
      qrDataInput.value = decodedText;
      processPhilSysData(decodedText);
      showToast('success', 'QR code scanned successfully!');
    });
  }

  function onScanError(error) {
    if (error && !error.startsWith('No multi format readers configured')) {
      console.error('QR Scan Error:', error);
    }
  }

  function processPhilSysData(qrData) {
    try {
      if (!qrData || typeof qrData !== 'string') {
        throw new Error('Invalid QR data');
      }

      const nameParts = qrData.split(',').map(part => part.trim());
      
      if (nameParts.length < 2) {
        throw new Error('QR data does not contain complete name information');
      }

      const lastNameField = document.getElementById('lastName');
      const firstNameField = document.getElementById('firstName');
      const middleNameField = document.getElementById('middleName');

      if (!lastNameField.value) lastNameField.value = nameParts[0];
      if (!firstNameField.value) firstNameField.value = nameParts[1];
      if (nameParts.length > 2 && !middleNameField.value) {
        middleNameField.value = nameParts[2];
      }
    } catch (error) {
      console.error('Error processing PhilSys data:', error);
      showToast('error', 'The scanned QR code does not contain valid PhilSys data');
    }
  }

  function setButtonLoading(isLoading) {
    if (isLoading) {
      scanButton.disabled = true;
      scanButton.innerHTML = 
        '<span class="spinner-border spinner-border-sm" role="status"></span> Initializing...';
    } else {
      scanButton.disabled = false;
      scanButton.innerHTML = 
        '<i class="fas fa-qrcode me-2"></i>Scan PhilSys QR Code';
    }
  }

  function resetButtonState() {
    scanButton.style.display = 'block';
    setButtonLoading(false);
  }

  function showToast(type, message) {
    const container = document.getElementById('toastContainer');
    if (!container) return;

    const toastEl = document.createElement('div');
    toastEl.className = `toast show align-items-center text-white bg-${type === 'success' ? 'success' : 'danger'} border-0`;
    toastEl.setAttribute('role', 'alert');
    toastEl.setAttribute('aria-live', 'assertive');
    toastEl.setAttribute('aria-atomic', 'true');
    toastEl.innerHTML = `
      <div class="d-flex">
        <div class="toast-body">${message}</div>
        <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast" aria-label="Close"></button>
      </div>
    `;

    container.appendChild(toastEl);
    
    setTimeout(() => {
      toastEl.remove();
    }, 5000);
  }

  function init() {
    // ⏱ Initialize DOM elements here after DOM is loaded
    scanButton = document.getElementById('scanPhilSysQR');
    closeButton = document.getElementById('closeScannerBtn');
    scannerContainer = document.getElementById('qrScannerContainer');
    qrDataInput = document.getElementById('qrData');

    if (scanButton && closeButton) {
      scanButton.addEventListener('click', start);
      closeButton.addEventListener('click', stop);
    }

    const registerModal = document.getElementById('registerModal');
    if (registerModal) {
      registerModal.addEventListener('hidden.bs.modal', stop);
    }
  }

  return {
    init,
    start,
    stop
  };
})();

export default QRScanner;
