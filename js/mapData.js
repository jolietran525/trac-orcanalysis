/* =====================================================================================
 * DESCRIPTION: Map Initialization and Data Management
 * 
 * README: 
 * ---- All map initialization and data processing functions can go here. This
 *      includes loading the CSV data, filtering the stops, and displaying them on 
 *      the map.
 * 
 * ===================================================================================== */

// Initialize map from LeafletMap class
const Lmap = new LeafletMap();

// Store the layer globally for easy reference during updates
let csvData, filteredData, routeStopLayer, agencyLookup = {};

let passengerCounts, minPassengerCount, maxPassengerCount;
// Declare variable to store the active FormHandler instance
let activeFormHandler = null;

// Global variable to store selected routes
let selectedRoutes = { from: new Set(), to: new Set() };

// Global variable to store filters
let passengerSlider = {
  passengerCountMin: null,
  passengerCountMax: null
};

const passengerCountSlider = document.getElementById('passenger_count_slider');

function debounce(func, wait) {
  let timeout;
  return function(...args) {
    clearTimeout(timeout);
    timeout = setTimeout(() => func.apply(this, args), wait);
  };
}
const debouncedUpdateMap = debounce(updateMapBasedOnFilters, 300); // Adjust the wait time as needed


// Load and initialize stop data
d3.csv("./data/20241008_orca_xfer_stop_summary_with_coords.csv").then(data => {
  csvData = data.filter(d => d.stop_lat && d.stop_lng);
  filteredData = csvData;
  displayStopsOnMap(filteredData);

  passengerCounts = d3.rollup(
    filteredData,
    v => d3.sum(v, d => +d.passenger_count),
    d => d.to_gtfs_agency_id,
    d => d.stop_code
  );

  // // Calculate min and max passenger counts
  // minPassengerCount = d3.min(
  //   Array.from(passengerCounts.values()) // Extract the values from the Map
  // );
  // maxPassengerCount = d3.max(
  //   Array.from(passengerCounts.values()) // Extract the values from the Map
  // );
    
  // Extract the summed values from the nested Map
  const summedValues = Array.from(passengerCounts.values()).flatMap(d => Array.from(d.values()));

  // Calculate min and max passenger counts
  minPassengerCount = d3.min(summedValues);
  maxPassengerCount = d3.max(summedValues);

  noUiSlider.create(passengerCountSlider, {
    start: [minPassengerCount, maxPassengerCount],
    connect: true,
    range: {
      'min': minPassengerCount,
      'max': maxPassengerCount
    },
    step: 1,
    // tooltips: [true, true],
    tooltips: {
      // tooltips are output only, so only a "to" is needed
      to: function(numericValue) {
          return numericValue.toFixed(0);
      }
    }
  });

  passengerCountSlider.noUiSlider.on('update', (values) => {
    // Parse the slider values directly
    passengerSlider.passengerCountMin = parseInt(values[0], 10); // Lower value
    passengerSlider.passengerCountMax = parseInt(values[1], 10); // Upper value
  
    debouncedUpdateMap(); // Reapply filters and update the map with debounce
  });
  
  
});

// Load the trac_agency.csv file and create a lookup table
d3.csv("./data/trac_agencies.csv").then(data => {
  data.forEach(d => {
    agencyLookup[d.agency_id] = d.agency_name;
  });
});


/**
 * Display the filtered stops on the map as GeoJSON layer
 * @param {Array} data - Array of filtered stop data to display on the map.
 */
function displayStopsOnMap(data) {
  if (routeStopLayer) Lmap.map.removeLayer(routeStopLayer);
  const uniqueStops = new Set();
  
  const stopsGeoJson = {
    type: "FeatureCollection",
    features: data.filter(d => {
      const key = `${d.to_gtfs_agency_id}_${d.stop_code}_${d.stop_lng}_${d.stop_lat}`;
      if (!uniqueStops.has(key)) {
        uniqueStops.add(key);
        return true;
      }
      return false;
    }).map(d => ({
      type: "Feature",
      properties: { 
        to_gtfs_agency_id: d.to_gtfs_agency_id,
        stop_code: d.stop_code
      },
      geometry: { type: "Point", coordinates: [+d.stop_lng, +d.stop_lat] }
    }))
  };

  const markerOptions = {
    radius: 3.5, fillColor: "#ffffff", color: "#000000", weight: 2, opacity: 1, fillOpacity: 1
  };

  routeStopLayer = L.geoJSON(stopsGeoJson, {
    pointToLayer: (feature, latlng) => L.circleMarker(latlng, markerOptions),
    onEachFeature: (feature, layer) => {
      layer.bindTooltip(Object.keys(feature.properties).map(key => 
        `<strong>${key}:</strong> ${feature.properties[key]}`).join("<br>")
      );
    //   layer.on("click", () => createTreemapForStop(feature.properties.stop_code));
      layer.on("click", () => 
        createTableForStop(feature.properties.stop_code, feature.properties.to_gtfs_agency_id));
    }
  }).addTo(Lmap.map);
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

  // const filteredGroupedData = Array.from(groupedData).filter(([stopCode, to_gtfs_agency_id, totalPassengerCount]) => {
  //   return totalPassengerCount >= passengerCountMin && totalPassengerCount <= passengerCountMax;
  // });

  const filteredGroupedData = Array.from(groupedData).flatMap(([to_gtfs_agency_id, stopMap]) => 
    Array.from(stopMap).filter(([stopCode, totalPassengerCount]) => 
      totalPassengerCount >= passengerCountMin && totalPassengerCount <= passengerCountMax
    ).map(([stopCode, totalPassengerCount]) => ({
      to_gtfs_agency_id,
      stopCode,
      totalPassengerCount
    }))
  );
  

  // Step 3: Get the stop_codes that pass the passenger count filter  
  const validStopCodes = new Set(filteredGroupedData.map(({ to_gtfs_agency_id, stopCode }) => ({
    to_gtfs_agency_id,
    stopCode
  })));

  // Step 4: Filter the original filteredData based on the valid stop_codes and selected routes
  // filteredData = filteredData.filter(d => {
  //   // Only keep data whose stop_code and to_gtfs_agency_id are in the validStopCodes set
  //   return Array.from(validStopCodes).some(validStop => 
  //     validStop.stopCode === d.stop_code && validStop.to_gtfs_agency_id === d.to_gtfs_agency_id
  //   );
  // });

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