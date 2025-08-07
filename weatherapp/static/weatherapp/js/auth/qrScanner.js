// qrScanner.js
const QRScanner = (function() {
  // Get scan type from global scope or provide default
  const ScanType = window.Html5QrcodeScanType || { 
    SCAN_TYPE_CAMERA: 0
  };

  const SCANNER_CONFIG = {
    fps: 10,
    qrbox: { width: 250, height: 250 },
    aspectRatio: 1.0,
    supportedScanTypes: [ScanType.SCAN_TYPE_CAMERA],
    rememberLastUsedCamera: true,
    showTorchButtonIfSupported: true
  };

  // State variables
  let scannerInstance = null;
  let scannerRunning = false;

  // DOM Elements
  const scanButton = document.getElementById('scanPhilSysQR');
  const closeButton = document.getElementById('closeScannerBtn');
  const scannerContainer = document.getElementById('qrScannerContainer');
  const qrDataInput = document.getElementById('qrData');

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

  function waitForVideoElement() {
    return new Promise((resolve) => {
      const check = () => {
        const video = document.querySelector('#reader video');
        if (video) {
          resolve(video);
        } else {
          setTimeout(check, 100);
        }
      };
      check();
    });
  }

  function waitForVideoReady(video) {
    return new Promise((resolve) => {
      const checkReady = () => {
        if (video.videoWidth > 0 && video.videoHeight > 0) {
          resolve();
        } else {
          setTimeout(checkReady, 100);
        }
      };
      checkReady();
    });
  }

  // Scanner Control
  async function start() {
    if (scannerRunning) return;
    
    try {
      // Show loading state
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

      if (scannerInstance) {
        await scannerInstance.clear(); // optional cleanup
        scannerInstance = null;
      }

      scannerInstance = new Html5Qrcode('reader');
      scannerRunning = true;

      // Try to use back camera if available
      let cameraId = cameras[0].id;
      const backCamera = cameras.find(cam => cam.label.toLowerCase().includes('back'));
      if (backCamera) {
        cameraId = backCamera.id;
      }

      // Show scanner container
      scannerContainer.classList.remove('d-none');
      scanButton.style.display = 'none';

      // Wait for layout to update
      await new Promise(resolve => setTimeout(resolve, 100));

      // Create scanner instance
      scannerInstance = new Html5Qrcode('reader');

      // Wait for video element to appear
      const video = await waitForVideoElement();

      // Wait for video stream to be ready
      await waitForVideoReady(video);
      console.log('Video stream is ready');

      // Now start scanning
      await scannerInstance.start(
        cameraId,
        SCANNER_CONFIG,
        onScanSuccess,
        onScanError
      );


      document.querySelector('.scanner-loading-fallback')?.classList.add('d-none'); 

      
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

  // Event Handlers
  function onScanSuccess(decodedText) {
    stop().then(() => {
      qrDataInput.value = decodedText;
      processPhilSysData(decodedText);
      showToast('success', 'QR code scanned successfully!');
    });
  }

  function onScanError(error) {
    const video = document.querySelector('#reader video');
    const isVideoReady = video && video.videoWidth > 0 && video.videoHeight > 0;

    // Suppress errors until video is ready
    if (!isVideoReady) return;

    // Ignore certain benign errors
    if (error && !error.startsWith('No multi format readers configured')) {
      console.error('QR Scan Error:', error);
    }
  }


  // Data Processing
  function processPhilSysData(qrData) {
    try {
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
      showToast('error', 'The scanned QR code does not contain valid PhilSys data');
    }
  }

  // UI Helpers
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
    toastEl.innerHTML =`
      <div class="d-flex">
        <div class="toast-body">${message}</div>
        <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast" aria-label="Close"></button>
      </div>
    `;

    container.appendChild(toastEl);
    
    // Auto-remove toast after 5 seconds
    setTimeout(() => {
      toastEl.remove();
    }, 5000);
  }

  // Initialize
  function init() {
    if (scanButton && closeButton) {
      scanButton.addEventListener('click', start);
      closeButton.addEventListener('click', stop);
    }

    // Cleanup when modal closes
    const registerModal = document.getElementById('registerModal');
    if (registerModal) {
      registerModal.addEventListener('hidden.bs.modal', stop);
    }
  }

  // Public API
  return {
    init,
    start,
    stop
  };
})();

// Export as default
export default QRScanner;
