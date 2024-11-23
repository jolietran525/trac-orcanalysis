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
let csvData, filteredData, stopLayer, agencyLookup = {};

let passengerCounts, minPassengerCount, maxPassengerCount;
// Declare variable to store the active FormHandler instance
let activeFormHandler = null;

// Global variable to store selected routes
let selectedRoutes = { from: new Set(), to: new Set() };

// Create a formatter using wNumb
const formatter = wNumb({
  decimals: 0, // No decimal places
  thousand: ',', // Use comma as thousand separator
});

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
  
  // Extract the summed values from the nested Map
  const summedValues = Array.from(passengerCounts.values()).flatMap(d => Array.from(d.values()));

  // Calculate min and max passenger counts
  minPassengerCount = d3.min(summedValues);
  maxPassengerCount = d3.max(summedValues);

  initializeSlider()
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
  if (stopLayer) Lmap.map.removeLayer(stopLayer);
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

  stopLayer = L.geoJSON(stopsGeoJson, {
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