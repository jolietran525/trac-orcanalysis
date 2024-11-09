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

// Load and initialize stop data
d3.csv("./data/20241008_orca_xfer_stop_summary_with_coords.csv").then(data => {
  csvData = data.filter(d => d.stop_lat && d.stop_lng);
  filteredData = csvData;
  displayStopsOnMap(filteredData);
});

// Load the trac_agency.csv file and create a lookup table
d3.csv("./data/trac_agencies.csv").then(data => {
  data.forEach(d => {
    agencyLookup[d.agency_id] = d.agency_name;
  });
});

/**
 * Filter stops based on a given route and agency, and display them on the map.
 * @param {string} routeFilter - The route to filter by.
 * @param {string} agencyFilter - The agency to filter by.
 */
function filterStopsOnMap(routeFilter, agencyFilter) {
  filteredData = (routeFilter && agencyFilter)
    ? csvData.filter(d => d.from_route === routeFilter && d.from_agency === agencyFilter)
    : csvData;
  displayStopsOnMap(filteredData);
}

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
      const key = `${d.stop_code}_${d.stop_lng}_${d.stop_lat}`;
      if (!uniqueStops.has(key)) {
        uniqueStops.add(key);
        return true;
      }
      return false;
    }).map(d => ({
      type: "Feature",
      properties: { 
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
      layer.on("click", () => createTableForStop(feature.properties.stop_code));
    }
  }).addTo(Lmap.map);
}