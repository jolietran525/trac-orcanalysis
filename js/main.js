let map = L.map('map', {zoomControl: false}).setView([47.60, -122.33], 10);


/* ---------------------- MAP TILES ---------------------- */
let tiles_lght = L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/{tileType}/{z}/{x}/{y}{r}.png', {
    attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, &copy; <a href="https://cartodb.com/attributions">CARTO</a>',
    subdomains: 'abcd',
    tileType: 'light_all',
    maxZoom: 20
    }
);

let tiles_drk = L.tileLayer('https://{s}.basemaps.cartocdn.com/{tileType}/{z}/{x}/{y}{r}.png', {
    attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, &copy; <a href="https://cartodb.com/attributions">CARTO</a>',
    subdomains: 'abcd',
    tileType: 'dark_all',
    maxZoom: 19
  });


let tiles_hyd = L.tileLayer('https://{s}.tile.openstreetmap.se/hydda/{tileType}/{z}/{x}/{y}.png', {
    attribution: 'Tiles courtesy of <a href="http://openstreetmap.se/" target="_blank">OpenStreetMap Sweden</a>',
    tileType: 'full',
    maxZoom: 20
});

// cartodb voyager - types: voyager, voyager_nolabels, voyager_labels_under
let tiles_vgr = L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/{tileType}/{z}/{x}/{y}{r}.png', {
    attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, &copy; <a href="https://cartodb.com/attributions">CARTO</a>',
      subdomains: 'abcd',
    tileType: 'voyager_labels_under',
      maxZoom: 20
  });


// esri world imagery satellite tiles
let tiles_ewi = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
    attribution: 'Tiles &copy; Esri &mdash; Source: Esri, i-cubed, USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the GIS User Community'
  });

// esri world topo map tiles
let tiles_ewt = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}', {
      attribution: 'Tiles &copy; Esri &mdash; Esri, DeLorme, NAVTEQ, TomTom, Intermap, iPC, USGS, FAO, NPS, NRCAN, GeoBase, Kadaster NL, Ordnance Survey, Esri Japan, METI, Esri China (Hong Kong), and the GIS User Community'
  });

// default tile
tiles_lght.addTo(map);

let baseLayers = {
    "Light (CartoDB)": tiles_lght,
    "Dark (CartoDB)": tiles_drk,
    "Color (Voyager)": tiles_vgr,
    "Satellite (ESRI)":  tiles_ewi,
    "Terrain (ESRI)": tiles_ewt
};


/* ---------------------- MAP CONTROL ---------------------- */
L.control.zoom({position: 'topright'}).addTo(map);
L.control.scale({maxWidth: 200, position: 'bottomright'}).addTo(map);

let overlayLayers = {};
let layerControl = L.control.layers(baseLayers,overlayLayers, {position: 'topright'}).addTo(map);

let scoreFilterControl = L.control({ position: 'bottomleft' });

let layerLegend = L.control({ position: 'bottomleft' });


/* ---------------------- MAP LAYERS ---------------------- */
function popup_attributes(feature, layer) {
  let html = '<table>';
  for (attrib in feature.properties) {
      html += '<tr><td>' + attrib + '</td><td>' + feature.properties[attrib] + '</td></tr>';
  }
  layer.bindPopup(html + '</table>');
}

/* -------- ROUTES with STOPS LAYER -------- */

let routeStopLayer;
let routeStop;

const t_routeStop = d3.json("data/routes_stops.geojson");
t_routeStop.then(data => {
  routeStop = data;
  // add features to map

  var geojsonMarkerOptions = {
    radius: 3.5,
    fillColor: "#ff7800",
    color: "#000",
    weight: 1,
    opacity: 1,
    fillOpacity: 0.8
  };

  routeStopLayer  = L.geoJSON(null, {
    pointToLayer: function (feature, geom) {
      return L.circleMarker(geom, geojsonMarkerOptions);
    },
      onEachFeature: popup_attributes
  }).addTo(map);
  
});


function addStopstoClickedLayer() {
  const routeStopFeatures = routeStop.features.filter(feature =>
      feature.properties.route_id === currentHighlightedRouteId 
  );
  
  routeStopLayer.clearLayers();
  routeStopLayer.addData({ type: 'FeatureCollection', features: routeStopFeatures });
}


/* -------- ROUTES with SHAPES LAYER -------- */
let routeShapeLayer;
let routeShape;
let highlightLayer;
let currentHighlightedRouteId; // Global variable to store the currently highlighted route ID

const t_routeShape = d3.json("data/routes_shapes.geojson");
t_routeShape.then(data => {
  routeShape = data;

  // Highlight layer, default as NULL
  highlightLayer = L.geoJSON(null, {
    style: function(e) { return { weight: 16, opacity: 0.4, color: 'yellow' } } // Adjust the highlighted style
  }).addTo(map);
  
  // add transparent layer to map
  routeShapeLayer_transparent  = L.geoJSON(routeShape, {
    style: function(e) { return { weight: 18, opacity: 0} }
  }).addTo(map);

  // add features to map
  routeShapeLayer  = L.geoJSON(routeShape, {
      style: function(e) { return { weight: 2, opacity: 0.5, color:  "#42a5d6" } }
  }).addTo(map);

  // Add hover events
  routeShapeLayer_transparent.on('mouseover', function (e) {
    const route_id = e.layer.feature.properties.route_id;
    highlightRouteHover(route_id);
  });

  routeShapeLayer_transparent.on('click', function (e) {
    const route_id = e.layer.feature.properties.route_id;
    if (currentHighlightedRouteId && currentHighlightedRouteId != route_id) {
      resetClick(currentHighlightedRouteId);
      currentHighlightedRouteId = null;
    }
    highlightRouteClick(route_id);
    addStopstoClickedLayer();
  });

  routeShapeLayer_transparent.on('mouseout', function () {
    resetHover();
    
    document.getElementById('text-description').innerHTML = 
      `<p style="font-size:120%"> <strong>Select routes</strong></p>
      <p> Use your cursor to highlight routes and see their names here. Click for more details. </p>`;
  });

});

function getColorBasedOnTripsCount(shape_id, shape_ids) {
  let colors = ['#00202e',  '#003f5c',  '#2c4875',  '#8a508f',  '#bc5090',  '#ff6361',  '#ff8531',  '#ffa600',  '#ffd380'];
  for (let i = 0; i < shape_ids.length; i++) {
    if (shape_id === shape_ids[i]) {
      return colors[i];
    }
  }
}

let highlightedFeatures;
function highlightRouteHover(route_id) {
  highlightedFeatures = routeShape.features.filter(feature => feature.properties.route_id === route_id);
  highlightLayer.clearLayers();
  highlightLayer.addData({ type: 'FeatureCollection', features: highlightedFeatures });
  highlightLayer.bringToBack();

  document.getElementById('text-description').innerHTML = `<p> <strong>${highlightedFeatures[0].properties.agency_name}<strong></p>`;
  document.getElementById('text-description').innerHTML += `<p>${highlightedFeatures[0].properties.route_short_name}</p>`;
  document.getElementById('text-description').innerHTML += `<p>This route takes <strong>${highlightedFeatures.length}</strong> different shapes.</p>`;
}


function highlightRouteClick(route_id) {
  // Reset the style of the previously highlighted route
  if (currentHighlightedRouteId && currentHighlightedRouteId !== route_id) {
    resetClick(currentHighlightedRouteId);
  }

  document.getElementById('text-description').innerHTML = `<p> <strong>${highlightedFeatures[0].properties.agency_name}<strong></p>`;
  document.getElementById('text-description').innerHTML += `<p>${highlightedFeatures[0].properties.route_short_name}</p>`;
  document.getElementById('text-description').innerHTML += `<p>This route takes <strong>${highlightedFeatures.length}</strong> different shapes.</p>`;

  let shape_ids = [];
  highlightLayer.eachLayer(function (layer) {
    const feature = layer.feature;
    shape_ids.push(feature.properties.shape_id);
    document.getElementById('text-description').innerHTML += `<p><strong>${feature.properties.trips_count}</strong> trips count.</p>`;
  });

  routeShapeLayer.eachLayer(function (layer) {
    if (layer.feature.properties.route_id === route_id) {
      let shape_id = layer.feature.properties.shape_id;
      layer.setStyle({ weight: 5, opacity: 0.5, color: getColorBasedOnTripsCount(shape_id, shape_ids) }); // Adjust the style as needed
      layer.bringToFront();
      currentHighlightedRouteId = route_id; // Update the currently highlighted route ID
    }
  });
}

function resetHover() {
  highlightLayer.clearLayers();
}

function resetClick(route_id) {
  routeShapeLayer.eachLayer(function (layer) {
    if (layer.feature.properties.route_id === route_id) {
      routeShapeLayer.resetStyle(layer);
    }
  });
  routeStopLayer.clearLayers();
}

const btn = document.getElementById("refresh_button");

btn.addEventListener("click", function () {
  resetHover();
  resetClick(currentHighlightedRouteId);
});


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
    } else {
      document.getElementById("tab-" + i).style.display = "none";
    }
  }
}
