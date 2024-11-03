let filteredStop;
  
function createTableForStop(stopCode) {
    // Filter the CSV data based on stop_code
    filteredStop = filteredData.filter(d => d.stop_code === stopCode);
  
    // Group by `from_route` and `from_agency`, and sum `passenger_count`
    const groupedData = d3.rollup(
      filteredStop,
      v => d3.sum(v, d => +d.passenger_count),
      d => d.from_agency,
      d => d.from_route
    );
  
    // Convert grouped data to an array format for easy table generation
    const tableData = Array.from(groupedData, ([agency, routes]) => 
      Array.from(routes, ([route, passengerCount]) => ({
        agency,
        route,
        passengerCount
      }))
    ).flat();
  
    // Define the container where the table will be stored
    const container = document.querySelector('#popup-container');

    // Clear any previous content inside the container
    container.innerHTML = "";

    // Create HTML structure for the pop-up table
    let tableHtml = `
        <div class="popup-table">
            <button class="close-button" onclick="closeTablePopup()">Close</button>
            <h3>Stop Data for Stop Code: ${stopCode}</h3>
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

    // Populate the table rows with data
    tableData.forEach(row => {
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
    `;

    // Insert the table into the DOM and make it visible
    // document.body.insertAdjacentHTML('beforeend', tableHtml);

    // Insert the table into the specified container
    container.innerHTML = tableHtml;
    adjustLayoutBasedOnPopupContent();
}
  
function closeTablePopup() {
    document.querySelector('.popup-table').remove();
    // // Define the container where the table will be stored
    // const container = document.querySelector('#popup-container');
    // // Clear any previous content inside the container
    // container.innerHTML = "";
    adjustLayoutBasedOnPopupContent();
}