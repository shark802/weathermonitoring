const QRScanner = (function() {
  // Configuration constants
  const SCANNER_CONFIG = {
    fps: 10,
    qrbox: { width: 250, height: 250 },
    aspectRatio: 1.0,
    rememberLastUsedCamera: true,
    showTorchButtonIfSupported: true
  };

  // State variables
  let scannerInstance = null;
  let scannerRunning = false;
  let html5QrCodeLib = null;

  // DOM elements cache
  const domElements = {
    scanButton: null,
    closeButton: null,
    scannerContainer: null,
    qrDataInput: null,
    lastNameField: null,
    firstNameField: null,
    middleNameField: null,
    toastContainer: null
  };

  // Load the HTML5 QR Code library dynamically
  async function loadScannerLibrary() {
    if (html5QrCodeLib) return html5QrCodeLib;

    try {
      // Try to use the global version first
      if (window.Html5Qrcode) {
        html5QrCodeLib = window.Html5Qrcode;
        return html5QrCodeLib;
      }

      // Fallback to dynamic import
      const module = await import('https://unpkg.com/html5-qrcode@2.3.8/dist/html5-qrcode.min.js');
      html5QrCodeLib = module.Html5Qrcode;
      return html5QrCodeLib;
    } catch (error) {
      console.error('Failed to load QR scanner library:', error);
      throw new Error('QR scanner library failed to load');
    }
  }

  // Camera permission check
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

  // Main scanner function
  async function start() {
    if (scannerRunning) return;
    
    try {
      setButtonLoading(true);

      // Load library first
      const Html5Qrcode = await loadScannerLibrary();
      
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

      // Prefer back camera if available
      let cameraId = cameras[0].id;
      const backCamera = cameras.find(cam => cam.label.toLowerCase().includes('back'));
      if (backCamera) cameraId = backCamera.id;

      await scannerInstance.start(
        cameraId, 
        SCANNER_CONFIG, 
        onScanSuccess, 
        onScanError
      );

      domElements.scannerContainer?.classList.remove('d-none');
      domElements.scanButton.style.display = 'none';
      
    } catch (error) {
      console.error('QR Scanner Error:', error);
      scannerRunning = false;
      setButtonLoading(false);
      showToast('error', error.message);
    }
  }

  // Stop scanner function
  async function stop() {
    if (scannerInstance && scannerRunning) {
      try {
        await scannerInstance.stop();
        scannerRunning = false;
        domElements.scannerContainer?.classList.add('d-none');
        resetButtonState();
        return true;
      } catch (error) {
        console.error('Error stopping scanner:', error);
        return false;
      }
    }
    return false;
  }

  // Scan success handler
  function onScanSuccess(decodedText) {
    stop().then(() => {
      if (domElements.qrDataInput) {
        domElements.qrDataInput.value = decodedText;
      }
      processPhilSysData(decodedText);
      showToast('success', 'QR code scanned successfully!');
    });
  }

  // Scan error handler
  function onScanError(error) {
    if (error && !error.startsWith('No multi format readers configured')) {
      console.error('QR Scan Error:', error);
    }
  }

  // Process PhilSys data
  function processPhilSysData(qrData) {
    try {
      if (!qrData || typeof qrData !== 'string') {
        throw new Error('Invalid QR data');
      }

      const parsedData = qrData.split(/[,;|]/).map(part => part.trim());
      
      if (parsedData.length < 2) {
        throw new Error('QR data does not contain complete name information');
      }

      // Only update empty fields
      if (domElements.lastNameField && !domElements.lastNameField.value) {
        domElements.lastNameField.value = parsedData[0];
        triggerInputEvent(domElements.lastNameField);
      }
      
      if (domElements.firstNameField && !domElements.firstNameField.value) {
        domElements.firstNameField.value = parsedData[1];
        triggerInputEvent(domElements.firstNameField);
      }
      
      if (parsedData.length > 2 && domElements.middleNameField && !domElements.middleNameField.value) {
        domElements.middleNameField.value = parsedData[2];
        triggerInputEvent(domElements.middleNameField);
      }
    } catch (error) {
      console.error('Error processing PhilSys data:', error);
      showToast('error', 'The scanned QR code does not contain valid PhilSys data');
    }
  }

  // Helper to trigger input events
  function triggerInputEvent(element) {
    const event = new Event('input', { bubbles: true });
    element.dispatchEvent(event);
  }

  // UI state management
  function setButtonLoading(isLoading) {
    if (!domElements.scanButton) return;

    domElements.scanButton.disabled = isLoading;
    domElements.scanButton.innerHTML = isLoading
      ? '<span class="spinner-border spinner-border-sm me-2" role="status"></span> Initializing...'
      : '<i class="fas fa-qrcode me-2"></i>Scan PhilSys QR Code';
  }

  function resetButtonState() {
    if (domElements.scanButton) {
      domElements.scanButton.style.display = 'block';
      setButtonLoading(false);
    }
  }

  // Toast notification system
  function showToast(type, message) {
    if (!domElements.toastContainer) {
      console.warn('Toast container not found');
      return;
    }

    const toastEl = document.createElement('div');
    toastEl.className = `toast show align-items-center text-white bg-${type === 'success' ? 'success' : 'danger'} border-0`;
    toastEl.innerHTML = `
      <div class="d-flex">
        <div class="toast-body">${message}</div>
        <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
      </div>
    `;

    domElements.toastContainer.appendChild(toastEl);
    setTimeout(() => toastEl.remove(), 5000);
  }

  // Initialize the scanner
  function init() {
    // Cache DOM elements
    domElements.scanButton = document.getElementById('scanPhilSysQR');
    domElements.closeButton = document.getElementById('closeScannerBtn');
    domElements.scannerContainer = document.getElementById('qrScannerContainer');
    domElements.qrDataInput = document.getElementById('qrData');
    domElements.lastNameField = document.getElementById('lastName');
    domElements.firstNameField = document.getElementById('firstName');
    domElements.middleNameField = document.getElementById('middleName');
    domElements.toastContainer = document.getElementById('toastContainer');

    // Set up event listeners
    if (domElements.scanButton) {
      domElements.scanButton.addEventListener('click', start);
    }
    if (domElements.closeButton) {
      domElements.closeButton.addEventListener('click', stop);
    }

    // Clean up when modal closes
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