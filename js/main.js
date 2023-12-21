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
const minZoomLevelToShowLayer = 14;

const t_routeStop = d3.json("data/routes_stops.geojson");
t_routeStop.then(data => {
  routeStop = data;
  // add features to map

  var geojsonMarkerOptions = {
    radius: 5,
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
  });
  
  // Add an event listener for the zoomend event
  map.on('movestart zoomlevelschange', function () {
    checkZoomAndBoundingBox();
  });

  map.on('moveend zoomlevelschange', function () {
    checkZoomAndBoundingBox();
  });

  // Initially check whether to show the layer based on zoom level
  checkZoomAndBoundingBox();
  
});


function checkZoomAndBoundingBox() {
  const currentZoomLevel = map.getZoom();
  const currentBoundingBox = map.getBounds();


  if (currentZoomLevel >= minZoomLevelToShowLayer) {
    const routeStopFeatures = routeStop.features.filter(feature =>
      turf.booleanIntersects(feature.geometry, turf.polygon([
        [
          [currentBoundingBox.getWest(), currentBoundingBox.getSouth()],
          [currentBoundingBox.getWest(), currentBoundingBox.getNorth()],
          [currentBoundingBox.getEast(), currentBoundingBox.getNorth()],
          [currentBoundingBox.getEast(), currentBoundingBox.getSouth()],
          [currentBoundingBox.getWest(), currentBoundingBox.getSouth()],
        ]
      ])));
  
    routeStopLayer.clearLayers();
    routeStopLayer.addData({ type: 'FeatureCollection', features: routeStopFeatures });
  }

  else {
    // If the layer is not already added, add it to the map
    if (!map.hasLayer(routeStopLayer)) {
      routeStopLayer.addTo(map);
    }
  }
}


/* -------- ROUTES with SHAPES LAYER -------- */
let routeShapeLayer;
let routeShape;
let highlightLayer;

const t_routeShape = d3.json("data/routes_shapes.geojson");
t_routeShape.then(data => {
  routeShape = data;

  // Highlight layer
  highlightLayer = L.geoJSON(null, {
    style: function(e) { return { weight: 16, opacity: 0.5, color: 'yellow' } } // Adjust the highlighted style
  }).addTo(map);
  
  // add features to map
  routeShapeLayer_transparent  = L.geoJSON(routeShape, {
    style: function(e) { return { weight: 18, opacity: 0} }
  }).addTo(map);

  // add features to map
  routeShapeLayer  = L.geoJSON(routeShape, {
      style: function(e) { return { weight: 2, opacity: 0.7, color:  "#42a5d6" } }
  }).addTo(map);

  // Add hover events
  routeShapeLayer_transparent.on('mouseover', function (e) {
    // highlightRoutesAtPoint(e.latlng);
    highlightRoute(e.layer.feature.properties.route_id);
  });

  routeShapeLayer_transparent.on('mouseout', function () {
    resetHighlight();
    document.getElementById('text-description').innerHTML = 
      `<p style="font-size:120%"> <strong>Select routes</strong></p>
      <p> Use your cursor to highlight routes and see their names here. Click for more details. </p>`;
  });
});

function highlightRoute(route_id) {
  const highlightedFeatures = routeShape.features.filter(feature => feature.properties.route_id === route_id);
  highlightLayer.clearLayers();
  highlightLayer.addData({ type: 'FeatureCollection', features: highlightedFeatures });
  highlightLayer.bringToBack();

  document.getElementById('text-description').innerHTML = `<p> <strong>${highlightedFeatures[0].properties.agency_name}<strong></p>`;
  document.getElementById('text-description').innerHTML += `<p>${highlightedFeatures[0].properties.route_short_name}</p>`;
  document.getElementById('text-description').innerHTML += `<p>This route takes <strong>${highlightedFeatures.length}</strong> different shapes.</p>`;
  
  // console.log(highlightedFeatures.length);

  highlightLayer.eachLayer(function (layer) {
    const feature = layer.feature;
    
    document.getElementById('text-description').innerHTML += `<p><strong>${feature.properties.trips_count}</strong> trips count.</p>`;
  })
  
}

function resetHighlight() {
  highlightLayer.clearLayers();
}


function highlightRoutesAtPoint(latlng) {
  const circle = L.circle(latlng);
  
  const intersectingFeatures = [];

  routeShapeLayer_transparent.eachLayer(function (layer) {
    const feature = layer.feature;
    
    if (turf.booleanIntersects(feature.geometry, turf.buffer(turf.point(circle.toGeoJSON().geometry.coordinates), 0.08, {unit: 'kilometers'}))) {
      intersectingFeatures.push(feature);
    }
  })

  // console.log(intersectingFeatures);

  highlightLayer.clearLayers();
  highlightLayer.addData({ type: 'FeatureCollection', features: intersectingFeatures });

  highlightLayer.bringToBack();

  // Create a map to store distinct route short names for each agency
  const agencyRouteMap = new Map();

  // Populate the map with distinct route short names for each agency
  intersectingFeatures.forEach(feature => {
    const agencyName = feature.properties.agency_name;
    const routeShortName = feature.properties.route_short_name;

    if (!agencyRouteMap.has(agencyName)) {
      agencyRouteMap.set(agencyName, new Set());
    }

    agencyRouteMap.get(agencyName).add(routeShortName);
  });

  // Display information
  document.getElementById('text-description').innerHTML = '';

  console.log(agencyRouteMap.keys)

  agencyRouteMap.forEach((routeShortNames, agencyName) => {
    document.getElementById('text-description').innerHTML += `<p><strong>${agencyName}</strong></p>`;
    
    const numRouteShortNames = routeShortNames.size;

    if (numRouteShortNames >= 5 ) {
      document.getElementById('text-description').innerHTML += `<p>${numRouteShortNames} routes</p>`;
    }
    else {
      document.getElementById('text-description').innerHTML += `<p>${[...routeShortNames].join('<br>')}</p>`;
    }
  });  

}



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
