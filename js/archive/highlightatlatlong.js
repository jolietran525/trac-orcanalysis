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