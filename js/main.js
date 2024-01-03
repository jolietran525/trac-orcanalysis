// let map = L.map('map', {zoomControl: false}).setView([47.60, -122.33], 10);


// /* ---------------------- MAP TILES ---------------------- */
// let tiles_lght = L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/{tileType}/{z}/{x}/{y}{r}.png', {
//     attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, &copy; <a href="https://cartodb.com/attributions">CARTO</a>',
//     subdomains: 'abcd',
//     tileType: 'light_all',
//     maxZoom: 20
//     }
// );

// let tiles_drk = L.tileLayer('https://{s}.basemaps.cartocdn.com/{tileType}/{z}/{x}/{y}{r}.png', {
//     attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, &copy; <a href="https://cartodb.com/attributions">CARTO</a>',
//     subdomains: 'abcd',
//     tileType: 'dark_all',
//     maxZoom: 19
//   });


// let tiles_hyd = L.tileLayer('https://{s}.tile.openstreetmap.se/hydda/{tileType}/{z}/{x}/{y}.png', {
//     attribution: 'Tiles courtesy of <a href="http://openstreetmap.se/" target="_blank">OpenStreetMap Sweden</a>',
//     tileType: 'full',
//     maxZoom: 20
// });

// // cartodb voyager - types: voyager, voyager_nolabels, voyager_labels_under
// let tiles_vgr = L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/{tileType}/{z}/{x}/{y}{r}.png', {
//     attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, &copy; <a href="https://cartodb.com/attributions">CARTO</a>',
//       subdomains: 'abcd',
//     tileType: 'voyager_labels_under',
//       maxZoom: 20
//   });


// // esri world imagery satellite tiles
// let tiles_ewi = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
//     attribution: 'Tiles &copy; Esri &mdash; Source: Esri, i-cubed, USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the GIS User Community'
//   });

// // esri world topo map tiles
// let tiles_ewt = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}', {
//       attribution: 'Tiles &copy; Esri &mdash; Esri, DeLorme, NAVTEQ, TomTom, Intermap, iPC, USGS, FAO, NPS, NRCAN, GeoBase, Kadaster NL, Ordnance Survey, Esri Japan, METI, Esri China (Hong Kong), and the GIS User Community'
//   });

// // default tile
// tiles_lght.addTo(map.map);

// let baseLayers = {
//     "Light (CartoDB)": tiles_lght,
//     "Dark (CartoDB)": tiles_drk,
//     "Color (Voyager)": tiles_vgr,
//     "Satellite (ESRI)":  tiles_ewi,
//     "Terrain (ESRI)": tiles_ewt
// };


// /* ---------------------- MAP CONTROL ---------------------- */
// L.control.zoom({position: 'topright'}).addTo(map.map);
// L.control.scale({maxWidth: 200, position: 'bottomright'}).addTo(map.map);

// let overlayLayers = {};
// let layerControl = L.control.layers(baseLayers,overlayLayers, {position: 'topright'}).addTo(map.map);

// let layerLegend = L.control({ position: 'bottomleft' });

// layerLegend.onAdd = function (map) {
//   let div = L.DomUtil.create('div', 'legend');
//   div.style.display = 'none';
//   return div;
// };

// // Add the legend to the map
// layerLegend.addTo(map.map);


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
    onEachFeature: popup_attributes
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
   
      // Retrieve the decorator from the map
      let decorator_shape = decoratorsMap.get(shape_id);
      
      // Bring the decorator to the front
      if (decorator_shape) {
        decorator_shape.start.bringToFront();
        decorator_shape.end.bringToFront();
      }
    }
  });
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
function highlightRouteClick(route_id) {
  // Reset the style of the previously highlighted route
  if (currentHighlightedRouteId) {
    resetClick(currentHighlightedRouteId);
  }

  let legendHTML = `<span id="route-name">${highlightedFeatures[0].properties.route_short_name}</span> <label>${route_matched[0].route_long_name}</label>`;
  legendHTML += `<ul style="margin-top:10px;">`;

  let shape_ids = [];
  let i = 0;
  highlightLayer.eachLayer(function (layer) {
    const feature = layer.feature;
    shape_ids.push(feature.properties.shape_id);
    legendHTML  += `<li onclick="bringShapetoFront(${feature.properties.shape_id})" onmouseover="highlightShapeHover(${feature.properties.shape_id})" onmouseout="resetHover()">
                      <span class="legend-color" style="background-color: ${colors[i]}" ></span>
                      <label><strong>${feature.properties.trips_count}</strong> trips made.</label>
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

      startMarker = L.circleMarker(startLatLng, {radius: 12, weight: 3, color: color_style, fillOpacity: 0.8, fillColor: 'white'}).addTo(map.map);
      endMarker = L.circleMarker(endLatLng, {radius: 12, weight: 3, color: color_style, fillOpacity: 0.8}).addTo(map.map);

      // const markerHtmlStyles = `
      //   color: ${color_style};
      //   width: 10px;
      //   height: 10px;
      //   display: block;
      //   left: 0;
      //   top: 0;
      //   position: relative;`

      // const icon = L.divIcon({
      //   iconAnchor: [0, 0],
      //   iconSize: [0,0],
      //   html: `<span style="${markerHtmlStyles}"><i class="fa-solid fa-map-pin" style:"height:100px; width:100px;"></i></span>`
      // })

      // endMarker = L.marker(endLatLng, {icon: icon}).addTo(map.map);

      startMarker.bringToFront();
      endMarker.bringToFront();
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
      let markers = decoratorsMap.get(shape_id);

      if (markers) {
        markers.start.remove();
        markers.end.remove();
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