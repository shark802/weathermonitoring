// This now assumes Html5Qrcode is available globally from the CDN

let scannerInstance = null;
let scannerRunning = false;

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

async function startQRScanner() {
  if (scannerRunning) return;
  if (typeof Html5Qrcode === 'undefined') {
    throw new Error('QR Scanner library not loaded');
  }

  try {
    const hasPermission = await checkCameraPermissions();
    if (!hasPermission) {
      throw new Error('Camera access was denied. Please enable camera permissions.');
    }

    const cameras = await Html5Qrcode.getCameras();
    if (cameras.length === 0) {
      throw new Error('No cameras found. Please ensure you have a working camera.');
    }

    scannerInstance = new Html5Qrcode('reader');
    scannerRunning = true;

    await scannerInstance.start(
      cameras[0].id,
      { 
        fps: 10, 
        qrbox: { width: 250, height: 250 },
        aspectRatio: 1.0
      },
      onQRScanSuccess,
      onQRScanError
    );

    // Show scanner UI
    document.getElementById('qrScannerContainer').classList.remove('d-none');
    return true;
  } catch (error) {
    console.error('QR Scanner Error:', error);
    scannerRunning = false;
    throw error;
  }
}

function stopQRScanner() {
  if (scannerInstance && scannerRunning) {
    return scannerInstance.stop()
      .then(() => {
        scannerRunning = false;
        document.getElementById('qrScannerContainer').classList.add('d-none');
        return true;
      })
      .catch(error => {
        console.error('Error stopping scanner:', error);
        return false;
      });
  }
  return Promise.resolve(false);
}

function onQRScanSuccess(decodedText) {
  stopQRScanner().then(() => {
    document.getElementById('qrData').value = decodedText;
    processPhilSysData(decodedText);
    showToast('success', 'PhilSys QR scanned successfully!');
  });
}

function onQRScanError(error) {
  if (error && !error.startsWith('No multi format readers configured')) {
    console.error('QR Scan Error:', error);
    showToast('error', 'QR scan failed. Please try again.');
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

export { startQRScanner, stopQRScanner };