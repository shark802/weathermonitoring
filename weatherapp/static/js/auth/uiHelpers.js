// Error Handling
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

function clearError(inputId) {
  const input = document.getElementById(inputId);
  if (!input) return;

  input.classList.remove('is-invalid');

  const wrapper = input.closest('.position-relative');
  if (wrapper) {
    const errorElement = wrapper.nextElementSibling;
    if (errorElement?.classList.contains('error-message')) {
      errorElement.remove();
      return;
    }
  }

  const fallbackError = input.parentNode.querySelector('.error-message');
  if (fallbackError) fallbackError.remove();
}

// Toast Notifications
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

// Modal Management
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
    this.removeEventListener('hidden.bs.modal', handler);
  });
}

function clearModalErrors(modalId) {
  const modal = document.getElementById(modalId);
  if (!modal) return;

  modal.querySelectorAll('.is-invalid').forEach(input => {
    input.classList.remove('is-invalid');
  });

  modal.querySelectorAll('.error-message').forEach(msg => {
    msg.remove();
  });

  ['length', 'upper', 'lower', 'number', 'special'].forEach(key => {
    const check = modal.querySelector(`.req-${key} .fa-check-circle`);
    const cross = modal.querySelector(`.req-${key} .fa-times-circle`);
    check?.classList.add('d-none');
    cross?.classList.remove('d-none');
  });
}

// Password Toggle
function setupPasswordToggles() {
  document.querySelectorAll('.toggle-password').forEach(toggle => {
    toggle.addEventListener('click', function() {
      const targetId = this.getAttribute('data-target');
      const input = document.getElementById(targetId);
      const icon = this.querySelector('i');
      
      if (input.type === 'password') {
        input.type = 'text';
        icon.classList.replace('fa-eye', 'fa-eye-slash');
        icon.style.color = '#dc3545';
      } else {
        input.type = 'password';
        icon.classList.replace('fa-eye-slash', 'fa-eye');
        icon.style.color = '#6c757d';
      }
    });
  });
}

export { 
  showError, 
  clearError, 
  showToast, 
  switchModal, 
  clearModalErrors, 
  setupPasswordToggles 
};