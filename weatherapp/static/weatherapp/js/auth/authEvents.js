import { QRScanner } from './qrScanner.js';
import {
  Validators,
  validateField,
  setupPasswordStrengthIndicator
} from './formValidation.js';
import {
  loadProvinces,
  setupProvinceDropdownListener
} from './addressSelect.js';
import {
  showError,
  clearError,
  showToast,
  switchModal,
  clearModalErrors,
  setupPasswordToggles
} from './uiHelpers.js';

document.addEventListener('DOMContentLoaded', () => {
  // 1) Basic UI wiring
  setupFormValidation();
  setupPasswordToggles();
  loadProvinces();
  setupProvinceDropdownListener();
  setupEventListeners();

  // 2) QR Scanner wiring
  const container   = document.getElementById('qrScannerContainer');
  const videoEl     = document.getElementById('qr-video');
  const canvasEl  = document.getElementById('qr-overlay');
  const qrDataInput = document.getElementById('qrData');
  const scanBtn     = document.getElementById('scanPhilSysQR');
  const closeBtn    = document.getElementById('closeScannerBtn');

  if (container && videoEl && qrDataInput && scanBtn && closeBtn) {
    const scanner = new QRScanner(
      videoEl,
      canvasEl,
      decodedText => {
        qrDataInput.value = decodedText;
        const [last, first, middle] = decodedText.split(',').map(s => s.trim());
        document.getElementById('lastName').value   ||= last;
        document.getElementById('firstName').value  ||= first;
        document.getElementById('middleName').value ||= middle;
        showToast('success', 'QR code scanned');
        scanner.stop();
        container.classList.add('d-none');
      },
      { preferredCamera: 'environment', maxScansPerSecond: 10 }
    );

    scanBtn.addEventListener('click', async () => {
      container.classList.remove('d-none');
      try {
        await scanner.start();
      } catch (e) {
        showToast('error', e.message || 'Unable to access camera');
        container.classList.add('d-none');
      }
    });

    closeBtn.addEventListener('click', () => {
      scanner.stop();
      container.classList.add('d-none');
    });
  }
});

function setupFormValidation() {
  const fieldMap = {
    firstName:   () => validateField('firstName', Validators.name,    { fieldName: 'First name' }),
    lastName:    () => validateField('lastName',  Validators.name,    { fieldName: 'Last name' }),
    regEmail:    () => validateField('regEmail',  Validators.email),
    regPhone:    () => validateField('regPhone',  Validators.phone),
    regUsername: () => validateField('regUsername', Validators.required, { fieldName: 'Username' }),
    regPassword: () => validateField('regPassword', Validators.password),
    confirm_Password: () => {
      const pw = document.getElementById('regPassword').value;
      return validateField('confirm_Password', v => Validators.confirmPassword(pw, v));
    }
  };

  Object.entries(fieldMap).forEach(([id, fn]) => {
    const input = document.getElementById(id);
    if (!input) return;
    input.addEventListener('input', () => {
      if (fn()) clearError(id);
    });
  });

  setupPasswordStrengthIndicator();

  document.getElementById('regUsername')?.addEventListener('blur', function() {
    const u = this.value.trim();
    if (!u) return;
    fetch(`/check-username?username=${encodeURIComponent(u)}`)
      .then(r => r.json())
      .then(d => d.exists ? showError('regUsername','Username already exists.') : clearError('regUsername'));
  });

  document.getElementById('regName')?.addEventListener('blur', function() {
    const n = this.value.trim();
    if (!n) return;
    fetch(`/check-name?name=${encodeURIComponent(n)}`)
      .then(r => r.json())
      .then(d => d.exists ? showError('regName','Name already exists.') : clearError('regName'));
  });
}

function setupEventListeners() {
  // modal toggles
  document.getElementById('openRegisterLink')?.addEventListener('click', e => {
    e.preventDefault();
    switchModal('loginModal','registerModal');
  });
  document.getElementById('openLoginLink')?.addEventListener('click', e => {
    e.preventDefault();
    switchModal('registerModal','loginModal');
  });

  // forms
  document.getElementById('registerForm')?.addEventListener('submit', handleRegisterSubmit);
  document.getElementById('loginForm')?.addEventListener('submit', handleLoginSubmit);

  // reset on close
  document.getElementById('registerModal')?.addEventListener('hidden.bs.modal', function() {
    this.querySelector('form').reset();
    clearModalErrors('registerModal');
  });
  document.getElementById('loginModal')?.addEventListener('hidden.bs.modal', function() {
    this.querySelector('form').reset();
  });
}

// … keep your existing handleRegisterSubmit, validateAllFields, handleFormErrors, handleLoginSubmit …


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
  if (!validateField('province', Validators.required, { fieldName: 'Province' })) isValid = false;
  if (!validateField('city', Validators.required, { fieldName: 'City/Municipality' })) isValid = false;
  if (!validateField('barangay', Validators.required, { fieldName: 'Barangay' })) isValid = false;
  
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
    province: 'province',
    city: 'city',
    barangay: 'barangay'
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