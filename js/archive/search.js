/* =====================================================================================
 * DESCRIPTION: Search and Dropdown Management
 * 
 * README: 
 * ---- Place all search and dropdown functions here, making the search component
 *      self-contained.
 * 
 * ===================================================================================== */

/**
 * Focus on the form container and display the dropdown list.
 * Add an event listener to remove the focus when clicking outside the form container.
 */
function focusFormContainer() {
  // Get the form container element
  const formContainer = document.querySelector('.form-container');
  
  document.getElementsByClassName("dropdown-list")[0].style.display = "block";
  
  // Add an event listener to remove the class when clicking outside the form container
  document.addEventListener('click', function removeFocus(e) {
    if (!formContainer.contains(e.target)) {
      document.removeEventListener('click', removeFocus);
      document.getElementsByClassName("dropdown-list")[0].style.display = "none";
    }
  });
}
  
/**
 * Search for items based on the input value and display matching results.
 */
function search_function() {
  // Get the search input value
  let input = document.getElementById('searchbar').value.toLowerCase();

  // If the input is empty, clear the results and reset the map
  if (input.trim() === '') {
    clearResults();
    filteredData = csvData; // Reset filteredData to the original data
    displayStopsOnMap(filteredData); // Reset to show all stops if input is cleared
  } else {
    // Filter routes based on the input value (searching by `route_short_name`)
    let matchingItems = csvData.filter(d =>
      d.from_route && d.from_route.toLowerCase().includes(input) );
    
    // Display the matching items in a list (if applicable)
    displayMatchingItems(matchingItems);
  }
}
  
/**
 * Clear the previous search results.
 */
function clearResults() {
  let resultsElement = document.getElementById('results');
  resultsElement.innerHTML = '';
}

/**
 * Display matching items in the results list.
 * @param {Array} matchingItems - The array of matching items to display.
 */
function displayMatchingItems(matchingItems) {
  let resultsElement = document.getElementById('results');
  clearResults();

  // Use a Set to store unique combinations of `from_agency` and `from_route`
  const uniqueRoutes = new Set();

  // Display each unique matching route
  matchingItems.forEach(item => {
    // Unique key for each combination
    const routeKey = `${item.from_agency}-${item.from_route}`;
    
    // Check if the combination is already displayed
    if (!uniqueRoutes.has(routeKey)) {
      uniqueRoutes.add(routeKey); // Mark this combination as displayed

      let listItem = document.createElement('li');
      listItem.innerHTML = `
        <div class="grid-container">
          <span id="route-name">${item.from_route}</span>
          <label>${agencyLookup[item.from_agency]}</label>
        </div>`;
      resultsElement.appendChild(listItem);

      // Add click event to each list item to filter map stops by that specific route
      listItem.addEventListener('click', () => {
        // Fill the search bar with the clicked item's route name
        document.getElementById('searchbar').value = `${item.from_route} (${agencyLookup[item.from_agency]})`;
        
        filterStopsOnMap(item.from_route, item.from_agency); // Display only the clicked route on the map
        document.getElementsByClassName("dropdown-list")[0].style.display = "none"; // Hide the dropdown list
        resultsElement.innerHTML = ''; // Clear the list after selection
      });
    }
  });
}
