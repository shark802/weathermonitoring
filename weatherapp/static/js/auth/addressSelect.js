const psgcCache = {
  provinces: null,
  municipalities: {},
  cities: {},
  barangays: {}
};

async function fetchWithCache(url, cacheKey) {
  if (psgcCache[cacheKey]) {
    return psgcCache[cacheKey];
  }

  try {
    const response = await fetch(url);
    if (!response.ok) throw new Error('Network response was not ok');
    const data = await response.json();
    psgcCache[cacheKey] = data;
    return data;
  } catch (error) {
    console.error('Fetch error:', error);
    throw error;
  }
}

async function loadProvinces() {
  try {
    const provinces = await fetchWithCache(
      'https://psgc.gitlab.io/api/provinces',
      'provinces'
    );
    
    const dropdown = document.getElementById('province-dropdown');
    if (!dropdown) return;

    dropdown.innerHTML = '<option value="" disabled selected>Select Province</option>';
    provinces.forEach(province => {
      dropdown.innerHTML += `<option value="${province.code}">${province.name}</option>`;
    });

    // Enable city dropdown when province is selected
    dropdown.addEventListener('change', async () => {
      const provinceCode = dropdown.value;
      if (!provinceCode) return;

      await loadCitiesAndMunicipalities(provinceCode);
    });

  } catch (error) {
    showToast('error', 'Failed to load provinces. Please try again.');
  }
}

async function loadCitiesAndMunicipalities(provinceCode) {
  try {
    const [municipalities, cities] = await Promise.all([
      fetchWithCache(
        `https://psgc.gitlab.io/api/provinces/${provinceCode}/municipalities/`,
        `municipalities_${provinceCode}`
      ),
      fetchWithCache(
        `https://psgc.gitlab.io/api/provinces/${provinceCode}/cities/`,
        `cities_${provinceCode}`
      )
    ]);

    const cityDropdown = document.getElementById('city-dropdown');
    if (!cityDropdown) return;

    cityDropdown.innerHTML = '<option value="" disabled selected>Select City/Municipality</option>';
    
    // Add municipalities
    municipalities.forEach(municipality => {
      cityDropdown.innerHTML += `
        <option value="${municipality.code}" data-type="municipality">
          ${municipality.name}
        </option>`;
    });

    // Add cities
    cities.forEach(city => {
      cityDropdown.innerHTML += `
        <option value="${city.code}" data-type="city">
          ${city.name}
        </option>`;
    });

    cityDropdown.disabled = false;

    // Enable barangay dropdown when city/municipality is selected
    cityDropdown.addEventListener('change', async () => {
      const selectedCode = cityDropdown.value;
      const selectedType = cityDropdown.options[cityDropdown.selectedIndex].dataset.type;
      await loadBarangays(selectedCode, selectedType);
    });

  } catch (error) {
    showToast('error', 'Failed to load cities/municipalities. Please try again.');
  }
}

async function loadBarangays(code, type) {
  try {
    const url = type === 'city' 
      ? `https://psgc.gitlab.io/api/cities/${code}/barangays/`
      : `https://psgc.gitlab.io/api/municipalities/${code}/barangays/`;

    const barangays = await fetchWithCache(url, `barangays_${code}`);

    const barangayDropdown = document.getElementById('barangay-dropdown');
    if (!barangayDropdown) return;

    barangayDropdown.innerHTML = '<option value="" disabled selected>Select Barangay</option>';
    barangays.forEach(barangay => {
      barangayDropdown.innerHTML += `<option value="${barangay.code}">${barangay.name}</option>`;
    });

    barangayDropdown.disabled = false;

  } catch (error) {
    showToast('error', 'Failed to load barangays. Please try again.');
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

export { loadProvinces };