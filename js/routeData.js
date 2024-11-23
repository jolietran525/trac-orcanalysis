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

// Global variable that stores the routes.json data
let routes, routeStop, routeShapeLayer_base, routeShape, highlightRoute;

// Global variable that stores the currently clicked-on route_id
let currentHighlightedRouteId = null;


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


/* -------- ROUTES with SHAPES LAYER -------- */
// Fetch shapes data for each route (routes_shapes) using d3.json
const t_routeShape = d3.json("data/routes_shapes.geojson");
t_routeShape.then(data => {
  routeShape = data;

  // Base layer, shown in map as grey
  routeShapeLayer_base  = L.geoJSON(routeShape, {
      style: function(e) { return { weight: 2, opacity: 0.5, color:  "#a9a9a9" } }
  }).addTo(Lmap.map);
  
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

 
  let shape_ids = [];
  let i = 0;

  // Iterate through layers to construct legend items
  highlightRoute.eachLayer(function (layer) {
    const feature = layer.feature;
    shape_ids.push(feature.properties.shape_id);
    legendHTML  += `<li onclick="bringShapetoFront(${feature.properties.shape_id})"
                        onmouseover="highlightShapeHover(${feature.properties.shape_id})"
                        onmouseout="resetHover()">
                        <div class="grid-container">
                            <span class="legend-color" style="background-color: ${colors[i]}" ></span>
                            <label><strong>${feature.properties.trips_count}</strong> ${feature.properties.trips_count > 1 ? 'trips' : 'trip'}</label>
                        </div>
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
          -webkit-text-stroke-color: ${color_style};
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
  stopLayer.bringToFront();
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

  // stopLayer.clearLayers();
  currentHighlightedRouteId = null;

  // Clear the legend display
  document.querySelector('.legend').innerHTML = "";
  document.querySelector('.legend').style.display = 'none';

  // Clear the startEndMarkers
  startEndMarkers.clear();
}

