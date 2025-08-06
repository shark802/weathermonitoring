// addressSelect.js
import { showToast } from './uiHelpers.js';

const psgcCache = {};

async function fetchWithCache(url, cacheKey) {
  if (psgcCache[cacheKey] !== null && psgcCache[cacheKey] !== undefined) {
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

export async function loadProvinces() {
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

  } catch (error) {
    showToast('error', 'Failed to load provinces. Please try again.');
  }
}

export function setupProvinceDropdownListener() {
  const dropdown = document.getElementById('province-dropdown');
  if (!dropdown) return;

  dropdown.addEventListener('change', async () => {
    const provinceCode = dropdown.value;
    if (!provinceCode) return;

    await loadCitiesAndMunicipalities(provinceCode);
  });
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
    const barangayDropdown = document.getElementById('barangay-dropdown');

    if (!cityDropdown || !barangayDropdown) return;

    cityDropdown.innerHTML = '<option value="" disabled selected>Select City/Municipality</option>';
    barangayDropdown.innerHTML = '<option value="" disabled selected>Select Barangay</option>';
    barangayDropdown.disabled = true;

    municipalities.forEach(m => {
      cityDropdown.innerHTML += `<option value="${m.code}" data-type="municipality">${m.name}</option>`;
    });

    cities.forEach(c => {
      cityDropdown.innerHTML += `<option value="${c.code}" data-type="city">${c.name}</option>`;
    });

    cityDropdown.disabled = false;

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
