import { Validators, validateField, setupPasswordStrengthIndicator } from './formValidation.js';
import { loadProvinces } from './addressSelect.js';
import { startQRScanner } from './qrScanner.js';
import { 
  showError, 
  clearError, 
  showToast, 
  switchModal, 
  clearModalErrors, 
  setupPasswordToggles 
} from './uiHelpers.js';

export function initializeAuthModules() {
  // Check if QR scanner library is loaded
  if (typeof Html5Qrcode === 'undefined') {
    console.warn('Html5Qrcode not loaded - QR scanning will be disabled');
    const qrButton = document.getElementById('scanPhilSysQR');
    if (qrButton) {
      qrButton.disabled = true;
      qrButton.title = 'QR scanner library not loaded';
    }
  }

  setupPasswordStrengthIndicator();
  setupPasswordToggles();
  loadProvinces();
  setupEventListeners();
}

function setupEventListeners() {
  // Modal switch links
  document.getElementById('openRegisterLink')?.addEventListener('click', function(e) {
    e.preventDefault();
    switchModal('loginModal', 'registerModal');
  });

  document.getElementById('openLoginLink')?.addEventListener('click', function(e) {
    e.preventDefault();
    switchModal('registerModal', 'loginModal');
  });

  // QR Scanner
  document.getElementById('scanPhilSysQR')?.addEventListener('click', async function(e) {
    e.preventDefault();
    try {
      await startQRScanner();
    } catch (error) {
      showToast('error', error.message || 'Failed to start QR scanner');
    }
  });

  // Cancel scan button
  document.getElementById('cancelScanBtn')?.addEventListener('click', function(e) {
    e.preventDefault();
    stopQRScanner();
  });

  // Form submissions
  document.getElementById('registerForm')?.addEventListener('submit', handleRegisterSubmit);
  document.getElementById('loginForm')?.addEventListener('submit', handleLoginSubmit);

  // Modal cleanup
  document.getElementById('registerModal')?.addEventListener('hidden.bs.modal', function() {
    this.querySelector('form').reset();
    clearModalErrors('registerModal');
    stopQRScanner();
  });

  document.getElementById('loginModal')?.addEventListener('hidden.bs.modal', function() {
    this.querySelector('form').reset();
  });
}

async function handleRegisterSubmit(e) {
  e.preventDefault();
  clearModalErrors('registerModal');

  // Validate all fields
  const isValid = validateAllFields();
  if (!isValid) return;

  const form = e.target;
  const submitBtn = form.querySelector('#registerSubmitBtn');
  const originalText = submitBtn.innerHTML;
  
  submitBtn.disabled = true;
  submitBtn.innerHTML = `<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span> Registering...`;

  try {
    const formData = new FormData(form);
    const response = await fetch(form.action, {
      method: 'POST',
      body: formData,
      headers: { 'X-Requested-With': 'XMLHttpRequest' },
    });

    const data = await response.json();

    if (data.success) {
      showToast('success', data.message);
      const modal = bootstrap.Modal.getInstance(document.getElementById('registerModal'));
      modal?.hide();
      setTimeout(() => window.location.href = "/", 1500);
    } else {
      handleFormErrors(data.errors);
    }
  } catch (error) {
    console.error('Registration Error:', error);
    showToast('error', 'Unexpected error occurred. Please try again.');
  } finally {
    submitBtn.disabled = false;
    submitBtn.innerHTML = originalText;
  }
}

function validateAllFields() {
  let isValid = true;

  // Name fields
  if (!validateField('firstName', Validators.name, { fieldName: 'First name' })) isValid = false;
  if (!validateField('lastName', Validators.name, { fieldName: 'Last name' })) isValid = false;
  
  // Address fields
  if (!validateField('province-dropdown', Validators.required, { fieldName: 'Province' })) isValid = false;
  if (!validateField('city-dropdown', Validators.required, { fieldName: 'City/Municipality' })) isValid = false;
  if (!validateField('barangay-dropdown', Validators.required, { fieldName: 'Barangay' })) isValid = false;
  
  // Contact info
  if (!validateField('regEmail', Validators.email)) isValid = false;
  if (!validateField('regPhone', Validators.phone)) isValid = false;
  
  // Credentials
  if (!validateField('regUsername', Validators.required, { fieldName: 'Username' })) isValid = false;
  if (!validateField('regPassword', Validators.password)) isValid = false;
  
  const password = document.getElementById('regPassword').value;
  if (!validateField('confirm_Password', 
    (value) => Validators.confirmPassword(password, value)
  )) isValid = false;

  return isValid;
}

function handleFormErrors(errors) {
  const fieldMap = {
    email: 'regEmail',
    phone_num: 'regPhone',
    username: 'regUsername',
    password: 'regPassword',
    confirm_password: 'confirm_Password',
    qr_data: 'scanPhilSysQR',
    first_name: 'firstName',
    last_name: 'lastName',
    province: 'province-dropdown',
    city: 'city-dropdown',
    barangay: 'barangay-dropdown'
  };

  Object.entries(errors).forEach(([field, message]) => {
    const inputId = fieldMap[field] || null;
    inputId ? showError(inputId, message) : showToast('error', message);
  });
}

function handleLoginSubmit(e) {
  const modal = bootstrap.Modal.getInstance(document.getElementById('loginModal'));
  const overlay = document.createElement('div');
  
  overlay.className = 'fixed inset-0 z-50 flex flex-col items-center justify-center bg-white/80 backdrop-blur-sm';
  overlay.innerHTML = ` 
    <div class="animate-spin rounded-full h-16 w-16 border-t-4 border-b-4 border-blue-500"></div>
    <p class="mt-4 text-lg font-medium text-gray-700">Logging in...</p>
  `;
  
  document.body.appendChild(overlay);
  modal?.hide();
  
  const modalBackdrop = document.querySelector('.modal-backdrop');
  if (modalBackdrop) modalBackdrop.remove();
  
  document.body.style.overflow = 'auto';
  document.body.style.paddingRight = '0';
  
  setTimeout(() => e.target.submit(), 100);
}