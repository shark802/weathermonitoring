import { Html5Qrcode } from 'https://unpkg.com/html5-qrcode@2.3.8?module';

const QRScanner = (function() {
  // Initialize with null and handle loading state
  let scannerInstance = null;
  let scannerRunning = false;
  let libraryLoaded = false;
  let loadAttempted = false;

  const ScanType = {
    SCAN_TYPE_CAMERA: 0,
    SCAN_TYPE_FILE: 1
  };

  const SCANNER_CONFIG = {
    fps: 10,
    qrbox: { width: 250, height: 250 },
    aspectRatio: 1.0,
    supportedScanTypes: [ScanType.SCAN_TYPE_CAMERA],
    rememberLastUsedCamera: true,
    showTorchButtonIfSupported: true
  };

  // DOM elements cache
  const domElements = {
    scanButton: null,
    closeButton: null,
    scannerContainer: null,
    qrDataInput: null,
    toastContainer: null
  };

  // Load the library with retry mechanism
  async function loadLibrary() {
    if (libraryLoaded) return true;
    if (loadAttempted) return false;

    loadAttempted = true;
    
    try {
      // Verify Html5Qrcode is available
      if (typeof Html5Qrcode === 'undefined') {
        throw new Error('QR Scanner library failed to load');
      }
      
      libraryLoaded = true;
      return true;
    } catch (error) {
      console.error('Library loading error:', error);
      showToast('error', 'Failed to load scanner library. Please refresh the page.');
      return false;
    }
  }

  async function start() {
    if (scannerRunning) return;
    
    try {
      setButtonLoading(true);
      
      // Ensure library is loaded
      const isLoaded = await loadLibrary();
      if (!isLoaded) {
        throw new Error('Scanner library not available');
      }

      const hasPermission = await checkCameraPermissions();
      if (!hasPermission) {
        throw new Error('Camera access denied. Please enable camera permissions.');
      }

      const cameras = await Html5Qrcode.getCameras();
      if (cameras.length === 0) {
        throw new Error('No cameras found on this device');
      }

      scannerInstance = new Html5Qrcode('reader');
      scannerRunning = true;

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
      console.error('Scanner Error:', error);
      scannerRunning = false;
      setButtonLoading(false);
      showToast('error', error.message);
    }
  }

  function stop() {
    if (scannerInstance && scannerRunning) {
      return scannerInstance.stop()
        .then(() => {
          scannerRunning = false;
          scannerInstance.clear();
          if (domElements.scannerContainer) {
            domElements.scannerContainer.classList.add('d-none');
          }
          resetButtonState();
          
          // Restore modal backdrop behavior
          if (domElements.registerModal) {
            const modal = bootstrap.Modal.getInstance(domElements.registerModal);
            if (modal) modal._config.backdrop = true;
          }
          
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
      if (domElements.qrDataInput) {
        domElements.qrDataInput.value = decodedText;
      }
      processPhilSysData(decodedText);
      showToast('success', 'QR code scanned successfully!');
    });
  }

  function onScanError(error) {
    if (error && !error.startsWith('No multi format readers configured')) {
      console.error('QR Scan Error:', error);
      showToast('error', 'Scanning error: ' + error);
    }
  }

  function processPhilSysData(qrData) {
    try {
      if (!qrData || typeof qrData !== 'string') {
        throw new Error('Invalid QR data');
      }

      // Enhanced parsing for PhilSys QR format
      const parsedData = qrData.split(/[,;|]/).map(part => part.trim());
      
      if (parsedData.length < 2) {
        throw new Error('QR data does not contain complete name information');
      }

      // Only update fields that are empty
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

  function triggerInputEvent(element) {
    const event = new Event('input', {
      bubbles: true,
      cancelable: true,
    });
    element.dispatchEvent(event);
  }

  function setButtonLoading(isLoading) {
    if (!domElements.scanButton) return;

    if (isLoading) {
      domElements.scanButton.disabled = true;
      domElements.scanButton.innerHTML = 
        '<span class="spinner-border spinner-border-sm me-2" role="status"></span> Initializing Scanner...';
    } else {
      domElements.scanButton.disabled = false;
      domElements.scanButton.innerHTML = 
        '<i class="fas fa-qrcode me-2"></i>Scan PhilSys QR Code';
    }
  }

  function resetButtonState() {
    if (domElements.scanButton) {
      domElements.scanButton.style.display = 'block';
      setButtonLoading(false);
    }
  }

  function showToast(type, message) {
    if (!domElements.toastContainer) {
      console.warn('Toast container not found');
      return;
    }

    const showNextToast = () => {
      if (toastQueue.length === 0) {
        isToastShowing = false;
        return;
      }

      isToastShowing = true;
      const { type, message } = toastQueue.shift();
      
      const toastEl = document.createElement('div');
      toastEl.className = `toast show align-items-center text-white bg-${
        type === 'success' ? 'success' : 'danger'
      } border-0`;
      toastEl.setAttribute('role', 'alert');
      toastEl.setAttribute('aria-live', 'assertive');
      toastEl.setAttribute('aria-atomic', 'true');
      toastEl.innerHTML = `
        <div class="d-flex">
          <div class="toast-body">${message}</div>
          <button type="button" class="btn-close btn-close-white me-2 m-auto" 
                  data-bs-dismiss="toast" aria-label="Close"></button>
        </div>
      `;

      // Add click handler to close button
      toastEl.querySelector('.btn-close').addEventListener('click', () => {
        toastEl.remove();
        showNextToast();
      });

      domElements.toastContainer.appendChild(toastEl);
      
      setTimeout(() => {
        toastEl.remove();
        showNextToast();
      }, 5000);
    };

    toastQueue.push({ type, message });
    if (!isToastShowing) {
      showNextToast();
    }
  }

  function init() {
    domElements.scanButton = document.getElementById('scanPhilSysQR');
    domElements.closeButton = document.getElementById('closeScannerBtn');
    domElements.scannerContainer = document.getElementById('qrScannerContainer');
    domElements.qrDataInput = document.getElementById('qrData');
    domElements.toastContainer = document.getElementById('toastContainer');

    if (domElements.scanButton) {
      domElements.scanButton.addEventListener('click', start);
    }
    if (domElements.closeButton) {
      domElements.closeButton.addEventListener('click', stop);
    }

    // Preload the library when modal is shown
    const registerModal = document.getElementById('registerModal');
    if (registerModal) {
      registerModal.addEventListener('show.bs.modal', () => {
        loadLibrary().catch(console.error);
      });
    }
  }

  return {
    init,
    start,
    stop
  };
})();

export default QRScanner;