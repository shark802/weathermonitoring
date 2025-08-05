// QR Scanner Module
const QRScanner = (function() {
  // Constants
  const SCANNER_CONFIG = {
    fps: 10,
    qrbox: { width: 250, height: 250 },
    aspectRatio: 1.0,
    supportedScanTypes: [Html5QrcodeScanType.SCAN_TYPE_CAMERA],
    rememberLastUsedCamera: true,
    showTorchButtonIfSupported: true
  };

  const SCANNER_UI_STRINGS = {
    noCamera: 'No cameras found. Please ensure you have a working camera.',
    permissionDenied: 'Camera access was denied. Please enable camera permissions.',
    scanSuccess: 'PhilSys QR scanned successfully!',
    scanFailed: 'QR scan failed. Please try again.',
    libraryError: 'QR Scanner library not loaded',
    invalidQRData: 'The scanned QR code does not contain valid PhilSys data'
  };

  // State variables
  let scannerInstance = null;
  let scannerRunning = false;
  let currentCameraId = null;

  // DOM Elements
  const scanButton = document.getElementById('scanPhilSysQR');
  const closeButton = document.getElementById('closeScannerBtn');
  const scannerContainer = document.getElementById('qrScannerContainer');
  const qrDataInput = document.getElementById('qrData');

  // Permission Check
  async function checkCameraPermissions() {
    try {
      if (!navigator.mediaDevices?.getUserMedia) {
        throw new Error('Camera API not supported');
      }
      const stream = await navigator.mediaDevices.getUserMedia({ video: true });
      stream.getTracks().forEach(track => track.stop());
      return true;
    } catch (error) {
      console.error('Camera permission denied:', error);
      return false;
    }
  }

  // Scanner Control
  async function startScanner() {
    if (scannerRunning) return;
    
    try {
      // Show loading state
      setButtonLoading(true);

      if (typeof Html5Qrcode === 'undefined') {
        throw new Error(SCANNER_UI_STRINGS.libraryError);
      }

      const hasPermission = await checkCameraPermissions();
      if (!hasPermission) {
        throw new Error(SCANNER_UI_STRINGS.permissionDenied);
      }

      const cameras = await Html5Qrcode.getCameras();
      if (cameras.length === 0) {
        throw new Error(SCANNER_UI_STRINGS.noCamera);
      }

      scannerInstance = new Html5Qrcode('reader');
      scannerRunning = true;

      // Try to use back camera if available
      currentCameraId = cameras[0].id;
      const backCamera = cameras.find(cam => cam.label.toLowerCase().includes('back'));
      if (backCamera) {
        currentCameraId = backCamera.id;
      }

      await scannerInstance.start(
        currentCameraId,
        SCANNER_CONFIG,
        onScanSuccess,
        onScanError
      );

      // Update UI
      scannerContainer.classList.remove('d-none');
      scanButton.style.display = 'none';
      
      return true;
    } catch (error) {
      console.error('QR Scanner Error:', error);
      scannerRunning = false;
      setButtonLoading(false);
      showToast('error', error.message);
      throw error;
    }
  }

  function stopScanner() {
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

  // Event Handlers
  function onScanSuccess(decodedText) {
    stopScanner().then(() => {
      qrDataInput.value = decodedText;
      processPhilSysData(decodedText);
      showToast('success', SCANNER_UI_STRINGS.scanSuccess);
    });
  }

  function onScanError(error) {
    // Ignore certain benign errors
    if (error && !error.startsWith('No multi format readers configured')) {
      console.error('QR Scan Error:', error);
      showToast('error', SCANNER_UI_STRINGS.scanFailed);
    }
  }

  // Data Processing
  function processPhilSysData(qrData) {
    try {
      // Basic validation
      if (!qrData || typeof qrData !== 'string') {
        throw new Error('Invalid QR data');
      }

      const nameParts = qrData.split(',').map(part => part.trim());
      
      if (nameParts.length < 2) {
        throw new Error('QR data does not contain complete name information');
      }

      // Update fields only if they're empty
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
      showToast('error', SCANNER_UI_STRINGS.invalidQRData);
    }
  }

  // UI Helpers
  function setButtonLoading(isLoading) {
    if (isLoading) {
      scanButton.disabled = true;
      scanButton.innerHTML = 
        '<span class="spinner-border spinner-border-sm" role="status"></span> Initializing scanner...';
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

  // Initialize
  function init() {
    if (scanButton && closeButton) {
      scanButton.addEventListener('click', startScanner);
      closeButton.addEventListener('click', stopScanner);
    }

    // Cleanup when modal closes
    const registerModal = document.getElementById('registerModal');
    if (registerModal) {
      registerModal.addEventListener('hidden.bs.modal', stopScanner);
    }
  }

  // Public API
  return {
    init,
    start: startScanner,
    stop: stopScanner
  };
})();

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', QRScanner.init);