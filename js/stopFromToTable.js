let filteredStop;
  
// function createTableForStop(stopCode) {
//     // Filter the CSV data based on stop_code
//     filteredStop = filteredData.filter(d => d.stop_code === stopCode);
  
//     // Group by `from_route` and `from_agency`, and sum `passenger_count`
//     const groupedData = d3.rollup(
//       filteredStop,
//       v => d3.sum(v, d => +d.passenger_count),
//       d => d.from_agency,
//       d => d.from_route
//     );
  
//     // Convert grouped data to an array format for easy table generation
//     const tableData = Array.from(groupedData, ([agency, routes]) => 
//       Array.from(routes, ([route, passengerCount]) => ({
//         agency,
//         route,
//         passengerCount
//       }))
//     ).flat();
  
//     // Define the container where the table will be stored
//     const container = document.querySelector('#popup-container');

//     // Clear any previous content inside the container
//     container.innerHTML = "";

//     // Create HTML structure for the pop-up table
//     let tableHtml = `
//         <div class="popup-table">
//             <button class="close-button" onclick="closeTablePopup()">Close</button>
//             <h3>Stop Data for Stop Code: ${stopCode}</h3>
//             <table>
//             <thead>
//                 <tr>
//                 <th>From Agency</th>
//                 <th>From Route</th>
//                 <th>Passenger Count</th>
//                 </tr>
//             </thead>
//             <tbody>
//     `;

//     // Populate the table rows with data
//     tableData.forEach(row => {
//         tableHtml += `
//         <tr>
//             <td>${row.agency}</td>
//             <td>${row.route}</td>
//             <td>${row.passengerCount}</td>
//         </tr>
//         `;
//     });

//     tableHtml += `
//             </tbody>
//             </table>
//         </div>
//     `;

//     // Insert the table into the DOM and make it visible
//     // document.body.insertAdjacentHTML('beforeend', tableHtml);

//     // Insert the table into the specified container
//     container.innerHTML = tableHtml;
//     adjustLayoutBasedOnPopupContent();
// }

function createTableForStop(stopCode) {
    // Filter the CSV data based on stop_code
    const filteredStop = filteredData.filter(d => d.stop_code === stopCode);
  
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
                <table>
                    <thead>
                        <tr>
                            <th>From Agency</th>
                            <th>From Route</th>
                            <th>Passenger Count</th>
                        </tr>
                    </thead>
                    <tbody>
    `;

    // Populate the "from" table rows with data
    fromTableData.forEach(row => {
        tableHtml += `
        <tr>
            <td>${row.agency}</td>
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
                <table>
                    <thead>
                        <tr>
                            <th>To Agency</th>
                            <th>To Route</th>
                            <th>Passenger Count</th>
                        </tr>
                    </thead>
                    <tbody>
    `;

    // Populate the "to" table rows with data
    toTableData.forEach(row => {
        tableHtml += `
        <tr>
            <td>${row.agency}</td>
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