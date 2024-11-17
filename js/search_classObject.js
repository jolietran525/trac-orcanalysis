class FormHandler {
  constructor(type) {
    this.type = type;
    this.formContainer = document.querySelector(`.form-container.${type}`);
    this.resultsElement = document.getElementById(`${type}_results`);
    this.boundRemoveFocus = (e) => this.removeFocus(e); // Save the bound function for reuse
    this.init();
  }

  init() {
    this.addSearchListener();
  }

  focusFormContainer() {
    // Display the results element
    this.resultsElement.style.display = "block";

    // Avoid duplicate event listeners
    document.removeEventListener('click', this.boundRemoveFocus);
    document.addEventListener('click', this.boundRemoveFocus);
  }

  removeFocus(e) {
    if (!this.formContainer.contains(e.target)) {
      // Hide results and clean up the click listener
      this.resultsElement.style.display = "none";
      document.removeEventListener('click', this.boundRemoveFocus);
    }
  }

  addSearchListener() {
    // Automatically binds the listener to the type
    const searchBar = document.getElementById(`${this.type}_searchbar`);
    searchBar.addEventListener('input', () => {
      this.searchFunction(this.type);
      this.focusFormContainer(); // Ensure results are visible while typing
    });

    // Focus behavior to show results when the input is focused
    searchBar.addEventListener('focus', () => this.focusFormContainer());
  }

  searchFunction(type) {
    let fromInput = document.getElementById('from_searchbar').value.toLowerCase();
    let toInput = document.getElementById('to_searchbar').value.toLowerCase();
    let input = type === 'from' ? fromInput : toInput;

    if (input.trim() === '') {
      this.clearResults(type);

      if (!fromInput && !toInput) {
        filteredData = csvData;
        displayStopsOnMap(filteredData);
      } else {
        updateMapBasedOnSelection();
      }
    } else {
      let matchingItems = filteredData.filter(d => {
        if (type === 'from') {
          return d.from_route && d.from_route.toLowerCase().includes(input);
        } else {
          return d.to_route && d.to_route.toLowerCase().includes(input);
        }
      });

      this.displayMatchingItems(matchingItems, type);
    }
  }

  clearResults(type) {
    this.resultsElement.innerHTML = '';
  }

  displayMatchingItems(matchingItems, type) {
    this.clearResults(type);
    const uniqueRoutes = new Set();

    matchingItems.forEach(item => {
      const routeKey = type === 'from' ? `${item.from_agency}-${item.from_route}` : `${item.to_agency}-${item.to_route}`;

      if (!uniqueRoutes.has(routeKey)) {
        uniqueRoutes.add(routeKey);

        let listItem = document.createElement('li');
        listItem.innerHTML = `
          ${type === 'from' ? item.from_route : item.to_route}
          ${type === 'from' ? agencyLookup[item.from_agency] : agencyLookup[item.to_agency]}
        `;
        this.resultsElement.appendChild(listItem);

        listItem.addEventListener('click', () => {
          document.getElementById(`${type}_searchbar`).value = `${type === 'from' ? item.from_route : item.to_route} (${type === 'from' ? agencyLookup[item.from_agency] : agencyLookup[item.to_agency]})`;
          updateMapBasedOnSelection();
          this.resultsElement.style.display = "none";
          this.resultsElement.innerHTML = '';
        });
      }
    });
  }
}

function updateMapBasedOnSelection() {
  let fromRoute = document.getElementById('from_searchbar').value.split(' (')[0];
  let toRoute = document.getElementById('to_searchbar').value.split(' (')[0];
  let fromAgencyName = document.getElementById('from_searchbar').value.split('(')[1]?.split(')')[0];
  let toAgencyName = document.getElementById('to_searchbar').value.split('(')[1]?.split(')')[0];

  let fromAgencyId = Object.keys(agencyLookup).find(key => agencyLookup[key] === fromAgencyName);
  let toAgencyId = Object.keys(agencyLookup).find(key => agencyLookup[key] === toAgencyName);

  if (fromRoute && !toRoute) {
    filteredData = csvData.filter(d => d.from_route === fromRoute && d.from_agency === fromAgencyId);
    displayStopsOnMap(filteredData);
  } else if (!fromRoute && toRoute) {
    filteredData = csvData.filter(d => d.to_route === toRoute && d.to_agency === toAgencyId);
    displayStopsOnMap(filteredData);
  } else if (fromRoute && toRoute) {
    filteredData = csvData.filter(d => d.from_route === fromRoute && d.from_agency === fromAgencyId && d.to_route === toRoute && d.to_agency === toAgencyId);
    displayStopsOnMap(filteredData);
  } else {
    displayStopsOnMap(csvData);
  }
}

// Example usage
// Declare variable to store the active FormHandler instance
let activeFormHandler = null;

// Attach click event listeners to initialize or switch FormHandler dynamically
document.getElementById('from_searchbar').addEventListener('click', () => {
  if (!activeFormHandler || activeFormHandler.type !== 'from') {
    // If no active handler or the active handler is not for 'from', create a new instance
    activeFormHandler = new FormHandler('from');
  }
});

document.getElementById('to_searchbar').addEventListener('click', () => {
  if (!activeFormHandler || activeFormHandler.type !== 'to') {
    // If no active handler or the active handler is not for 'to', create a new instance
    activeFormHandler = new FormHandler('to');
  }
});

