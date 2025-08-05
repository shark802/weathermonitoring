let scannerInstance = null;
let scannerRunning = false;
let errorDisplayed = false; // Track if we've shown an error
const IGNORED_ERRORS = [
  'NotFoundException',
  'No multi format readers configured',
  'Video stream has ended',
  'QR code parse error',
  'Decoder is busy'
];

async function startQRScanner() {
  if (scannerRunning) return true;

  try {
    // Check camera permissions
    if (!navigator.mediaDevices?.getUserMedia) {
      throw new Error('Camera not supported');
    }

    const stream = await navigator.mediaDevices.getUserMedia({ video: true });
    stream.getTracks().forEach(track => track.stop());

    // Get available cameras
    const cameras = await Html5Qrcode.getCameras();
    if (cameras.length === 0) {
      throw new Error('No cameras available');
    }

    scannerInstance = new Html5Qrcode('reader');
    scannerRunning = true;
    errorDisplayed = false; // Reset error state

    // Try to use back camera
    const backCamera = cameras.find(cam => 
      cam.label.toLowerCase().includes('back') || 
      cam.label.toLowerCase().includes('rear')
    );

    await scannerInstance.start(
      backCamera?.id || cameras[0].id,
      {
        fps: 10,
        qrbox: { width: 250, height: 250 },
        disableFlip: true // Reduces some errors
      },
      onQRScanSuccess,
      (error) => {
        if (!shouldDisplayError(error)) return;
        onQRScanError(error);
      }
    );

    document.getElementById('qrScannerContainer').classList.remove('d-none');
    return true;
  } catch (error) {
    handleInitializationError(error);
    throw error;
  }
}

function shouldDisplayError(error) {
  // Don't display if we've already shown an error
  if (errorDisplayed) return false;
  
  // Don't display ignorable errors
  return !IGNORED_ERRORS.some(ignorable => 
    error.toString().includes(ignorable) ||
    (error.message && error.message.includes(ignorable))
  );
}

function handleInitializationError(error) {
  scannerRunning = false;
  let userMessage = 'Failed to start scanner';
  
  if (error.message.includes('permission')) {
    userMessage = 'Camera access denied. Please enable permissions.';
  } else if (error.message.includes('camera') || error.message.includes('device')) {
    userMessage = 'Camera not available. Please check your device.';
  }

  errorDisplayed = true;
  showToast('error', userMessage);
}

function onQRScanSuccess(decodedText) {
  // Skip if we recently showed an error
  if (errorDisplayed) return;
  
  stopQRScanner().then(() => {
    document.getElementById('qrData').value = decodedText;
    processPhilSysData(decodedText);
    showToast('success', 'QR code scanned successfully!');
  });
}

function onQRScanError(error) {
  if (!shouldDisplayError(error)) return;
  
  errorDisplayed = true;
  showToast('error', 'Position the QR code clearly in the frame');
  
  // Auto-reset error state after delay
  setTimeout(() => {
    errorDisplayed = false;
  }, 3000);
}

async function stopQRScanner() {
  if (!scannerRunning) return false;

  try {
    await scannerInstance.stop();
    scannerRunning = false;
    document.getElementById('qrScannerContainer').classList.add('d-none');
    return true;
  } catch (error) {
    console.warn('Error stopping scanner:', error);
    return false;
  }
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