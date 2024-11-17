class FormHandler {
  constructor(type) {
    this.type = type;
    this.formContainer = document.querySelector(`.form-container.${type}`);
    this.searchBar = document.getElementById(`${type}_searchbar`);
    this.dropdown = document.getElementById(`${type}_results`);
    this.liElements = document.getElementById(`${this.type}_results`).querySelectorAll('li');
    this.availableRoutes = new Set(); // Track available routes to display in the dropdown
    this.boundRemoveFocus = (e) => this.removeFocus(e); // Save the bound function for reuse
    this.init();
  }

  init() {
    this.addSearchListener();
    this.updateAvailableRoutes(); // Populate the available routes list
  }

  // Add search input event listener
  addSearchListener() {
    this.searchBar.addEventListener('focus', () => this.showDropdown());
    this.searchBar.addEventListener('input', () => this.handleSearchInput());
    this.dropdown.addEventListener('click', (e) => this.handleItemSelect(e)); // Add click event listener for dropdown items
    this.dropdown.addEventListener('dragstart', (e) => e.preventDefault()); // Prevent default drag behavior
  }

  // Show the dropdown when the input field is focused or typing
  showDropdown() {
    if (this.dropdown) {
      this.dropdown.style.display = "block";
      this.populateDropdown();
    }

    document.removeEventListener('click', this.boundRemoveFocus);
    document.addEventListener('click', this.boundRemoveFocus);
  }

  removeFocus(e) {
    if (!this.searchBar.contains(e.target)) {
      // Hide results and clean up the click listener
      this.dropdown.style.display = "none";
      document.removeEventListener('click', this.boundRemoveFocus);
    }
  }

  // Handle user input and filter available routes dynamically
  handleSearchInput() {
    this.populateDropdown();
  }

  // Populate dropdown with filtered routes-agency combinations
  populateDropdown() {
    const dropdownItems = [];
    let input = this.searchBar.value.trim().toLowerCase();
    this.availableRoutes.forEach(routeAgency => {
      const [route, agency] = routeAgency.split('-');
      if (route.toLowerCase().includes(input) || agency.toLowerCase().includes(input)) {
        dropdownItems.push(routeAgency);
      }
    });

    this.dropdown.innerHTML = ''; // Clear existing items
    dropdownItems.forEach(item => {
      const li = document.createElement('li');
      li.textContent = item;
      this.dropdown.appendChild(li);
    });
  }


  // Handle item selection from the dropdown
  handleItemSelect(e) {
    if (e.target.tagName.toLowerCase() === 'li') {
      const selectedItem = e.target.textContent;
      if (selectedItem && !selectedRoutes[this.type].has(selectedItem)) {
        selectedRoutes[this.type].add(selectedItem); // Add to selected routes
        this.updateSearchBar(); // Update the search bar
        this.hideDropdown(); // Hide the dropdown after selection
        this.updateAvailableRoutes(); // Update available routes
        this.updateMapBasedOnSelection(); // Update the map based on selection
      }
    }  
  } 

  // Deselect an item
  deselectItem(item) {
    selectedRoutes[this.type].delete(item);
    
    // Find and remove the corresponding element from the DOM
    const selectedItemsContainer = this.searchBar.parentElement.querySelector('.selected-items-container');
    const itemElements = selectedItemsContainer.querySelectorAll('.selected-item');
    itemElements.forEach(itemElement => {
      if (itemElement.textContent.includes(item)) {
        selectedItemsContainer.removeChild(itemElement);
      }
    });

    this.updateSearchBar();
    this.updateAvailableRoutes();
    this.updateMapBasedOnSelection(); // Ensure the map is updated after deselection
  }

  // Update the search bar with selected items in serialized format
  updateSearchBar() {
    const selectedItemsArray = Array.from(selectedRoutes[this.type]);
    // Clear the search bar
    this.searchBar.value = '';

    // Create a container for selected items
    let selectedItemsContainer = this.searchBar.parentElement.querySelector('.selected-items-container');
    if (!selectedItemsContainer) {
      selectedItemsContainer = document.createElement('div');
      selectedItemsContainer.classList.add('selected-items-container');
      this.searchBar.parentElement.insertBefore(selectedItemsContainer, this.searchBar);
    } else {
      selectedItemsContainer.innerHTML = ''; // Clear existing items
    }

    // Add each selected item with an "x" mark
    selectedItemsArray.forEach(item => {
      const itemElement = document.createElement('span');
      itemElement.classList.add('selected-item');
      itemElement.textContent = item;

      const removeButton = document.createElement('button');
      removeButton.classList.add('remove-button');
      removeButton.textContent = 'x';
      removeButton.addEventListener('click', (e) => {
        e.stopPropagation(); // Prevent the search bar from losing focus
        this.deselectItem(item);
      });

      itemElement.appendChild(removeButton);
      selectedItemsContainer.appendChild(itemElement);
    });

    this.updateMapBasedOnSelection();
  }

  // Hide the dropdown
  hideDropdown() {
    this.dropdown.style.display = "none";
  }

  // Update the available routes list
  updateAvailableRoutes() {
    const allRouteAgencies = new Set();
    
    // Assuming `csvData` is available globally
    csvData.forEach(item => {
      const fromRouteAgency = `${item.from_route}-${agencyLookup[item.from_agency]}`;
      const toRouteAgency = `${item.to_route}-${agencyLookup[item.to_agency]}`;
      allRouteAgencies.add(fromRouteAgency);
      allRouteAgencies.add(toRouteAgency);
    });
    
    // Update available routes based on selected routes
    this.availableRoutes = allRouteAgencies;
  }

  // Update the map based on the selected routes
  updateMapBasedOnSelection() {
    const fromRoutes = selectedRoutes.from;
    const toRoutes = selectedRoutes.to;
  
    // Filter csvData based on from and to routes
    filteredData = csvData.filter(d => {
      const fromMatch = fromRoutes.size
        ? Array.from(fromRoutes).some(routeAgency => {
            const [route, agency] = routeAgency.split('-');
            const agencyId = Object.keys(agencyLookup).find(key => agencyLookup[key] === agency);
            return d.from_route === route && d.from_agency === agencyId;
          })
        : true;
  
      const toMatch = toRoutes.size
        ? Array.from(toRoutes).some(routeAgency => {
            const [route, agency] = routeAgency.split('-');
            const agencyId = Object.keys(agencyLookup).find(key => agencyLookup[key] === agency);
            return d.to_route === route && d.to_agency === agencyId;
          })
        : true;
  
      return fromMatch && toMatch;
    });
  
    displayStopsOnMap(filteredData); // Update the map
  }
  
}

// Declare variable to store the active FormHandler instance
let activeFormHandler = null;
// Global variable to store selected routes
let selectedRoutes = { from: new Set(), to: new Set() };

// Attach click event listeners to initialize or switch FormHandler dynamically
document.getElementById('from_searchbar').addEventListener('click', () => {
  if (!activeFormHandler || activeFormHandler.type !== 'from') {
    // If no active handler or the active handler is not for 'from', create a new instance
    activeFormHandler = new FormHandler('from');
  }
});

document.getElementById('to_searchbar').addEventListener('click', () => {
  if (!activeFormHandler || activeFormHandler.type !== 'to') {
    activeFormHandler = new FormHandler('to');
  }
});



