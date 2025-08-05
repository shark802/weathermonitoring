document.addEventListener('DOMContentLoaded', function () {
  setupFormValidation();

  const registerForm = document.getElementById('registerForm');
  if (registerForm) {
    registerForm.addEventListener('submit', handleFormSubmit);
  }
});

function setupFormValidation() {
  const fieldMap = {
    firstName: () => validateRequired('firstName', 'First name is required.'),
    lastName: () => validateRequired('lastName', 'Last name is required.'),
    regEmail: validateEmail,
    regPhone: validatePhone,
    regUsername: validateRequired,
    regPassword: validatePassword,
    confirm_Password: validateConfirmPassword,
  };

  Object.entries(fieldMap).forEach(([id, validatorFn]) => {
    const input = document.getElementById(id);
    if (input) {
      input.addEventListener('input', () => clearErrorIfValid(id, validatorFn));
    }
  });

  // Password strength indicators
  document.getElementById('regPassword')?.addEventListener('input', function () {
    const password = this.value;
    const requirements = {
      length: password.length >= 8,
      upper: /[A-Z]/.test(password),
      lower: /[a-z]/.test(password),
      number: /\d/.test(password),
      special: /[!@#$%^&*(),.?":{}|<>]/.test(password),
    };

    Object.keys(requirements).forEach(key => {
      const check = document.querySelector(`.req-${key} .fa-check-circle`);
      const cross = document.querySelector(`.req-${key} .fa-times-circle`);

      if (requirements[key]) {
        check?.classList.remove('d-none');
        cross?.classList.add('d-none');
      } else {
        check?.classList.add('d-none');
        cross?.classList.remove('d-none');
      }
    });
  });

  // Username uniqueness check
  document.getElementById('regUsername')?.addEventListener('blur', function () {
    const username = this.value.trim();
    if (!username) return;

    fetch(`/check-username?username=${encodeURIComponent(username)}`)
      .then(res => res.json())
      .then(data => {
        if (data.exists) showError('regUsername', 'Username already exists.');
        else clearError('regUsername');
      });
  });

  // Name uniqueness check
  document.getElementById('regName')?.addEventListener('blur', function () {
    const name = this.value.trim();
    if (!name) return;

    fetch(`/check-name?name=${encodeURIComponent(name)}`)
      .then(res => res.json())
      .then(data => {
        if (data.exists) showError('regName', 'Name already exists.');
        else clearError('regName');
      });
  });
}

// Generic error display
function showError(inputId, message) {
  const input = document.getElementById(inputId);
  if (!input) return;

  input.classList.add('is-invalid');

  let errorElement = input.parentNode.querySelector('.error-message');
  if (errorElement) {
    errorElement.textContent = message;
  } else {
    errorElement = document.createElement('div');
    errorElement.className = 'text-danger small mt-1 error-message';
    errorElement.textContent = message;
    input.parentNode.insertBefore(errorElement, input.nextSibling);
  }
}

// Password error display without shifting icon
function showPasswordError(inputId, message) {
  const input = document.getElementById(inputId);
  if (!input) return;

  const wrapper = input.closest('.position-relative');
  if (!wrapper) return;

  let errorElement = wrapper.nextElementSibling;
  if (errorElement && errorElement.classList.contains('error-message')) {
    errorElement.textContent = message;
  } else {
    errorElement = document.createElement('div');
    errorElement.className = 'text-danger small mt-1 error-message';
    errorElement.textContent = message;
    wrapper.parentNode.insertBefore(errorElement, wrapper.nextSibling);
  }
}

// Clear error (handles both types)
function clearError(inputId) {
  const input = document.getElementById(inputId);
  if (!input) return;

  input.classList.remove('is-invalid');

  const wrapper = input.closest('.position-relative');
  if (wrapper) {
    const errorElement = wrapper.nextElementSibling;
    if (errorElement && errorElement.classList.contains('error-message')) {
      errorElement.remove();
      return;
    }
  }

  const fallbackError = input.parentNode.querySelector('.error-message');
  if (fallbackError) fallbackError.remove();
}

function clearErrorIfValid(inputId, validatorFn) {
  if (typeof validatorFn === 'function' && validatorFn() === true) {
    clearError(inputId);
  }
}

function clearModalErrors(modalId) {
  const modal = document.getElementById(modalId);
  if (!modal) return;

  // Remove validation classes
  const invalidInputs = modal.querySelectorAll('.is-invalid');
  invalidInputs.forEach(input => input.classList.remove('is-invalid'));

  // Remove error messages
  const errorMessages = modal.querySelectorAll('.error-message');
  errorMessages.forEach(msg => msg.remove());

  // Reset password requirement icons
  const requirementKeys = ['length', 'upper', 'lower', 'number', 'special'];
  requirementKeys.forEach(key => {
    const check = modal.querySelector(`.req-${key} .fa-check-circle`);
    const cross = modal.querySelector(`.req-${key} .fa-times-circle`);
    check?.classList.add('d-none');
    cross?.classList.remove('d-none');
  });
}



function clearErrors() {
  document.querySelectorAll('.error-message').forEach(el => el.remove());
  document.querySelectorAll('.is-invalid').forEach(el => el.classList.remove('is-invalid'));
}

// Form validation
function validateForm() {
  let valid = true;
  if (!validateRequired('firstName', 'First name is required.')) valid = false;
  if (!validateRequired('lastName', 'Last name is required.')) valid = false;
  if (!validateRequired('province', 'Province is required.')) valid = false;
  if (!validateRequired('city', 'City/Municipality is required.')) valid = false;
  if (!validateRequired('barangay', 'Barangay is required.')) valid = false;
  if (!validateEmail()) valid = false;
  if (!validatePhone()) valid = false;
  if (!validateRequired('regUsername', 'Username is required.')) valid = false;
  if (!validatePassword()) valid = false;
  if (!validateConfirmPassword()) valid = false;
  return valid;
}

function validateRequired(id, msg = 'This field is required.') {
  const value = document.getElementById(id)?.value.trim();
  if (!value) {
    showError(id, msg);
    return false;
  }
  return true;
}

function validateEmail() {
  const email = document.getElementById('regEmail')?.value.trim();
  const regex = /^[^@]+@[^@]+\.[^@]+$/;

  if (!email) {
    showError('regEmail', 'Email is required.');
    return false;
  }
  if (!regex.test(email)) {
    showError('regEmail', 'Invalid email format.');
    return false;
  }
  return true;
}

function validatePhone() {
  const phone = document.getElementById('regPhone')?.value.trim();
  const regex = /^\d{11}$/;

  if (!phone) {
    showError('regPhone', 'Phone number is required.');
    return false;
  }
  if (!regex.test(phone)) {
    showError('regPhone', 'Phone number must be exactly 11 digits.');
    return false;
  }
  return true;
}

function validatePassword() {
  const password = document.getElementById('regPassword')?.value;

  if (!password) return showPasswordError('regPassword', 'Password is required.'), false;
  if (password.length < 8) return showPasswordError('regPassword', 'Password must be at least 8 characters.'), false;
  if (!/[A-Z]/.test(password)) return showPasswordError('regPassword', 'At least one uppercase letter required.'), false;
  if (!/[a-z]/.test(password)) return showPasswordError('regPassword', 'At least one lowercase letter required.'), false;
  if (!/\d/.test(password)) return showPasswordError('regPassword', 'At least one number required.'), false;
  if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) return showPasswordError('regPassword', 'At least one special character required.'), false;

  return true;
}

function validateConfirmPassword() {
  const password = document.getElementById('regPassword')?.value;
  const confirm = document.getElementById('confirm_Password')?.value;

  if (!confirm) {
    showPasswordError('confirm_Password', 'Please confirm your password.');
    return false;
  }
  if (password !== confirm) {
    showPasswordError('confirm_Password', 'Passwords do not match.');
    return false;
  }
  return true;
}

// Submit handler
async function handleFormSubmit(e) {
  e.preventDefault();
  clearErrors();

  const form = e.target;
  const submitBtn = form.querySelector('#registerSubmitBtn');
  submitBtn.disabled = true;
  const originalText = submitBtn.innerHTML;
  submitBtn.innerHTML = `<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span> Registering...`;

  if (!validateForm()) {
    submitBtn.disabled = false;
    submitBtn.innerHTML = originalText;
    return;
  }

  try {
    const formData = new FormData(form);
    const res = await fetch(form.action, {
      method: 'POST',
      body: formData,
      headers: { 'X-Requested-With': 'XMLHttpRequest' },
    });
    const data = await res.json();

    if (data.success) {
      showToast('success', data.message);
      const modal = bootstrap.Modal.getInstance(document.getElementById('registerModal'));
      if (modal) modal.hide();
      setTimeout(() => window.location.href = "/", 1500);
    } else {
      Object.entries(data.errors).forEach(([field, msg]) => {
        const map = {
          name: 'regName',
          email: 'regEmail',
          phone_num: 'regPhone',
          username: 'regUsername',
          password: 'regPassword',
          confirm_password: 'confirm_Password',
          qr_data: 'scanPhilSysQR',
        };
        const inputId = map[field] || null;
        inputId ? showError(inputId, msg) : showToast('error', msg);
      });
    }
  } catch (err) {
    console.error('Submit Error:', err);
    showToast('error', 'Unexpected error occurred. Try again.');
  } finally {
    submitBtn.disabled = false;
    submitBtn.innerHTML = originalText;
  }
}

// Bootstrap Toast
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


        $(document).ready(function() {
            // Fetch provinces from PSGC API
            $.ajax({
                url: 'https://psgc.gitlab.io/api/provinces',
                method: 'GET',
                dataType: 'json',
                success: function(data) {
                    data.forEach(function(province) {
                        $('#province-dropdown').append(`<option value="${province.code}">${province.name}</option>`);
                    });
                },
                error: function(xhr, status, error) {
                    console.error('Failed to fetch provinces from PSGC API:', status, error);
                }
            });

            // Load cities/municipalities when a province is selected
            $('#province-dropdown').on('change', function() {
                const provinceCode = $(this).val();
                $('#city-dropdown').prop('disabled', false).empty().append('<option value="" disabled selected>Select City/Municipality</option>');
                $('#barangay-dropdown').prop('disabled', true).empty().append('<option value="" disabled selected>Select Barangay</option>');

                // Fetch municipalities
                $.ajax({
                    url: `https://psgc.gitlab.io/api/provinces/${provinceCode}/municipalities/`,
                    method: 'GET',
                    dataType: 'json',
                    success: function(data) {
                        data.forEach(function(municipality) {
                            $('#city-dropdown').append(`<option value="${municipality.code}" data-type="municipality">${municipality.name}</option>`);
                        });
                    },
                    error: function(xhr, status, error) {
                        console.error('Failed to fetch municipalities:', status, error);
                    }
                });

                // Fetch cities
                $.ajax({
                    url: `https://psgc.gitlab.io/api/provinces/${provinceCode}/cities/`,
                    method: 'GET',
                    dataType: 'json',
                    success: function(data) {
                        data.forEach(function(city) {
                            $('#city-dropdown').append(`<option value="${city.code}" data-type="city">${city.name}</option>`);
                        });
                    },
                    error: function(xhr, status, error) {
                        console.error('Failed to fetch cities:', status, error);
                    }
                });
            });

            // Load barangays when a city/municipality is selected
            $('#city-dropdown').on('change', function() {
                const selectedCode = $(this).val();
                const selectedType = $(this).find(':selected').data('type');

                // Reset barangay dropdown
                $('#barangay-dropdown').prop('disabled', false).empty().append('<option value="" disabled selected>Select Barangay</option>');

                // Determine the correct URL for fetching barangays
                let url;
                if (selectedType === 'city') {
                    url = `https://psgc.gitlab.io/api/cities/${selectedCode}/barangays/`;
                } else {
                    url = `https://psgc.gitlab.io/api/municipalities/${selectedCode}/barangays/`;
                }

                // Fetch barangays based on selected city/municipality
                $.ajax({
                    url: url,
                    method: 'GET',
                    dataType: 'json',
                    success: function(data) {
                        data.forEach(function(barangay) {
                            $('#barangay-dropdown').append(`<option value="${barangay.code}">${barangay.name}</option>`);
                        });
                    },
                    error: function(xhr, status, error) {
                        console.error('Failed to fetch barangays:', status, error);
                    }
                });
            });
        });

document.getElementById('scanPhilSysQR').addEventListener('click', function() {
    Html5Qrcode.getCameras().then(cameras => {
      if (cameras && cameras.length > 0) {
        const scanner = new Html5Qrcode('reader');
        scanner.start(
          cameras[0].id,
          { fps: 10 },
          qrCode => {
            scanner.stop();
            document.getElementById('qrData').value = qrCode;
            
            // Auto-fill name fields from PhilSys QR (example format: "DELA CRUZ,JUAN,SANTOS")
            const nameParts = qrCode.split(',');
            if (nameParts.length >= 2) {
              document.getElementById('lastName').value = nameParts[0].trim();
              document.getElementById('firstName').value = nameParts[1].trim();
              if (nameParts.length > 2) {
                document.getElementById('middleName').value = nameParts[2].trim();
              }
            }
            
            alert("PhilSys QR scanned successfully!");
          },
          error => console.error("QR scan failed:", error)
        );
      } else {
        alert("Camera not found. Please check permissions.");
      }
    }).catch(err => {
      console.error("Camera access error:", err);
      alert("Cannot access camera. Try uploading an image instead.");
    });
  });

function switchModal(fromId, toId) {
    const fromModal = bootstrap.Modal.getInstance(document.getElementById(fromId));
    const toModalElement = document.getElementById(toId);

    if (!fromModal || !toModalElement) {
      console.error('Modal elements not found');
      return;
    }

    fromModal.hide();
    
    document.getElementById(fromId).addEventListener('hidden.bs.modal', function handler() {
      const toModal = new bootstrap.Modal(toModalElement);
      toModal.show();
      this.removeEventListener('hidden.bs.modal', handler); // Clean up
    });
  }

  document.addEventListener('DOMContentLoaded', function() {
    const rememberMe = localStorage.getItem('rememberMe');
    if (rememberMe === 'true') {
        document.getElementById('remember_me').checked = true;
    }
    
    document.getElementById('remember_me').addEventListener('change', function() {
        localStorage.setItem('rememberMe', this.checked);
    });
});

document.addEventListener('DOMContentLoaded', function() {
  document.querySelectorAll('.toggle-password').forEach(toggle => {
    toggle.addEventListener('click', function() {
      const targetId = this.getAttribute('data-target');
      const input = document.getElementById(targetId);
      const icon = this.querySelector('i');
      
      if (input.type === 'password') {
        input.type = 'text';
        icon.classList.replace('fa-eye', 'fa-eye-slash');
        icon.style.color = '#dc3545'; // Red when visible
      } else {
        input.type = 'password';
        icon.classList.replace('fa-eye-slash', 'fa-eye');
        icon.style.color = '#6c757d'; // Gray when hidden
      }
    });
  });
});

document.addEventListener('DOMContentLoaded', function () {
  // Open Register Modal
  document.getElementById('openRegisterLink')?.addEventListener('click', function (e) {
    e.preventDefault();
    switchModal('loginModal', 'registerModal');
  });

  // Open Login Modal
  document.getElementById('openLoginLink')?.addEventListener('click', function (e) {
    e.preventDefault();
    switchModal('registerModal', 'loginModal');
  });

  // Toggle Password Icons
  document.querySelectorAll('.toggle-password').forEach(icon => {
    icon.addEventListener('click', togglePassword);
  });

  // Login Form Submit
  document.getElementById('loginForm')?.addEventListener('submit', function (e) {
    const modalElement = document.getElementById('loginModal');
    const modal = bootstrap.Modal.getInstance(modalElement);

    const overlay = document.createElement('div');
    overlay.className = 'fixed inset-0 z-50 flex flex-col items-center justify-center bg-white/80 backdrop-blur-sm';
    overlay.innerHTML = `
      <div class="animate-spin rounded-full h-16 w-16 border-t-4 border-b-4 border-blue-500"></div>
      <p class="mt-4 text-lg font-medium text-gray-700">Logging in...</p>
    `;
    document.body.appendChild(overlay);

    modal.hide();

    const modalBackdrop = document.querySelector('.modal-backdrop');
    if (modalBackdrop) {
      modalBackdrop.remove();
    }

    document.body.style.overflow = 'auto';
    document.body.style.paddingRight = '0';

    setTimeout(() => {
      this.submit();
    }, 100);
  });

  // Clear login form when modal is hidden
  const loginModal = document.getElementById('loginModal');
  loginModal?.addEventListener('hidden.bs.modal', function () {
    document.getElementById('loginForm').reset();
  });

  // Clear register form when modal is hidden
  const registerModal = document.getElementById('registerModal');
  registerModal?.addEventListener('hidden.bs.modal', function () {
    document.getElementById('registerForm').reset();
    clearModalErrors('registerModal');
  });
});
