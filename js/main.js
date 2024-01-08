const map = new LeafletMap();

/* ---------------------- GLOBAL VARIABLES / FUNCTIONS ---------------------- */
// https://sashamaps.net/docs/resources/20-colors/
// This is the array that stores a list of color
let colors = ['#e6194b',
              '#3cb44b', 
              '#4363d8', 
              '#f58231', 
              '#911eb4', 
              '#46f0f0', 
              '#f032e6', 
              '#bcf60c', 
              '#fabebe', 
              '#008080', 
              '#e6beff', 
              '#9a6324', 
              '#fffac8', 
              '#800000', 
              '#aaffc3', 
              '#808000', 
              '#ffd8b1', 
              '#000075'];

// this is the variable that stores the checkbox in the Options tab in HTML doc
let checkbox;

// This is the variable that stores the routes.json data
let routes;

// This is the variable that stores the layer of stops along each route
let routeStopLayer;

// This is the variable that stores the source data for the routeStopLayer
let routeStop;

// this is the variable that stores the layer of shapes for each route, with the 
let routeShapeLayer;

// This is the variable that stores the route_shape.geojson data
let routeShape;
let highlightLayer;
let currentHighlightedRouteId = null; // Global variable to store the currently highlighted route ID

function popup_attributes(feature, layer) {
  let html = '<table>';
  for (attrib in feature.properties) {
      html += '<tr><td>' + attrib + '</td><td>' + feature.properties[attrib] + '</td></tr>';
  }
  layer.bindPopup(html + '</table>');
}

const btn = document.getElementById("refresh_button");
btn.addEventListener("click", function () {
  resetHover();
  resetClick(currentHighlightedRouteId);
});


function getColorBasedOnTripsCount(shape_id, shape_ids) {
  for (let i = 0; i < shape_ids.length; i++) {
    if (shape_id === shape_ids[i]) {
      return colors[i];
    }
  }
}


/* -------- ROUTES JSON -------- */

async function routes_data() {
  const response = await fetch('./data/routes.json');
  routes = await response.json();
}
routes_data();


/* -------- ROUTES with STOPS LAYER -------- */
const t_routeStop = d3.json("data/routes_stops.geojson");
t_routeStop.then(data => {
  routeStop = data;

  // add features to map
  var geojsonMarkerOptions = {
    radius: 3.5,
    fillColor: "#ffffff",
    color: "#000000",
    weight: 2,
    opacity: 1,
    fillOpacity: 1
  };

  // Default layer to NULL, we will only add the stops to map only
  // when we click on the route shape layer
  routeStopLayer  = L.geoJSON(null, {
    pointToLayer: function (feature, geom) {
      return L.circleMarker(geom, geojsonMarkerOptions);
    },
    onEachFeature: (feature, layer) => {
      layer.bindTooltip(`<strong>Stop ID:</strong> ${feature.properties.stop_id}`)
    }
  }).addTo(map.map);
  
});


// This function will be triggered when routeShape layer is clicked
// as the result, the stops geometry will be displayed for that clicked route
function addStopstoClickedLayer() {
  const routeStopFeatures = routeStop.features.filter(feature =>
      feature.properties.route_id === currentHighlightedRouteId 
  );

  routeStopLayer.clearLayers();
  routeStopLayer.addData({ type: 'FeatureCollection', features: routeStopFeatures });
}

// Add an event listener to the checkbox element
checkbox = document.querySelector('.check');
checkbox.addEventListener('change', toggleRouteStopLayer);

// This function will allow user to show or hide the stops to their preferences
// when they click on the route shape layer
function toggleRouteStopLayer() {  
  let showStops = checkbox.checked;
  // Toggle the visibility of the routeStopLayer
  if (showStops) {
    addStopstoClickedLayer();
  } else {
    routeStopLayer.clearLayers();
  }
}


/* -------- ROUTES with SHAPES LAYER -------- */
const t_routeShape = d3.json("data/routes_shapes.geojson");
t_routeShape.then(data => {
  routeShape = data;

  // add features to map
  routeShapeLayer  = L.geoJSON(routeShape, {
      style: function(e) { return { weight: 2, opacity: 0.5, color:  "#a9a9a9" } }
  }).addTo(map.map);

  // Highlight layer, default as NULL
  // This will be shown upon hovering on the transparent layer
  highlightLayer = L.geoJSON(null, {
    style: function(e) { return { weight: 16, opacity: 0.5, color: 'yellow' } } // Adjust the highlighted style
  }).addTo(map.map);

  // Highlight layer for the clicked route
  // Only shown upon hovering on the legend
  highlightShape = L.geoJSON(null, {
    style: function(e) { return { weight: 16, opacity: 0.6, color: 'orange' } } // Adjust the highlighted style
  }).addTo(map.map);
  
  // add transparent layer to map, this will not be shown, but only serves as a layer that will be used for hover functionality
  routeShapeLayer_transparent  = L.geoJSON(routeShape, {
    style: function(e) { return { weight: 18, opacity: 0} }
  }).addTo(map.map);

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
    if (currentHighlightedRouteId != null && currentHighlightedRouteId != route_id) {
      resetClick(currentHighlightedRouteId);
      currentHighlightedRouteId = null;
    }
    highlightRouteClick(route_id);
    addStopstoClickedLayer();
  });
});



function bringShapetoFront(shape_id) {
  routeShapeLayer.eachLayer(function (layer) {
    if (layer.feature.properties.shape_id === shape_id) {
      layer.bringToFront();
   
      let decorator_shape = decoratorsMap.get(shape_id);

      // Check if the decorator is currently on the map
      const isDecoratorShown = map.map.hasLayer(decorator_shape.start) && map.map.hasLayer(decorator_shape.end);

      // If it's shown, remove it; otherwise, add it to the map
      if (isDecoratorShown) {
        map.map.removeLayer(decorator_shape.start);
        map.map.removeLayer(decorator_shape.end);
      } else {
        decoratorsMap.forEach(function(value, key) {
          if (key !== shape_id) {
            map.map.removeLayer(value.start);
            map.map.removeLayer(value.end);
          } else {
            decorator_shape.start.addTo(map.map);
            decorator_shape.end.addTo(map.map);
          }
        });
      }
      
    
  }});
  routeStopLayer.bringToFront();
}

function highlightShapeHover(shape_id) {
  highlightedFeatures = routeShape.features.filter(feature => feature.properties.shape_id === shape_id);
  highlightShape.clearLayers();
  highlightShape.addData({ type: 'FeatureCollection', features: highlightedFeatures });
  highlightShape.bringToBack();
}

let highlightedFeatures;
let route_matched;
function highlightRouteHover(route_id) {
  highlightedFeatures = routeShape.features.filter(feature => feature.properties.route_id === route_id);
  highlightLayer.clearLayers();
  highlightLayer.addData({ type: 'FeatureCollection', features: highlightedFeatures });
  highlightLayer.bringToBack();

  route_matched = routes.filter(item => item.route_id === route_id);

  document.getElementById('text-description').innerHTML = `<p> <strong>${highlightedFeatures[0].properties.agency_name}<strong></p>`;
  document.getElementById('text-description').innerHTML += `<span id="route-name">${highlightedFeatures[0].properties.route_short_name}</span> <label>${route_matched[0].route_long_name}</label>`;
  document.getElementById('text-description').innerHTML += `<p>This route takes <strong>${highlightedFeatures.length}</strong> different shapes.</p>`;
}

let decoratorsMap = new Map();
let startMarker = null;
let endMarker = null;
let markerHtmlStyles;
function highlightRouteClick(route_id) {
  // Reset the style of the previously highlighted route
  if (currentHighlightedRouteId) {
    resetClick(currentHighlightedRouteId);
  }

  let legendHTML = `<p style="margin-top:0"><strong>${highlightedFeatures[0].properties.agency_name}</strong></p>`;
  legendHTML += `<span id="route-name">${highlightedFeatures[0].properties.route_short_name}</span> <label>${route_matched[0].route_long_name}</label><br><br>`;
  legendHTML += `<span style="background-color: #FFFFFF;
                        width: 1rem;
                        height: 1rem;
                        display: inline-block;
                        border-radius: 50%;
                        border: 3px solid #000000;
                        margin-top: 5px;
                        vertical-align: text-bottom;
                        margin-right: 10px;"></span> <label style="display: inline-block;">Start</label>`;
  legendHTML += `<i class="fa-solid fa-location-dot"
                    style="
                        background: none;
                        color: #FFFFFF;
                        -webkit-text-stroke-width: 2.5px;
                        -webkit-text-stroke-color: #000000;
                        font-size: 1.25rem;
                        display: inline-block;
                        vertical-align: text-bottom;
                        margin-top: 5px;
                        margin-left: 15px;
                        margin-right: 10px;"></i> <label style="display: inline-block;">End</label>`;
  legendHTML += `<p style="font-size: small;"><em>Click on the shape to show/hide<br>the start and end point</em></p>`;
  legendHTML += `<ul style="margin-top:10px;">`;

  let shape_ids = [];
  let i = 0;
  highlightLayer.eachLayer(function (layer) {
    const feature = layer.feature;
    shape_ids.push(feature.properties.shape_id);
    legendHTML  += `<li onclick="bringShapetoFront(${feature.properties.shape_id})" onmouseover="highlightShapeHover(${feature.properties.shape_id})" onmouseout="resetHover()">
                      <span class="legend-color" style="background-color: ${colors[i]}" ></span>
                      <label><strong>${feature.properties.trips_count}</strong> trips made</label>
                    </li>`;
    i++;
  });
  legendHTML  += `</ul>`;

  document.getElementsByClassName('legend')[0].style.display = 'block';
  document.getElementsByClassName('legend')[0].innerHTML = legendHTML;

  routeShapeLayer.eachLayer(function (layer) {
    if (layer.feature.properties.route_id === route_id) {
      let shape_id = layer.feature.properties.shape_id;
      let color_style = getColorBasedOnTripsCount(shape_id, shape_ids);
      layer.setStyle({ weight: 5, opacity: 1, color: color_style }); // Adjust the style as needed
      layer.bringToFront();

      let coordinates = layer.feature.geometry.coordinates;
      let startLatLng = L.latLng(coordinates[0][1], coordinates[0][0])	;
      let endLatLng = L.latLng(coordinates[coordinates.length - 1][1], coordinates[coordinates.length - 1][0]);

      startMarker = L.circleMarker(startLatLng, {radius: 9, weight: 3, color: color_style, fillOpacity: 1, fillColor: 'white'});

      markerHtmlStyles = `
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
        html: `<i class="fa-solid fa-location-dot" style="${markerHtmlStyles}"></i>`
      })

      endMarker = L.marker(endLatLng, {icon: icon});

      // Store markers in the decoratorsMap with shape_id as key
      decoratorsMap.set(shape_id, { start: startMarker, end: endMarker });
    }
  });
  
  checkbox.checked = true;
  currentHighlightedRouteId = route_id; // Update the currently highlighted route ID
}


function resetHover() {
  document.getElementById('text-description').innerHTML = 
      `<p style="font-size:120%"> <strong>Select routes</strong></p>
      <p> Use your cursor to highlight routes and see their names here. Click for more details. </p>`;
  highlightLayer.clearLayers();
  highlightShape.clearLayers();
}


function resetClick(route_id) {  
  routeShapeLayer.eachLayer(function (layer) {
    if (layer.feature.properties.route_id === route_id) {
      routeShapeLayer.resetStyle(layer);

      let shape_id = layer.feature.properties.shape_id;
      let decorator_shape = decoratorsMap.get(shape_id);

      if (decorator_shape) {
        decorator_shape.start.remove();
        decorator_shape.end.remove();
      }
    }
  });

  routeStopLayer.clearLayers();
  currentHighlightedRouteId = null;

  document.getElementsByClassName('legend')[0].innerHTML = "";
  document.getElementsByClassName('legend')[0].style.display = 'none';

  checkbox.checked = false;

  // Clear the decoratorsMap
  decoratorsMap.clear();

}



// function highlightRoutesAtPoint(latlng) {
//   const circle = L.circle(latlng);
  
//   const intersectingFeatures = [];

//   routeShapeLayer_transparent.eachLayer(function (layer) {
//     const feature = layer.feature;
    
//     if (turf.booleanIntersects(feature.geometry, turf.buffer(turf.point(circle.toGeoJSON().geometry.coordinates), 0.08, {unit: 'kilometers'}))) {
//       intersectingFeatures.push(feature);
//     }
//   })

//   // console.log(intersectingFeatures);

//   highlightLayer.clearLayers();
//   highlightLayer.addData({ type: 'FeatureCollection', features: intersectingFeatures });

//   highlightLayer.bringToBack();

//   // Create a map to store distinct route short names for each agency
//   const agencyRouteMap = new Map();

//   // Populate the map with distinct route short names for each agency
//   intersectingFeatures.forEach(feature => {
//     const agencyName = feature.properties.agency_name;
//     const routeShortName = feature.properties.route_short_name;

//     if (!agencyRouteMap.has(agencyName)) {
//       agencyRouteMap.set(agencyName, new Set());
//     }

//     agencyRouteMap.get(agencyName).add(routeShortName);
//   });

//   // Display information
//   document.getElementById('text-description').innerHTML = '';

//   console.log(agencyRouteMap.keys)

//   agencyRouteMap.forEach((routeShortNames, agencyName) => {
//     document.getElementById('text-description').innerHTML += `<p><strong>${agencyName}</strong></p>`;
    
//     const numRouteShortNames = routeShortNames.size;

//     if (numRouteShortNames >= 5 ) {
//       document.getElementById('text-description').innerHTML += `<p>${numRouteShortNames} routes</p>`;
//     }
//     else {
//       document.getElementById('text-description').innerHTML += `<p>${[...routeShortNames].join('<br>')}</p>`;
//     }
//   });  

// }



function activate_tab(n) {
  // Get the total number of tabs
  var totalTabs = 3 /* Set the total number of tabs */;

  // Iterate through all tabs
  for (var i = 1; i <= totalTabs; i++) {
    // Check if the current tab is the one to keep (n), show it, otherwise hide it
    if (i == n) {
      document.getElementById("tab-" + i).style.display = "block";
      document.getElementsByClassName("tab-" + i)[0].className = `tab-${i} active`;
    } else {
      document.getElementById("tab-" + i).style.display = "none";
      document.getElementsByClassName("tab-" + i)[0].className = `tab-${i}`;
    }
  }
}


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

function clearResults() {
    // Assuming you have an element with the id "results" to display the matching items
    let resultsElement = document.getElementById('results');

    // Clear previous results
    resultsElement.innerHTML = '';
}

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
          addStopstoClickedLayer();
      });
  });
}