let filteredStop;
  
function createTableForStop(stopCode, agnecyID) {
    // Filter the CSV data based on stop_code
    const filteredStop = filteredData.filter(d => 
        d.stop_code === stopCode &&
        d.to_gtfs_agency_id === agnecyID );
  
    // Group by `from_route` and `from_agency`, and sum `passenger_count`
    const groupedFromData = d3.rollup(
      filteredStop,
      v => d3.sum(v, d => +d.passenger_count),
      d => d.from_agency,
      d => d.from_route
    );

    // Group by `to_route` and `to_agency`, and sum `passenger_count`
    const groupedToData = d3.rollup(
      filteredStop,
      v => d3.sum(v, d => +d.passenger_count),
      d => d.to_agency,
      d => d.to_route
    );

    // Convert grouped data to array format for the "from" table
    const fromTableData = Array.from(groupedFromData, ([agency, routes]) => 
      Array.from(routes, ([route, passengerCount]) => ({ agency, route, passengerCount }))
    ).flat();

    // Convert grouped data to array format for the "to" table
    const toTableData = Array.from(groupedToData, ([agency, routes]) => 
      Array.from(routes, ([route, passengerCount]) => ({ agency, route, passengerCount }))
    ).flat();
  
    // Define the container where the table will be stored
    const container = document.querySelector('#popup-container');

    // Clear any previous content inside the container
    container.innerHTML = "";

    // Create HTML structure for the pop-up table with tabs
    let tableHtml = `
        <div class="popup-table">
            <button class="close-button" onclick="closeTablePopup()">Close</button>
            <h3>Stop Data for Stop Code: ${stopCode}</h3>
            <div class="tabs">
                <button class="tab-button" onclick="showTab('from')">From</button>
                <button class="tab-button" onclick="showTab('to')">To</button>
            </div>
            <div class="tab-content" id="from-tab">
                <table id="from-table">
                    <thead>
                        <tr>
                            <th onclick="sortTable('from-table', 0)">From Agency</th>
                            <th onclick="sortTable('from-table', 1)">From Route</th>
                            <th onclick="sortTable('from-table', 2)">Passenger Count</th>
                        </tr>
                    </thead>
                    <tbody>
    `;

    // Populate the "from" table rows with data
    fromTableData.forEach(row => {
        tableHtml += `
        <tr>
            <td>${agencyLookup[row.agency]}</td>
            <td>${row.route}</td>
            <td>${row.passengerCount}</td>
        </tr>
        `;
    });

    tableHtml += `
                    </tbody>
                </table>
            </div>
            <div class="tab-content" id="to-tab" style="display:none;">
                <table id="to-table">
                    <thead>
                        <tr>
                            <th onclick="sortTable('to-table', 0)">To Agency</th>
                            <th onclick="sortTable('to-table', 1)">To Route</th>
                            <th onclick="sortTable('to-table', 2)">Passenger Count</th>
                        </tr>
                    </thead>
                    <tbody>
    `;

    // Populate the "to" table rows with data
    toTableData.forEach(row => {
        tableHtml += `
        <tr>
            <td>${agencyLookup[row.agency]}</td>
            <td>${row.route}</td>
            <td>${row.passengerCount}</td>
        </tr>
        `;
    });

    tableHtml += `
                    </tbody>
                </table>
            </div>
        </div>
    `;

    // Insert the table into the specified container
    container.innerHTML = tableHtml;
    adjustLayoutBasedOnPopupContent();

    // Show the "from" tab by default
    showTab('from');
}

// Function to show the appropriate tab
function showTab(tabName) {
    const fromTab = document.getElementById('from-tab');
    const toTab = document.getElementById('to-tab');
    const fromButton = document.querySelector('.tab-button:nth-child(1)');
    const toButton = document.querySelector('.tab-button:nth-child(2)');

    if (tabName === 'from') {
        fromTab.style.display = 'flex';
        toTab.style.display = 'none';
        fromButton.classList.add('active');
        toButton.classList.remove('active');
    } else if (tabName === 'to') {
        fromTab.style.display = 'none';
        toTab.style.display = 'flex';
        fromButton.classList.remove('active');
        toButton.classList.add('active');
    }
}

function closeTablePopup() {
    document.querySelector('.popup-table').remove();
    // // Define the container where the table will be stored
    // const container = document.querySelector('#popup-container');
    // // Clear any previous content inside the container
    // container.innerHTML = "";
    adjustLayoutBasedOnPopupContent();
}

function sortTable(tableId, n) {
    var table, rows, switching, i, x, y, shouldSwitch, dir, switchcount = 0;
    table = document.getElementById(tableId);
    switching = true;
    // Set the sorting direction to ascending:
    dir = "asc";
    /* Make a loop that will continue until
    no switching has been done: */
    while (switching) {
      // Start by saying: no switching is done:
      switching = false;
      rows = table.rows;
      /* Loop through all table rows (except the
      first, which contains table headers): */
      for (i = 1; i < (rows.length - 1); i++) {
        // Start by saying there should be no switching:
        shouldSwitch = false;
        /* Get the two elements you want to compare,
        one from current row and one from the next: */
        x = rows[i].getElementsByTagName("TD")[n];
        y = rows[i + 1].getElementsByTagName("TD")[n];

        /* Check if the two rows should switch place,
        based on the direction, asc or desc: */
        let xValue = x.innerHTML.toLowerCase();
        let yValue = y.innerHTML.toLowerCase();

        // Check if the values are numbers, and convert if so
        if (!isNaN(xValue) && !isNaN(yValue)) {
            xValue = parseFloat(xValue);
            yValue = parseFloat(yValue);
        }

        if (dir == "asc") {
            if (xValue > yValue) {
            shouldSwitch = true;
            break;
            }
        } else if (dir == "desc") {
            if (xValue < yValue) {
            shouldSwitch = true;
            break;
            }
        }

      }
      if (shouldSwitch) {
        /* If a switch has been marked, make the switch
        and mark that a switch has been done: */
        rows[i].parentNode.insertBefore(rows[i + 1], rows[i]);
        switching = true;
        // Each time a switch is done, increase this count by 1:
        switchcount ++;
      } else {
        /* If no switching has been done AND the direction is "asc",
        set the direction to "desc" and run the while loop again. */
        if (switchcount == 0 && dir == "asc") {
          dir = "desc";
          switching = true;
        }
      }
    }
  }
  