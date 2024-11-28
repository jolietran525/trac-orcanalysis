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
// function displayStopsOnMap(data) {
//   if (stopLayer) Lmap.map.removeLayer(stopLayer);
//   const uniqueStops = new Set();
  
//   // Calculate the sum of passenger_count for each stop_code using d3.rollup
//   const passengerCounts = d3.rollup(
//     data,
//     v => d3.sum(v, d => +d.passenger_count),
//     d => d.to_gtfs_agency_id,
//     d => d.stop_code
//   );

//   const colorScale = d3.scaleSequential(d3.interpolateWarm)
//       .domain([minPassengerCount, maxPassengerCount]);
  
//   const stopsGeoJson = {
//     type: "FeatureCollection",
//     features: data.filter(d => {
//       const key = `${d.to_gtfs_agency_id}_${d.stop_code}_${d.stop_lng}_${d.stop_lat}`;
//       if (!uniqueStops.has(key)) {
//         uniqueStops.add(key);
//         return true;
//       }
//       return false;
//     }).map(d => ({
//       type: "Feature",
//       properties: { 
//         to_gtfs_agency_id: d.to_gtfs_agency_id,
//         stop_code: d.stop_code,
//         passenger_count: passengerCounts.get(d.to_gtfs_agency_id).get(d.stop_code)
//       },
//       geometry: { type: "Point", coordinates: [+d.stop_lng, +d.stop_lat] }
//     }))
//   };

//   stopLayer = L.geoJSON(stopsGeoJson, {
//     pointToLayer: (feature, latlng) => {
//       const color = colorScale(feature.properties.passenger_count);
//       const markerOptions = {
//         radius: 7
//         , fillColor: color, fillOpacity: 0.5
//         , color: "#000000", weight: 1.2, opacity: 0.7
//       };
//       return L.circleMarker(latlng, markerOptions);
//     },
//     onEachFeature: (feature, layer) => {
//       layer.bindTooltip(Object.keys(feature.properties).map(key => 
//         `<strong>${key}:</strong> ${feature.properties[key]}`).join("<br>")
//       );
//       layer.on("click", () => 
//         createTableForStop(feature.properties.stop_code, feature.properties.to_gtfs_agency_id));
//     }
//   }).addTo(Lmap.map);
// }

function displayStopsOnMap(data) {
  if (stopLayer) Lmap.map.removeLayer(stopLayer);
  const uniqueStops = new Set();
  
  // Calculate the sum of passenger_count for each stop_code using d3.rollup
  const passengerCounts = d3.rollup(
    data,
    v => d3.sum(v, d => +d.passenger_count),
    d => d.to_gtfs_agency_id,
    d => d.stop_code
  );

  // Extract passenger counts into an array
  const passengerCountArray = Array.from(passengerCounts.values()).flatMap(d => Array.from(d.values()));

  const colorScale = d3.scaleQuantile()
  .domain(passengerCountArray)
  .range(d3.schemeSpectral[7]); // Using a predefined color scheme with 9 colors

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
        stop_code: d.stop_code,
        passenger_count: passengerCounts.get(d.to_gtfs_agency_id).get(d.stop_code)
      },
      geometry: { type: "Point", coordinates: [+d.stop_lng, +d.stop_lat] }
    }))
  };

  // Sort features by passenger_count in descending order
  stopsGeoJson.features.sort((a, b) => b.properties.passenger_count - a.properties.passenger_count);

  stopLayer = L.geoJSON(stopsGeoJson, {
    pointToLayer: (feature, latlng) => {
      const color = colorScale(feature.properties.passenger_count);
      const markerOptions = {
        radius: 7,
        fillColor: color,
        fillOpacity: 0.5,
        color: "#000000",
        weight: 1.2,
        opacity: 0.7
      };
      return L.circleMarker(latlng, markerOptions);
    },
    onEachFeature: (feature, layer) => {
      layer.bindTooltip(Object.keys(feature.properties).map(key => 
        `<strong>${key}:</strong> ${feature.properties[key]}`).join("<br>")
      );
      layer.on("click", () => 
        createTableForStop(feature.properties.stop_code, feature.properties.to_gtfs_agency_id));
    }
  }).addTo(Lmap.map);

  // Create the legend control
  const legendControl = L.control({ position: 'bottomright' });

  legendControl.onAdd = function(map) {
    // Clear any existing legend
    const existingLegend = document.querySelector('.info.legend.passenger');
    if (existingLegend) {
      existingLegend.remove();
    }

    const div = L.DomUtil.create('div', 'info legend passenger');
    const quantiles = colorScale.quantiles();
    const colors = colorScale.range();

    div.innerHTML += '<h4>Passenger Count</h4>';

    quantiles.forEach((q, i) => {
      const color = colors[i];
      const range = i === 0 ? `≤ ${formatter.to(q)}` : `${formatter.to(quantiles[i - 1])} - ${formatter.to(q)}`;
      div.innerHTML += `<i class="circle" style="background:${color}"></i> ${range}<br>`;
    });

    // Add the last range
    const lastRange = `> ${formatter.to(quantiles[quantiles.length - 1])}`;
    div.innerHTML += `<i class="circle" style="background:${colors[colors.length - 1]}"></i> ${lastRange}<br>`;

    return div;
  };

  legendControl.addTo(Lmap.map);


  // Create the stop count legend control
  const stopCountLegendControl = L.control({ position: 'bottomright' });

  stopCountLegendControl.onAdd = function(map) {
    // Clear any existing legend
    const existingLegend = document.querySelector('.info.legend.stop-count');
    if (existingLegend) {
      existingLegend.remove();
    }

    const div = L.DomUtil.create('div', 'info legend stop-count');
    const totalStops = stopsGeoJson.features.length;

    div.innerHTML += '<h4>Total Number of Stops</h4>';
    div.innerHTML += `<div>${formatter.to(totalStops)}</div>`;

    return div;
  };

  stopCountLegendControl.addTo(Lmap.map);
  
}
