/* =====================================================================================
 * DESCRIPTION: Map Initialization and Data Management
 * 
 * README: 
 * ---- All map initialization and data processing functions can go here. This
 *      includes loading the CSV data, filtering the stops, and displaying them on 
 *      the map.
 * 
 * ===================================================================================== */

// Global variable to store filters
let passengerSlider = {
  passengerCountMin: null,
  passengerCountMax: null
};

const debouncedUpdateMap = debounce(updateMapBasedOnFilters, 1200); // Adjust the wait time as needed
const passengerCountSlider = document.getElementById('passenger_count_slider');

function initializeSlider() {
  noUiSlider.create(passengerCountSlider, {
    start: [minPassengerCount, maxPassengerCount],
    connect: true,
    range: {
      'min': minPassengerCount,
      'max': maxPassengerCount
    },
    step: 1,
    tooltips: [formatter, formatter] // Use the formatter for both tooltips
  });

  passengerCountSlider.noUiSlider.on('update', (values) => {
    passengerSlider.passengerCountMin = parseInt(values[0], 10);
    passengerSlider.passengerCountMax = parseInt(values[1], 10);
    debouncedUpdateMap();
  });
}

function updateSliderRange() {
  passengerCounts = d3.rollup(
    filteredData,
    v => d3.sum(v, d => +d.passenger_count),
    d => d.to_gtfs_agency_id,
    d => d.stop_code
  );

  // Extract the summed values from the nested Map
  const summedValues = Array.from(passengerCounts.values()).flatMap(d => Array.from(d.values()));

  // Calculate min and max passenger counts
  minPassengerCount = d3.min(summedValues);
  maxPassengerCount = d3.max(summedValues);
  
  passengerCountSlider.noUiSlider.updateOptions({
    start: [minPassengerCount, maxPassengerCount],
    range: {
      'min': minPassengerCount,
      'max': maxPassengerCount
    }
  });

  // Ensure the slider values are within the new range
  if (passengerSlider.passengerCountMin < minPassengerCount || passengerSlider.passengerCountMin > maxPassengerCount) {
    passengerSlider.passengerCountMin = minPassengerCount;
    passengerCountSlider.noUiSlider.set([minPassengerCount, null]);
  }
  if (passengerSlider.passengerCountMax < minPassengerCount || passengerSlider.passengerCountMax > maxPassengerCount) {
    passengerSlider.passengerCountMax = maxPassengerCount;
    passengerCountSlider.noUiSlider.set([null, maxPassengerCount]);
  }
}

function updateMapBasedOnFilters() {
  // Step 1: Filter data based on fromMatch and toMatch
  let filteredData = csvData.filter(d => {
    const fromMatch = selectedRoutes.from.size
      ? Array.from(selectedRoutes.from).some(routeAgency => {
          const [route, agency] = routeAgency.split('-');
          const agencyId = Object.keys(agencyLookup).find(key => agencyLookup[key] === agency);
          return d.from_route === route && d.from_agency === agencyId;
        })
      : true;

    const toMatch = selectedRoutes.to.size
      ? Array.from(selectedRoutes.to).some(routeAgency => {
          const [route, agency] = routeAgency.split('-');
          const agencyId = Object.keys(agencyLookup).find(key => agencyLookup[key] === agency);
          return d.to_route === route && d.to_agency === agencyId;
        })
      : true;

    return fromMatch && toMatch;
  });

  // Step 1: Group the filteredData by stop_code and aggregate passenger_count
  const groupedData = d3.rollup(
    filteredData,
    v => d3.sum(v, d => +d.passenger_count),  // Sum the passenger counts for each group
    d => d.to_gtfs_agency_id,                 // Group by to_gtfs_agency_id first
    d => d.stop_code                          // Then group by stop_code
  );
  
  // Step 2: Filter the grouped data based on the passenger count range
  const passengerCountMin = passengerSlider.passengerCountMin !== null ? passengerSlider.passengerCountMin : -Infinity;
  const passengerCountMax = passengerSlider.passengerCountMax !== null ? passengerSlider.passengerCountMax : Infinity;

  const filteredGroupedData = Array.from(groupedData).flatMap(([to_gtfs_agency_id, stopMap]) => 
    Array.from(stopMap).filter(([stopCode, totalPassengerCount]) => 
      totalPassengerCount >= passengerCountMin && totalPassengerCount <= passengerCountMax
    ).map(([stopCode, totalPassengerCount]) => ({
      to_gtfs_agency_id,
      stopCode,
      totalPassengerCount
    }))
  );
  
  // Step 4: Get the stop_codes that pass the passenger count filter  
  const validStopCodes = new Set(filteredGroupedData.map(({ to_gtfs_agency_id, stopCode }) => ({
    to_gtfs_agency_id,
    stopCode
  })));

  // Convert validStopCodes to a Set of strings for quick lookup
  const validStopCodesSet = new Set(
    Array.from(validStopCodes).map(({ stopCode, to_gtfs_agency_id }) => `${stopCode}-${to_gtfs_agency_id}`)
  );

  filteredData = filteredData.filter(d => {
    // Only keep data whose stop_code and to_gtfs_agency_id are in the validStopCodes set
    return validStopCodesSet.has(`${d.stop_code}-${d.to_gtfs_agency_id}`);
  });

  // Step 5: Update the map with the final filtered data
  displayStopsOnMap(filteredData);
}
