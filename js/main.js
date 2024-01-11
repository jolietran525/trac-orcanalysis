// Load map from the leaflet_map.js class
const Lmap = new LeafletMap();

L.Control.Button = L.Control.extend({
  options: {
    position: 'topright',
  },
  onAdd: function (map) {
    var container = L.DomUtil.create('div', 'leaflet-bar leaflet-control buttons');
    var button = L.DomUtil.create('a', 'leaflet-control-button', container);
    L.DomEvent.disableClickPropagation(button);
    button.innerHTML = '<i class="fa-solid fa-rotate-right" id="refresh_button"></i>';

    return container;
  },
  onRemove: function (map) {},
});

var control = new L.Control.Button();
control.addTo(Lmap.map);

/* ---------------------- GLOBAL VARIABLES / FUNCTIONS ---------------------- */
// https://sashamaps.net/docs/resources/20-colors/
// Global array that stores a list of color
let colors = ['#e6194B',
              '#3cb44b', 
              '#4363d8', 
              '#f58231', 
              '#f032e6', 
              '#fabed4', 
              '#469990', 
              '#800000', 
              '#9A6324',
              '#dcbeff', 
              '#42d4f4',
              '#000075',
              '#aaffc3', ];

// Global variable that stores the stops_checkbox in the Options tab in HTML doc
let stops_checkbox;

// Global variable that stores the routes.json data
let routes;

// Global variable that stores the layer of stops along each route
let routeStopLayer;

// Global that stores the source data for the routeStopLayer
let routeStop;

// Global variable that stores the layer of shapes for each route, with the 
let routeShapeLayer_base;

// Global variable that stores the route_shape.geojson data
let routeShape;

// Global variable that stores the layer with highlighted route upon hover data
let highlightRoute;

// Global variable that stores the currently clicked-on route_id
let currentHighlightedRouteId = null;

// Global variable that stores the refresh button from the HTML
const refresh_btn = document.getElementById("refresh_button");

// Add the event to the refresh_button, if there is any clicked-on route, unclick it and reset the style
refresh_btn.addEventListener("click", function () {
  resetHover();
  resetClick(currentHighlightedRouteId);
});

/**
 * Gets the color associated with a specific shape ID from a given array of shape IDs.
 *
 * @param {int} shape_id - The shape ID to find the color for.
 * @param {int[]} shape_ids - An array of shape IDs to search for a match.
 * @returns {string} - The color associated with the given shape ID, or undefined if not found.
 */
function getColorForEachShape(shape_id, shape_ids) {
  for (let i = 0; i < shape_ids.length; i++) {
    if (shape_id === shape_ids[i]) {
      return colors[i];
    }
  }
}


/* -------- ROUTES JSON -------- */

/**
 * Asynchronously fetches route data from the 'routes.json' file and assigns it to the 'routes' variable.
 * This function should be called to initialize the 'routes' variable with the fetched data.
 */
async function routes_data() {
  const response = await fetch('./data/routes.json');
  routes = await response.json();
}

// Call the routes_data function to fetch and initialize route data
routes_data();


/* -------- ROUTES with STOPS LAYER -------- */
// Fetch stops data for each route (routes_stops) using d3.json
const t_routeStop = d3.json("data/routes_stops.geojson");
t_routeStop.then(data => {
  routeStop = data;

  // Define marker options for the stops on the map
  var geojsonMarkerOptions = {
    radius: 3.5,
    fillColor: "#ffffff",
    color: "#000000",
    weight: 2,
    opacity: 1,
    fillOpacity: 1
  };

  // Create a GeoJSON layer for route stops, initially set to NULL
  // Stops will be added to the map only when clicking on the route shape layer
  routeStopLayer  = L.geoJSON(null, {
    pointToLayer: function (feature, geom) {
      // Create a circle marker for each stop using the specified options
      return L.circleMarker(geom, geojsonMarkerOptions);
    },
    onEachFeature: (feature, layer) => {
      // Add a tooltip to each stop layer displaying the Stop ID
      layer.bindTooltip(`<strong>Stop ID:</strong> ${feature.properties.stop_id}`)
    }
  }).addTo(Lmap.map);
  
});


/* -------- ROUTES with SHAPES LAYER -------- */
// Fetch shapes data for each route (routes_shapes) using d3.json
const t_routeShape = d3.json("data/routes_shapes.geojson");
t_routeShape.then(data => {
  routeShape = data;

  // Base layer, shown in map as grey
  routeShapeLayer_base  = L.geoJSON(routeShape, {
      style: function(e) { return { weight: 2, opacity: 0.5, color:  "#a9a9a9" } }
  }).addTo(Lmap.map);
  
  // Transparent layer, only serves as a layer that will be used for hover functionality
  routeShapeLayer_transparent  = L.geoJSON(routeShape, {
    style: function(e) { return { weight: 18, opacity: 0} }
  }).addTo(Lmap.map);

  // Add hover events to the transparent layer
  routeShapeLayer_transparent.on('mouseover', function (e) {
    const route_id = e.layer.feature.properties.route_id;
    highlightRouteHover(route_id);
  });
  
  routeShapeLayer_transparent.on('mouseout', function () {
    resetHover();
  });

  // Add click event to the transparent layer
  routeShapeLayer_transparent.on('click', function (e) {
    const route_id = e.layer.feature.properties.route_id;
    highlightRouteClick(route_id);
    if (stops_checkbox.checked) {
      addStopstoClickedLayer();
    }
  });

  // Highlighted route layer, default as NULL
  // This will be shown upon hovering on the transparent layer (routeShapeLayer_transparent)
  highlightRoute = L.geoJSON(null, {
    style: function(e) { return { weight: 16, opacity: 0.65, color: 'yellow' } } // Adjust the highlighted style
  }).addTo(Lmap.map);

  // Highlight shape layer for the clicked route
  // Only shown upon hovering on the shape item in the legend
  highlightShape = L.geoJSON(null, {
    style: function(e) { return { weight: 16, opacity: 0.65, color: 'orange' } } // Adjust the highlighted style
  }).addTo(Lmap.map);

});


/* -------- HOVER EVENT -------- */

/**
 * Highlight route on hover.
 * Updates the map to highlight a route and displays relevant information when hovered over.
 */

let highlightedFeatures;
let route_matched;
function highlightRouteHover(route_id) {
  // Filter features based on the provided route_id
  highlightedFeatures = routeShape.features.filter(feature => feature.properties.route_id === route_id);

  // Clear existing layers and add new data
  highlightRoute.clearLayers();
  highlightRoute.addData({ type: 'FeatureCollection', features: highlightedFeatures });
  highlightRoute.bringToBack();

  // Find the matching route in the routes data (this will get us the route long name and such)
  route_matched = routes.filter(item => item.route_id === route_id);

  // Update the information displayed in the text-description element
  document.getElementById('text-description').innerHTML = `<p> <strong>${highlightedFeatures[0].properties.agency_name}<strong></p>`;
  document.getElementById('text-description').innerHTML += `<span id="route-name">${highlightedFeatures[0].properties.route_short_name}</span> <label>${route_matched[0].route_long_name}</label>`;
  document.getElementById('text-description').innerHTML += `<p>This route takes <strong>${highlightedFeatures.length}</strong> different shapes.</p>`;
}

/**
 * Reset style for hovered route, clear the information when hovering over a shape is ended.
 */
function resetHover() {
  document.getElementById('text-description').innerHTML = 
      `<p style="font-size:120%"> <strong>Select routes</strong></p>
      <p> Use your cursor to highlight routes and see their names here. Click for more details. </p>`;
  highlightRoute.clearLayers();
  highlightShape.clearLayers();
}

/* -------- CLICKED EVENT -------- */

/**
 * This function will be triggered when routeShape layer is clicked
 * as the result, the stops geometry will be displayed for that clicked route
 */
function addStopstoClickedLayer() {
  const routeStopFeatures = routeStop.features.filter(feature =>
      feature.properties.route_id === currentHighlightedRouteId 
  );

  routeStopLayer.clearLayers();
  routeStopLayer.addData({ type: 'FeatureCollection', features: routeStopFeatures });
}

// Add an event listener to the stops_checkbox element
stops_checkbox = document.querySelector('.check');
stops_checkbox.addEventListener('change', function () {
  toggleRouteStopLayer(stops_checkbox.checked);
});

/** 
 * This function will allow user to show or hide the stops to their preferences
 * when they click on the stop_checkbox option
*/ 
function toggleRouteStopLayer(showStops) {  
  // let showStops = stops_checkbox.checked;
  // Toggle the visibility of the routeStopLayer
  if (showStops) {
    addStopstoClickedLayer();
  } else {
    routeStopLayer.clearLayers();
  }
}

/**
 * Highlight route on click, displays a legend with information, and stores the data of markers for start and end points of each shape.
 */
let startEndMarkers = new Map();
let startMarker = null;
let endMarker = null;
function highlightRouteClick(route_id) {
  // Reset the previous highlighted route if any
  if (currentHighlightedRouteId != null && currentHighlightedRouteId != route_id) {
    resetClick(currentHighlightedRouteId);
    currentHighlightedRouteId = null;
  }

  // Construct legend HTML with route information:
  // Agency Name
  let legendHTML = `<p style="margin-top:0"><strong>${highlightedFeatures[0].properties.agency_name}</strong></p>`;
  // Route Short Name + Route Long Name
  legendHTML += `<div class="grid-container" style="margin-bottom: 15px;">
                    <div>
                      <span id="route-name">${highlightedFeatures[0].properties.route_short_name}</span>
                    </div>
                    <div>
                      <label>${route_matched[0].route_long_name}</label>
                    </div>
                 </div>`;
  // Start/End point markers
  legendHTML += `<div class="grid-container">
                  <div>
                    <span style=
                       "background-color: #FFFFFF;
                        width: 1rem;
                        height: 1rem;
                        display: inline-block;
                        border-radius: 50%;
                        border: 3px solid #000000;
                        vertical-align: text-bottom;
                        margin-right: 10px;">
                    </span>
                    <label>Start</label>
                  </div>
                  <div>
                    <i class="fa-solid fa-location-dot"
                      style=
                         "background: none;
                          color: #FFFFFF;
                          -webkit-text-stroke-width: 2.5px;
                          -webkit-text-stroke-color: #000000;
                          font-size: 1.25rem;
                          vertical-align: text-bottom;
                          margin-right: 10px;">
                    </i>
                    <label>End</label>
                  </div>
                </div>`;
  // Extra info
  legendHTML += `<p style="font-size: small;"><em>Click on the shape to show/hide the start and end point</em></p>`;
  // List of shape info
  legendHTML += `<ul style="margin-top:10px;">`;

  let shape_ids = [];
  let i = 0;

  // Iterate through layers to construct legend items
  highlightRoute.eachLayer(function (layer) {
    const feature = layer.feature;
    shape_ids.push(feature.properties.shape_id);
    legendHTML  += `<li onclick="bringShapetoFront(${feature.properties.shape_id})"
                        onmouseover="highlightShapeHover(${feature.properties.shape_id})"
                        onmouseout="resetHover()">
                            <span class="legend-color" style="background-color: ${colors[i]}" ></span>
                            <label><strong>${feature.properties.trips_count}</strong> trips</label>
                    </li>`;
    i++;
  });
  legendHTML  += `</ul>`;

  // Display the legend and update map styles
  document.querySelector('.legend').style.display = 'block';
  document.querySelector('.legend').innerHTML = legendHTML;

  // Update routeShapeLayer_base styles based for the clicked route
  routeShapeLayer_base.eachLayer(function (layer) {
    if (layer.feature.properties.route_id === route_id) {
      let shape_id = layer.feature.properties.shape_id;
      let color_style = getColorForEachShape(shape_id, shape_ids);
      layer.setStyle({ weight: 6, opacity: 1, color: color_style }); // Adjust the style as needed
      layer.bringToFront();

      // Get coordinates for start and end points
      let coordinates = layer.feature.geometry.coordinates;
      let startLatLng = L.latLng(coordinates[0][1], coordinates[0][0])	;
      let endLatLng = L.latLng(coordinates[coordinates.length - 1][1], coordinates[coordinates.length - 1][0]);
    
      let endMarkerStyles = `
          background: none;
          color: #FFFFFF;
          -webkit-text-stroke-width: 3px;
          -webkit-text-stroke-color:${color_style};
          font-size: 1.5rem;
          left: -0.6rem;
          top: -1.5rem;
          position: relative;`

      const icon = L.divIcon({
        iconAnchor: [0, 0],
        labelAnchor: [0,0],
        iconSize: [0,0],
        tooltipAnchor: [0,0],
        html: `<i class="fa-solid fa-location-dot" style="${endMarkerStyles}"></i>`
      });

      startMarker = L.circleMarker(startLatLng, {radius: 9, weight: 3, color: color_style, fillOpacity: 1, fillColor: 'white'});
      endMarker = L.marker(endLatLng, {icon: icon});

      // Store markers in the startEndMarkers with shape_id as key
      startEndMarkers.set(shape_id, { start: startMarker, end: endMarker });
    }
  });

  // Update the currently highlighted route ID
  currentHighlightedRouteId = route_id; 
}

/**
 * Highlight shape (of clicked route) on hover.
 */
function highlightShapeHover(shape_id) {
  highlightedFeatures = routeShape.features.filter(feature => feature.properties.shape_id === shape_id);
  highlightShape.clearLayers();
  highlightShape.addData({ type: 'FeatureCollection', features: highlightedFeatures });
  highlightShape.bringToBack();
}

/**
 * Bring shape (of the clicked route) to front and toggle markers (start/end markers).
 */
function bringShapetoFront(shape_id) {
  routeShapeLayer_base.eachLayer(function (layer) {
    if (layer.feature.properties.shape_id === shape_id) {
      layer.bringToFront();
   
      let markers_shape = startEndMarkers.get(shape_id);

      // Check if the decorator is currently on the map
      const isMarkersShown = Lmap.map.hasLayer(markers_shape.start) && Lmap.map.hasLayer(markers_shape.end);

      // If it's shown, remove it; otherwise, add it to the map
      if (isMarkersShown) {
        Lmap.map.removeLayer(markers_shape.start);
        Lmap.map.removeLayer(markers_shape.end);
      } else {
        startEndMarkers.forEach(function(value, key) {
          if (key !== shape_id) {
            Lmap.map.removeLayer(value.start);
            Lmap.map.removeLayer(value.end);
          } else {
            markers_shape.start.addTo(Lmap.map);
            markers_shape.end.addTo(Lmap.map);
          }
        });
      }  
    }
  });
  routeStopLayer.bringToFront();
}

/**
 * Reset the style for clicked route and clear the legend, as well as decorator
 */
function resetClick(route_id) {  
  routeShapeLayer_base.eachLayer(function (layer) {
    if (layer.feature.properties.route_id === route_id) {
      routeShapeLayer_base.resetStyle(layer);

      let shape_id = layer.feature.properties.shape_id;
      let markers_shape = startEndMarkers.get(shape_id);

      if (markers_shape) {
        markers_shape.start.remove();
        markers_shape.end.remove();
      }
    }
  });

  routeStopLayer.clearLayers();
  currentHighlightedRouteId = null;

  // Clear the legend display
  document.querySelector('.legend').innerHTML = "";
  document.querySelector('.legend').style.display = 'none';

  // Clear the startEndMarkers
  startEndMarkers.clear();
}

/* -------- TABS FUNCTIONS -------- */
/**
 * Activate the specified tab and update its visual representation.
 * @param {number} n - The index of the tab to activate.
 */

  // Initial check when the page loads
  window.onload = function() {
    resize_tab();
  };

  // Handle resize events
  window.onresize = function() {
    resize_tab();
  };

  var previouslyActiveTab = null;

  function resize_tab() {
    // Check the screen height and width
    var screenHeight = window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight;
    var screenWidth = window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth;
    var tabContent = document.querySelector('.map-panel-tabs .tab-content');
    var totalTabs = 3; // Set the total number of tabs
  
    // Check if the screen size is small
    if (screenHeight <= 600 || screenWidth <= 800) {
      // Remove 'active' class from active tabs
      for (var i = 1; i <= totalTabs; i++) {
        const tabClass = `tab-${i}`;
        const tabElement = document.getElementsByClassName(tabClass)[0];
  
        if (tabElement.classList.contains('active')) {
          previouslyActiveTab = i;
          tabElement.classList.remove('active');
          tabContent.style.display = 'none';
          // document.getElementById(tabId).style.display = 'none';
        }
      }
    } else {
      // Restore 'active' class for the previously active tab
      if (previouslyActiveTab !== null) {
        const tabClass = `tab-${previouslyActiveTab}`;
        const tabElement = document.getElementsByClassName(tabClass)[0];
  
        if (!tabElement.classList.contains('active')) {
          tabElement.classList.add('active');
          activate_tab(previouslyActiveTab);
        }
      }
    }
  }
  
  function activate_tab(n) {
    previouslyActiveTab = n;
    // Check the screen height and width
    var screenHeight = window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight;
    var screenWidth = window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth;
    var totalTabs = 3; // Set the total number of tabs
    var tabContent = document.querySelector('.map-panel-tabs .tab-content');
  
    if (screenHeight > 600 && screenWidth > 800) {
      // Use the initial logic for screen heights greater than 600px
      tabContent.style.display = 'block';
  
      for (var i = 1; i <= totalTabs; i++) {
        const tabId = `tab-${i}`;
        const tabElement = document.getElementById(tabId);
        const tabClass = `tab-${i}`;
  
        tabElement.style.display = i === n ? "block" : "none";
        document.getElementsByClassName(tabClass)[0].className = i === n ? `${tabClass} active` : tabClass;
      }
    } else {
      // Toggle the display of the tab content for screen heights less than or equal to 600px
      for (var i = 1; i <= totalTabs; i++) {
        const tabId = `tab-${i}`;
        const tabElement = document.getElementById(tabId);
        const tabClass = `tab-${i}`;
  
        if (i === n) {
          // If tabElement is currently displayed and i equals n, hide it and remove "active" class
          if (tabElement.style.display === 'block') {
            tabContent.style.display = 'none';
            tabElement.style.display = 'none';
            document.getElementsByClassName(tabClass)[0].classList.remove('active');
          } else {
            // If tabElement is not currently displayed, show it and add "active" class
            tabContent.style.display = 'block';
            tabElement.style.display = 'block';
            document.getElementsByClassName(tabClass)[0].className = `${tabClass} active`;
          }
        } else {
          // For other tabs, set display and class accordingly
          tabElement.style.display = 'none';
          document.getElementsByClassName(tabClass)[0].className = tabClass;
        }
      }
    }
  }
  
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
    let input = document.getElementById('searchbar').value.toLowerCase();

    if (input.trim() === '') {
        // If the input is empty, clear the results
        clearResults();
    } else {
        let matchingItems = routes.filter(item => item.route_short_name.toLowerCase().includes(input));
        // Display the matching items
        displayMatchingItems(matchingItems);
    }
}

/**
 * Clear the previous search results.
 */
function clearResults() {
    // Assuming you have an element with the id "results" to display the matching items
    let resultsElement = document.getElementById('results');

    // Clear previous results
    resultsElement.innerHTML = '';
}

/**
 * Display matching items in the results list.
 * @param {Array} matchingItems - The array of matching items to display.
 */
function displayMatchingItems(matchingItems) {
  let resultsElement = document.getElementById('results');

  // Clear previous results
  clearResults();

  // Display the matching items
  matchingItems.forEach(item => {
      let listItem = document.createElement('li');
      listItem.innerHTML = `<span id="route-name">${item.route_short_name}</span> ${item.route_long_name}`;
      resultsElement.appendChild(listItem);

      listItem.addEventListener('mouseover', function () {
        highlightRouteHover(item.route_id);
      });

      listItem.addEventListener('mouseout', function () {
        resetHover();
      });

      // Add a click event listener to each list item
      listItem.addEventListener('click', function () {
          highlightRouteClick(item.route_id);
          if (stops_checkbox.checked) {
            addStopstoClickedLayer();
          }
          document.getElementsByClassName("dropdown-list")[0].style.display = "none"; // hide the drop-down content if one element is clicked
      });

  });
}