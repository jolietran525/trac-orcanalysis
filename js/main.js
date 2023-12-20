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
L.control.zoom({position: 'topleft'}).addTo(map);
L.control.scale({maxWidth: 200, position: 'bottomright'}).addTo(map);

let overlayLayers = {};
let layerControl = L.control.layers(baseLayers,overlayLayers, {position: 'topleft'}).addTo(map);

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

/* -------- ROUTES with SHAPES LAYER -------- */
let routeShapeLayer;
let routeShape;
let highlightLayer;

const t_routeShape = d3.json("data/routes_shapes.geojson");
t_routeShape.then(data => {
  routeShape = data;
  // add features to map
  routeShapeLayer  = L.geoJSON(routeShape, {
      style: function(e) { return { weight: 2, opacity: 0.7, color:  "#5381ed" } },
      onEachFeature: popup_attributes
  });
  
  routeShapeLayer_transparent  = L.geoJSON(routeShape, {
    style: function(e) { return { weight: 20, opacity: 0, color:  "#5381ed" } },
  }).addTo(map);

  // Highlight layer
  highlightLayer = L.geoJSON(null, {
    style: function(e) { return { weight: 10, opacity: 0.4, color: 'yellow' } } // Adjust the highlighted style
  });

  // Add original layer to map
  routeShapeLayer.addTo(map);

  // Add highlight layer to map (but initially empty)
  highlightLayer.addTo(map);

  // Add hover events
  routeShapeLayer_transparent.on('mouseover', function (e) {
    // highlightRoutesAtPoint(e.latlng);
    highlightRoute(e.layer.feature.properties.route_id);
  });

  routeShapeLayer_transparent.on('mouseout', function () {
    resetHighlight();
  });
});

function highlightRoute(route_id) {
  const highlightedFeatures = routeShape.features.filter(feature => feature.properties.route_id === route_id);
  highlightLayer.clearLayers();
  highlightLayer.addData({ type: 'FeatureCollection', features: highlightedFeatures });
}

function resetHighlight() {
  highlightLayer.clearLayers();
}

function highlightRoutesAtPoint(latlng) {
  const circle = L.circle(latlng);
  
  const intersectingFeatures = [];

  routeShapeLayer_transparent.eachLayer(function (layer) {
    const feature = layer.feature;
    // console.log(turf.buffer(feature.geometry, 30, {units: 'meters'}));
    if (turf.booleanIntersects(feature.geometry, turf.buffer(turf.point(circle.toGeoJSON().geometry.coordinates), 5, {unit: 'meters'}))) {
      intersectingFeatures.push(feature);
    }
  });

  // highlightRoute(intersectingFeatures.route_id);

  highlightLayer.clearLayers();
  highlightLayer.addData({ type: 'FeatureCollection', features: intersectingFeatures });
}


let routeStopLayer;
let routeStop;
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

  routeStopLayer  = L.geoJSON(routeStop, {
    pointToLayer: function (feature, geom) {
      return L.circleMarker(geom, geojsonMarkerOptions);
    },
      onEachFeature: popup_attributes
  });
  
  // routeStopLayer.addTo(map);
});