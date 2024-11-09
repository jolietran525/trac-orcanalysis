/**
 * Focus on the form container and display the dropdown list.
 * Add an event listener to remove the focus when clicking outside the form container.
 */
function focusFormContainer(type) {
  // Get the form container element
  const formContainer = document.querySelector(`.form-container.${type}`);
  
  document.getElementById(`${type}_results`).style.display = "block";
  
  // Add an event listener to remove the class when clicking outside the form container
  document.addEventListener('click', function removeFocus(e) {
    if (!formContainer.contains(e.target)) {
      document.removeEventListener('click', removeFocus);
      document.getElementById(`${type}_results`).style.display = "none";
    }
  });
}

/**
 * Search for items based on the input value and display matching results.
 */
function search_function(type) {
  // Get the search input values
  let fromInput = document.getElementById('from_searchbar').value.toLowerCase();
  let toInput = document.getElementById('to_searchbar').value.toLowerCase();

  // Determine which search bar triggered the function
  let input = type === 'from' ? fromInput : toInput;

  // If the input is empty, clear the results for this type
  if (input.trim() === '') {
    clearResults(type);

    // If both search bars are empty, reset the map
    if (!fromInput && !toInput) {
      filteredData = csvData; // Reset filteredData to the original data
      displayStopsOnMap(filteredData); // Reset to show all stops if both inputs are cleared
    } else {
      // If the other search bar is still filled, update the map based on the remaining input
      updateMapBasedOnSelection();
    }
  } else {
    // Filter routes based on the input value and the state of the other search bar
    let matchingItems = filteredData.filter(d => {
      if (type === 'from') {
        return d.from_route && d.from_route.toLowerCase().includes(input);
      } else {
        return d.to_route && d.to_route.toLowerCase().includes(input);
      }
    });

    // Display the matching items in a list (if applicable)
    displayMatchingItems(matchingItems, type);
  }
}

/**
 * Clear the previous search results.
 */
function clearResults(type) {
  let resultsElement = document.getElementById(`${type}_results`);
  resultsElement.innerHTML = '';
}


/**
 * Display matching items in the results list.
 * @param {Array} matchingItems - The array of matching items to display.
 * @param {String} type - The type of search bar ('from' or 'to').
 */
function displayMatchingItems(matchingItems, type) {
  let resultsElement = document.getElementById(`${type}_results`);
  clearResults(type);

  // Use a Set to store unique combinations of `agency` and `route`
  const uniqueRoutes = new Set();

  // Display each unique matching route
  matchingItems.forEach(item => {
    // Unique key for each combination
    const routeKey = type === 'from' ? `${item.from_agency}-${item.from_route}` : `${item.to_agency}-${item.to_route}`;
    
    // Check if the combination is already displayed
    if (!uniqueRoutes.has(routeKey)) {
      uniqueRoutes.add(routeKey); // Mark this combination as displayed

      let listItem = document.createElement('li');
      listItem.innerHTML = `
        <div class="grid-container">
          <span id="route-name">${type === 'from' ? item.from_route : item.to_route}</span>
          <label>${type === 'from' ? agencyLookup[item.from_agency] : agencyLookup[item.to_agency]}</label>
        </div>`;
      resultsElement.appendChild(listItem);

      // Add click event to each list item to filter map stops by that specific route
      listItem.addEventListener('click', () => {
        // Fill the search bar with the clicked item's route name and agency name in brackets
        document.getElementById(`${type}_searchbar`).value = `${type === 'from' ? item.from_route : item.to_route} (${type === 'from' ? agencyLookup[item.from_agency] : agencyLookup[item.to_agency]})`;
        
        // Update the map based on the selected routes
        updateMapBasedOnSelection();
        
        document.getElementById(`${type}_results`).style.display = "none"; // Hide the dropdown list
        resultsElement.innerHTML = ''; // Clear the list after selection
      });
    }
  });
}

/**
 * Update the map based on the selected from_route and to_route.
 */
function updateMapBasedOnSelection() {
  let fromRoute = document.getElementById('from_searchbar').value.split(' (')[0];
  let toRoute = document.getElementById('to_searchbar').value.split(' (')[0];
  let fromAgencyName = document.getElementById('from_searchbar').value.split('(')[1]?.split(')')[0];
  let toAgencyName = document.getElementById('to_searchbar').value.split('(')[1]?.split(')')[0];

  // Find the orca_agency_id for the given agency names
  let fromAgencyId = Object.keys(agencyLookup).find(key => agencyLookup[key] === fromAgencyName);
  let toAgencyId = Object.keys(agencyLookup).find(key => agencyLookup[key] === toAgencyName);

  if (fromRoute && !toRoute) {
    // Show all routes from the selected from_route and from_agency
    filteredData = csvData.filter(d => d.from_route === fromRoute && d.from_agency === fromAgencyId);
    displayStopsOnMap(filteredData);
  } else if (!fromRoute && toRoute) {
    // Show only routes from the selected from_route and from_agency to the selected to_route and to_agency
    filteredData = csvData.filter(d => d.to_route === toRoute && d.to_agency === toAgencyId);
    displayStopsOnMap(filteredData);
  } else if (fromRoute && toRoute) {
    // Show only routes from the selected from_route and from_agency to the selected to_route and to_agency
    filteredData = csvData.filter(d => d.from_route === fromRoute && d.from_agency === fromAgencyId && d.to_route === toRoute && d.to_agency === toAgencyId);
    displayStopsOnMap(filteredData);
  } else {
    // Reset to show all stops if no valid selection
    displayStopsOnMap(csvData);
  }
}
