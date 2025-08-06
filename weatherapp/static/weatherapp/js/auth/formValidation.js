// formValidation.js

export const Validators = {
  required: (value, fieldName) => {
    if (!value.trim()) return `${fieldName} is required.`;
    return null;
  },

  email: (value) => {
    if (!value.trim()) return 'Email is required.';
    if (!/^[^@]+@[^@]+\.[^@]+$/.test(value)) return 'Invalid email format.';
    return null;
  },

  phone: (value) => {
    if (!value.trim()) return 'Phone number is required.';
    if (!/^\d{11}$/.test(value)) return 'Phone must be 11 digits.';
    return null;
  },

  name: (value, fieldName) => {
    const error = Validators.required(value, fieldName);
    if (error) return error;
    if (!/^[A-Za-z\s-]+$/.test(value)) return `${fieldName} can only contain letters, spaces and hyphens.`;
    return null;
  },

  password: (value) => {
    if (!value) return 'Password is required.';
    if (value.length < 8) return 'Password must be at least 8 characters.';
    if (!/[A-Z]/.test(value)) return 'At least one uppercase letter required.';
    if (!/[a-z]/.test(value)) return 'At least one lowercase letter required.';
    if (!/\d/.test(value)) return 'At least one number required.';
    if (!/[!@#$%^&*(),.?":{}|<>]/.test(value)) return 'At least one special character required.';
    return null;
  },

  confirmPassword: (password, confirmPassword) => {
    if (!confirmPassword) return 'Please confirm your password.';
    if (password !== confirmPassword) return 'Passwords do not match.';
    return null;
  }
};

export function validateField(fieldId, validator, options = {}) {
  const input = document.getElementById(fieldId);
  if (!input) return false;

  const value = input.value;
  const error = validator(value, options.fieldName || fieldId);
  
  if (error) {
    showError(fieldId, error);
    return false;
  }
  
  clearError(fieldId);
  return true;
}

export function setupPasswordStrengthIndicator() {
  document.getElementById('regPassword')?.addEventListener('input', function() {
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
}

// These will be provided by uiHelpers.js
import { showError, clearError } from './uiHelpers.js';
