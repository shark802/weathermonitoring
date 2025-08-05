let scannerInstance = null;
let scannerRunning = false;
let lastErrorTime = 0;
const ERROR_DEBOUNCE_TIME = 3000; // 3 seconds

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
    throw new Error('Camera access was denied. Please enable camera permissions.');
  }
}

async function startQRScanner() {
  // Prevent multiple simultaneous scanners
  if (scannerRunning) {
    console.log('Scanner already running');
    return true;
  }

  if (typeof Html5Qrcode === 'undefined') {
    throw new Error('QR Scanner library not loaded. Please refresh the page.');
  }

  try {
    await checkCameraPermissions();

    const cameras = await Html5Qrcode.getCameras();
    if (cameras.length === 0) {
      throw new Error('No cameras found. Please ensure you have a working camera.');
    }

    scannerInstance = new Html5Qrcode('reader');
    scannerRunning = true;

    // Try to find back camera
    const backCamera = findBackCamera(cameras);
    const cameraId = backCamera ? backCamera.id : cameras[0].id;

    await scannerInstance.start(
      cameraId,
      { 
        fps: 10, 
        qrbox: { width: 250, height: 250 },
        aspectRatio: 1.0,
        disableFlip: true // Reduce some error sources
      },
      onQRScanSuccess,
      (error) => {
        // Filter out non-critical errors
        if (!isIgnorableError(error)) {
          onQRScanError(error);
        }
      }
    );

    document.getElementById('qrScannerContainer').classList.remove('d-none');
    return true;
  } catch (error) {
    scannerRunning = false;
    if (scannerInstance) {
      await scannerInstance.clear();
    }
    console.error('QR Scanner initialization failed:', error);
    throw error;
  }
}

function isIgnorableError(error) {
  if (!error) return true;
  
  // List of errors we can safely ignore
  const ignorableErrors = [
    'NotFoundException', 
    'No multi format readers configured',
    'Video stream has ended',
    'QR code parse error, error ='
  ];

  return ignorableErrors.some(ignorable => 
    error.toString().includes(ignorable) ||
    (error.message && error.message.includes(ignorable))
  );
}

async function stopQRScanner() {
  if (!scannerInstance || !scannerRunning) {
    return false;
  }

  try {
    await scannerInstance.stop();
    scannerRunning = false;
    document.getElementById('qrScannerContainer').classList.add('d-none');
    return true;
  } catch (error) {
    console.error('Error stopping scanner:', error);
    return false;
  } finally {
    if (scannerInstance) {
      scannerInstance.clear();
    }
  }
}

function onQRScanSuccess(decodedText) {
  const now = Date.now();
  if (now - lastErrorTime < 1000) return; // Ignore success immediately after error
  
  stopQRScanner().then(() => {
    document.getElementById('qrData').value = decodedText;
    processPhilSysData(decodedText);
    showToast('success', 'PhilSys QR scanned successfully!');
  }).catch(error => {
    console.error('Error during scanner cleanup:', error);
  });
}

function onQRScanError(error) {
  const now = Date.now();
  if (now - lastErrorTime < ERROR_DEBOUNCE_TIME) return;
  lastErrorTime = now;

  if (isIgnorableError(error)) {
    return;
  }

  console.error('QR Scan Error:', error);
  
  let userMessage = 'QR scan failed. Please try again.';
  if (error.message.includes('permission')) {
    userMessage = 'Camera access denied. Please enable camera permissions.';
  } else if (error.message.includes('cameras') || error.message.includes('camera')) {
    userMessage = 'Camera problem. Please check your camera.';
  }

  showToast('error', userMessage);
}

function processPhilSysData(qrData) {
  try {
    const nameParts = qrData.split(',');
    if (nameParts.length >= 2) {
      document.getElementById('lastName').value = nameParts[0].trim();
      document.getElementById('firstName').value = nameParts[1].trim();
      if (nameParts.length > 2) {
        document.getElementById('middleName').value = nameParts[2].trim();
      }
    }
  } catch (error) {
    console.error('Error processing PhilSys data:', error);
  }
}

// Helper function (will be imported from uiHelpers.js)
function showToast(type, message) {
  const container = document.getElementById('toastContainer');
  if (!container) return;

  const toastEl = document.createElement('div');
  toastEl.className = `toast align-items-center text-white bg-${type === 'success' ? 'success' : 'danger'} border-0`;
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
  const toast = new bootstrap.Toast(toastEl);
  toast.show();

  toastEl.addEventListener('hidden.bs.toast', () => {
    toastEl.remove();
  });
}

export { startQRScanner, stopQRScanner, isIgnorableError };