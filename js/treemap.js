// Load map from the leaflet_map.js class
const Lmap = new LeafletMap();

// L.Control.Button = L.Control.extend({
//   options: {
//     position: 'topright',
//   },
//   onAdd: function (map) {
//     var container = L.DomUtil.create('div', 'leaflet-bar leaflet-control buttons');
//     var button = L.DomUtil.create('a', 'leaflet-control-button', container);
//     L.DomEvent.disableClickPropagation(button);
//     button.id = 'refresh_button';
//     button.innerHTML = '<i class="fa-solid fa-rotate-right"></i>';

//     return container;
//   },
//   onRemove: function (map) {},
// });

// var control = new L.Control.Button();
// control.addTo(Lmap.map);

// let csvData;
// const stop_xfer = d3.csv("./data/20241008_orca_xfer_stop_summary_with_coords.csv")

// stop_xfer.then(data => {
//   csvData = data; // Store CSV data globally for later access

//   // Create a Set to track unique stops based on stop_code, stop_lng, and stop_lat
//   const uniqueStops = new Set();

//   // Step 1: Convert CSV data into GeoJSON format and filter out duplicates
//   const stopsGeoJson = {
//     type: "FeatureCollection",
//     features: data
//       .filter(d => {
//         // Create a unique identifier for each stop based on stop_code, stop_lng, and stop_lat
//         const uniqueKey = `${d.stop_code}_${d.stop_lng}_${d.stop_lat}`;
        
//         // Check if this combination is already in the Set
//         if (!uniqueStops.has(uniqueKey)) {
//           uniqueStops.add(uniqueKey); // Add to Set if not present
//           return true; // Keep this stop
//         }
//         return false; // Discard duplicate
//       })
//       .map(d => {
//         return {
//           type: "Feature",
//           properties: {
//             stop_code: d.stop_code
//           }, // Add the created properties object
//           geometry: {
//             type: "Point",
//             coordinates: [+d.stop_lng, +d.stop_lat] // Use 'stop_lat' and 'stop_lng' columns for coordinates
//           }
//         };
//       })
//   };

//   // Step 2: Define marker options (similar to what you used with GeoJSON)
//   const geojsonMarkerOptions = {
//     radius: 3.5,
//     fillColor: "#ffffff",
//     color: "#000000",
//     weight: 2,
//     opacity: 1,
//     fillOpacity: 1
//   };

//   // Step 3: Add the GeoJSON layer to the map with custom pointToLayer and onEachFeature functions
//   const routeStopLayer = L.geoJSON(stopsGeoJson, {
//     pointToLayer: function(feature, latlng) {
//       // Create a circle marker at each lat/lon
//       return L.circleMarker(latlng, geojsonMarkerOptions);
//     },
//     onEachFeature: function(feature, layer) {
//       // Bind a tooltip to each marker showing one or more properties (e.g., stop_id)
//       const popupContent = Object.keys(feature.properties).map(key => 
//         `<strong>${key}:</strong> ${feature.properties[key]}`
//       ).join("<br>");
      
//       layer.bindTooltip(popupContent);

//       // Step 2: Add click event to each layer
//       layer.on("click", () => {
//         const stopCode = feature.properties.stop_code; // Get stop_code from the feature
//         createTreemapForStop(stopCode); // Call the treemap function with the clicked stop_code
//       });
//     }
//   }).addTo(Lmap.map); // Assuming Lmap.map is your Leaflet map
// });

let csvData;
const stop_xfer = d3.csv("./data/20241008_orca_xfer_stop_summary_with_coords.csv");

// Store the layer globally for easy reference during updates
let routeStopLayer;

stop_xfer.then(data => {
  csvData = data; // Store CSV data globally for later access
  displayStopsOnMap(csvData); // Initial display of all stops on the map
});

/**
 * Filter stops based on a given route and display them on the map.
 * @param {string} routeFilter - The route to filter by.
 */
function filterStopsOnMap(routeFilter) {
  // Filter the CSV data based on the input route
  const filteredData = csvData.filter(d => d.from_route && d.from_route.includes(routeFilter));
  displayStopsOnMap(filteredData);
}

/**
 * Display the filtered stops on the map.
 * @param {Array} data - Array of filtered stop data to display on the map.
 */
function displayStopsOnMap(data) {
  // Remove the previous layer from the map if it exists
  if (routeStopLayer) {
    Lmap.map.removeLayer(routeStopLayer);
  }

  // Create a Set to track unique stops based on stop_code, stop_lng, and stop_lat
  const uniqueStops = new Set();

  // Convert filtered CSV data into GeoJSON format, filtering out duplicates
  const stopsGeoJson = {
    type: "FeatureCollection",
    features: data
      .filter(d => {
        const uniqueKey = `${d.stop_code}_${d.stop_lng}_${d.stop_lat}`;
        if (!uniqueStops.has(uniqueKey)) {
          uniqueStops.add(uniqueKey); // Add to Set if not present
          return true; // Keep this stop
        }
        return false; // Discard duplicate
      })
      .map(d => ({
        type: "Feature",
        properties: {
          stop_code: d.stop_code,
          from_route: d.from_route // Add any other properties you want to display
        },
        geometry: {
          type: "Point",
          coordinates: [+d.stop_lng, +d.stop_lat] // Convert to numbers for coordinates
        }
      }))
  };

  // Define marker options
  const geojsonMarkerOptions = {
    radius: 3.5,
    fillColor: "#ffffff",
    color: "#000000",
    weight: 2,
    opacity: 1,
    fillOpacity: 1
  };

  // Add the GeoJSON layer to the map
  routeStopLayer = L.geoJSON(stopsGeoJson, {
    pointToLayer: (feature, latlng) => L.circleMarker(latlng, geojsonMarkerOptions),
    onEachFeature: (feature, layer) => {
      const popupContent = Object.keys(feature.properties)
        .map(key => `<strong>${key}:</strong> ${feature.properties[key]}`)
        .join("<br>");
      layer.bindTooltip(popupContent);

      // Add click event to each stop marker
      layer.on("click", () => {
        const stopCode = feature.properties.stop_code;
        createTreemapForStop(stopCode);
      });
    }
  }).addTo(Lmap.map);
}

let filteredData;
let hierarchyData;

// Add the ResizeObserver to detect changes in the size of the #treemap div
const resizeObserver = new ResizeObserver(entries => {
  for (let entry of entries) {
    // Get the new dimensions of #treemap
    const width = entry.contentRect.width;
    const height = entry.contentRect.height;
    
    // Recreate the treemap with the new dimensions
    if (hierarchyData) {  // Only recreate if hierarchyData is available
      createTreemap(hierarchyData);
    }
  }
});

// Start observing the #treemap div
resizeObserver.observe(document.querySelector('#treemap'));

function createTreemapForStop(stopCode) {
  // Step 3: Filter the CSV data
  filteredData = csvData.filter(d => d.stop_code === stopCode);

  // Group by to_agency and to_route, then sum passenger_count
  const nestedData = d3.group(filteredData, d => d.to_agency, d => d.to_route);

  // Convert nested data into hierarchical format for treemap
  hierarchyData = {
    name: "root",  // Root node
    children: Array.from(nestedData, ([agency, routes]) => ({
      name: agency,  // to_agency as the parent node
      children: Array.from(routes, ([route, values]) => ({
        name: route,  // to_route as the child node
        value: d3.sum(values, d => +d.passenger_count)  // Sum of passenger_count for each route
      }))
    }))
  };
  // Step 4: Call the createTreemap function
  createTreemap(hierarchyData);
  // Call the function initially and whenever the treemap data changes
  adjustLayoutBasedOnTreemap();
}


function createTreemap(hierarchyData) {
  const container = d3.select("#treemap").node();
  const width = container.clientWidth;
  const height = container.clientHeight;

  // const color = d3.scaleOrdinal(d3.schemeCategory10);  // Color scale for nodes
  const color = d3.scaleOrdinal(hierarchyData.children.map(d => d.name), d3.schemeTableau10);

  const root = d3.treemap()
    .tile(d3.treemapSquarify)
    .size([width, height])
    .padding(1)
    .round(true)
  (d3.hierarchy(hierarchyData)
      .sum(d => d.value)
      .sort((a, b) => b.value - a.value));

  // Select the div to append the treemap SVG
  d3.select("#treemap").selectAll("svg").remove(); // Clear any existing treemap
  const svg = d3.select("#treemap")
    .append("svg")
    .attr("viewBox", [0, 0, width, height])
    .attr("width", width)
    .attr("height", height)
    .attr("style", "max-width: 100%; height: auto; font: 12px sans-serif;");

  // Create nodes for each element in the hierarchy
  const nodes = svg.selectAll("g")
    .data(root.leaves())  // Get only the leaf nodes (the `to_route` routes)
    .join("g")
      .attr("transform", d => `translate(${d.x0},${d.y0})`);

  // Helper function to create unique IDs
  function uniqueId(prefix) {
    return `${prefix}-${Math.floor(Math.random() * 100000)}`;
  }
  // Define format for the value
  const format = d3.format(",d");  // Formats as integer with commas

  nodes.append("title")
  .text(d => {
    const ancestors = d.ancestors().reverse();
    const agency = ancestors[1] ? ancestors[1].data.name : "";  // Agency level
    const route = ancestors[2] ? ancestors[2].data.name : "";   // Route level
    const count = format(d.value);  // Value for the current node

    // Construct the tooltip based on levels
    let tooltipText = "";
    if (agency) {
      tooltipText += `Agency: ${agency}\n`;
    }
    if (route) {
      tooltipText += `Route: ${route}\n`;
    }
    tooltipText += `Count: ${count}`;
    
    return tooltipText;
  });

  // Add rectangles for each node
  nodes.append("rect")
    .attr("id", d => {
      d.leafUid = uniqueId("leaf"); // Use a helper function to generate unique IDs
      return d.leafUid;
    })
    .attr("fill", d => { while (d.depth > 1) d = d.parent; return color(d.data.name); })
    .attr("fill-opacity", 0.6)
    .attr("width", d => d.x1 - d.x0)
    .attr("height", d => d.y1 - d.y0);

  // Add a unique clipPath to each node
  nodes.append("clipPath")
      .attr("id", d => {
        d.clipUid = uniqueId("clip"); // Use a helper function to generate unique IDs
        return d.clipUid;
      })
    .append("use")
      .attr("xlink:href", d => d.leafUid.href);  // Reference the unique clip path
  
  nodes.append("text")
      .attr("clip-path", d => d.clipUid)
    .selectAll("tspan")
    .data(d => d.data.name.split(/(?=[A-Z][a-z])|\s+/g).concat(format(d.value)))
    .join("tspan")
      .attr("x", 3)
      .attr("y", (d, i, nodes) => `${(i === nodes.length - 1) * 0.3 + 1.1 + i * 0.9}em`)
      .attr("font-weight", (d, i, nodes) => i === nodes.length - 1 ? "normal" : "bold")  // Bold the first line (Route name)
      .attr("fill-opacity", (d, i, nodes) => i === nodes.length - 1 ? 0.9 : null)
      .text(d => d);
}


var treemap = document.querySelector('#treemap');
var map = document.querySelector('#map');
var mapArea = document.querySelector('#map-area');
var startX, startWidth, totalWidth;
let isResized = false; // Track if #treemap has been resized

function adjustLayoutBasedOnTreemap() {
  const svg = treemap.querySelector('svg');

  if (!svg) {
    // No SVG inside #treemap, hide #treemap and expand #map
    treemap.style.flex = '0';
    treemap.style.flexBasis = '0';
    map.style.flex = '1';
    map.style.flexBasis = '100%'; // Expand map to full width
  } else {
    // SVG exists
    if (!isResized) {
      // Only set flex properties to 50% on initial load or if not resized
      treemap.style.flex = '1';
      treemap.style.flexBasis = '50%';
      map.style.flex = '1';
      map.style.flexBasis = '50%'; // Split 50-50 by default
      // Trigger Leaflet to update its size
      Lmap.map.invalidateSize();
      Lmap.map.setView(Lmap.map.getCenter());
    }
  }

}

// Call the function initially and whenever the treemap data changes
adjustLayoutBasedOnTreemap();


// Resize handler
function updateLayoutOnResize() {
  // Update flex-basis values based on current layout
  const totalWidth = mapArea.getBoundingClientRect().width; // Get the total width of #map-area
  const treemapWidth = parseInt(window.getComputedStyle(treemap).flexBasis) || 0;
  const mapWidth = totalWidth - treemapWidth - 5; // 5px gap

  // Set the new widths
  if (treemapWidth > 0) {
    treemap.style.flexBasis = `${treemapWidth}px`;
    map.style.flexBasis = `${mapWidth}px`;
  }
}

// Add resize event listener
window.addEventListener('resize', () => {
  updateLayoutOnResize();
  // Call the function to adjust layout based on treemap data
  adjustLayoutBasedOnTreemap();
});


// Add a mousemove event to adjust the cursor only when near the edge
treemap.addEventListener('mousemove', function(e) {
    const rect = treemap.getBoundingClientRect();
    const offsetX = e.clientX - rect.left;

    // Check if the mouse is within 10px of the left edge
    if (offsetX < 10) {
        treemap.style.cursor = 'ew-resize'; // Show resize cursor
    } else {
        treemap.style.cursor = 'default'; // Reset to default cursor
    }
});

// Add event listener for mousedown to initiate the resize
treemap.addEventListener('mousedown', function(e) {
    const rect = treemap.getBoundingClientRect();
    const offsetX = e.clientX - rect.left;

    // Only start resizing if the click is within 10px of the left edge
    if (offsetX < 10) {
        startX = e.clientX;
        startWidth = parseInt(document.defaultView.getComputedStyle(treemap).width, 10);
        totalWidth = mapArea.getBoundingClientRect().width;  // Get the total width of #map-area
        document.documentElement.addEventListener('mousemove', doDrag, false);
        document.documentElement.addEventListener('mouseup', stopDrag, false);
    }
}, false);

function doDrag(e) {
    let deltaX = startX - e.clientX; // Reverse direction of dragging

    let newTreemapWidth = startWidth + deltaX;

    // Ensure the new width doesn't exceed container limits
    if (newTreemapWidth < 50) newTreemapWidth = 50;
    if (newTreemapWidth > totalWidth - 50) newTreemapWidth = totalWidth - 50;

    let newMapWidth = totalWidth - newTreemapWidth - 5;

    // Apply the new widths as flex-basis values
    treemap.style.flex = `0 0 ${newTreemapWidth}px`;
    map.style.flex = `0 0 ${newMapWidth}px`;
}

function stopDrag(e) {
  isResized = true; 
  // Trigger Leaflet to update its size
  document.documentElement.removeEventListener('mousemove', doDrag, false);
  document.documentElement.removeEventListener('mouseup', stopDrag, false);
  Lmap.map.invalidateSize();
  Lmap.map.setView(Lmap.map.getCenter());  
}





/* -------- ROUTES with SHAPES LAYER -------- */
// Fetch shapes data for each route (routes_shapes) using d3.json
// const t_routeShape = d3.json("data/routes_shapes.geojson");
// t_routeShape.then(data => {
//   routeShape = data;

//   // Base layer, shown in map as grey
//   routeShapeLayer_base  = L.geoJSON(routeShape, {
//       style: function(e) { return { weight: 2, opacity: 0.5, color:  "#a9a9a9" } }
//   }).addTo(Lmap.map);
  
//   // Transparent layer, only serves as a layer that will be used for hover functionality
//   routeShapeLayer_transparent  = L.geoJSON(routeShape, {
//     style: function(e) { return { weight: 18, opacity: 0} }
//   }).addTo(Lmap.map);

//   // Add hover events to the transparent layer
//   routeShapeLayer_transparent.on('mouseover', function (e) {
//     const route_id = e.layer.feature.properties.route_id;
//     highlightRouteHover(route_id);
//   });
  
//   routeShapeLayer_transparent.on('mouseout', function () {
//     resetHover();
//   });

//   // Add click event to the transparent layer
//   routeShapeLayer_transparent.on('click', function (e) {
//     const route_id = e.layer.feature.properties.route_id;
//     highlightRouteClick(route_id);
//     if (stops_checkbox.checked) {
//       addStopstoClickedLayer();
//     }
//   });

//   // Highlighted route layer, default as NULL
//   // This will be shown upon hovering on the transparent layer (routeShapeLayer_transparent)
//   highlightRoute = L.geoJSON(null, {
//     style: function(e) { return { weight: 16, opacity: 0.65, color: 'yellow' } } // Adjust the highlighted style
//   }).addTo(Lmap.map);

//   // Highlight shape layer for the clicked route
//   // Only shown upon hovering on the shape item in the legend
//   highlightShape = L.geoJSON(null, {
//     style: function(e) { return { weight: 16, opacity: 0.65, color: 'orange' } } // Adjust the highlighted style
//   }).addTo(Lmap.map);

// });


// /* -------- HOVER EVENT -------- */

// /**
//  * Highlight route on hover.
//  * Updates the map to highlight a route and displays relevant information when hovered over.
//  */

// let highlightedFeatures;
// let route_matched;
// function highlightRouteHover(route_id) {
//   // Filter features based on the provided route_id
//   highlightedFeatures = routeShape.features.filter(feature => feature.properties.route_id === route_id);

//   // Clear existing layers and add new data
//   highlightRoute.clearLayers();
//   highlightRoute.addData({ type: 'FeatureCollection', features: highlightedFeatures });
//   highlightRoute.bringToBack();

//   // Find the matching route in the routes data (this will get us the route long name and such)
//   route_matched = routes.filter(item => item.route_id === route_id);

//   // Update the information displayed in the text-description element
//   document.getElementById('text-description').innerHTML = `<p> <strong>${highlightedFeatures[0].properties.agency_name}<strong></p>`;
//   document.getElementById('text-description').innerHTML += `<div class="grid-container"><span id="route-name">${highlightedFeatures[0].properties.route_short_name}</span> <label>${route_matched[0].route_long_name}</label></div>`;
//   document.getElementById('text-description').innerHTML += `<p>This route operates <strong>${highlightedFeatures.length}</strong> ${highlightedFeatures.length > 1 ? 'paths' : 'path'}.</p>`;
// }
// /**
//  * Reset style for hovered route, clear the information when hovering over a shape is ended.
//  */
// function resetHover() {
//   document.getElementById('text-description').innerHTML = 
//       `<p style="font-size:120%"> <strong>Select routes</strong></p>
//       <p> Use your cursor to highlight routes and see their names here. Click for more details. </p>`;
//   highlightRoute.clearLayers();
//   highlightShape.clearLayers();
// }

// /* -------- CLICKED EVENT -------- */

// /**
//  * This function will be triggered when routeShape layer is clicked
//  * as the result, the stops geometry will be displayed for that clicked route
//  */
// function addStopstoClickedLayer() {
//   const routeStopFeatures = routeStop.features.filter(feature =>
//       feature.properties.route_id === currentHighlightedRouteId 
//   );

//   routeStopLayer.clearLayers();
//   routeStopLayer.addData({ type: 'FeatureCollection', features: routeStopFeatures });
// }

// // Add an event listener to the stops_checkbox element
// stops_checkbox = document.querySelector('.check');
// stops_checkbox.addEventListener('change', function () {
//   toggleRouteStopLayer(stops_checkbox.checked);
// });

// /** 
//  * This function will allow user to show or hide the stops to their preferences
//  * when they click on the stop_checkbox option
// */ 
// function toggleRouteStopLayer(showStops) {  
//   // let showStops = stops_checkbox.checked;
//   // Toggle the visibility of the routeStopLayer
//   if (showStops) {
//     addStopstoClickedLayer();
//   } else {
//     routeStopLayer.clearLayers();
//   }
// }

// /**
//  * Highlight route on click, displays a legend with information, and stores the data of markers for start and end points of each shape.
//  */
// let startEndMarkers = new Map();
// let startMarker = null;
// let endMarker = null;
// function highlightRouteClick(route_id) {
//   // Reset the previous highlighted route if any
//   if (currentHighlightedRouteId != null && currentHighlightedRouteId != route_id) {
//     resetClick(currentHighlightedRouteId);
//     currentHighlightedRouteId = null;
//   }

//   // Construct legend HTML with route information:
//   // Agency Name
//   let legendHTML = `<p style="margin-top:0;"><strong>${highlightedFeatures[0].properties.agency_name}</strong></p>`;
//   // Route Short Name + Route Long Name
//   legendHTML += `<div class="grid-container" style="margin-bottom: 15px;">
//                     <div>
//                       <span id="route-name">${highlightedFeatures[0].properties.route_short_name}</span>
//                     </div>
//                     <div>
//                       <label>${route_matched[0].route_long_name}</label>
//                     </div>
//                  </div>`;
//   // Start/End point markers
//   legendHTML += `<div class="grid-container" id="legend-markers">
//                   <div style="margin-right: 10px;">
//                     <span style=
//                        "background-color: #FFFFFF;
//                         width: 1rem;
//                         height: 1rem;
//                         display: inline-block;
//                         border-radius: 50%;
//                         border: 3px solid #000000;
//                         vertical-align: text-bottom;
//                         margin-right: 5px;">
//                     </span>
//                     <label>Start</label>
//                   </div>
//                   <div>
//                     <i class="fa-solid fa-location-dot"
//                       style=
//                          "background: none;
//                           color: #FFFFFF;
//                           -webkit-text-stroke-width: 2.5px;
//                           -webkit-text-stroke-color: #000000;
//                           font-size: 1.25rem;
//                           vertical-align: text-bottom;
//                           margin-right: 5px;">
//                     </i>
//                     <label>End</label>
//                   </div>
//                 </div>`;
//   // Extra info
//   // List of shape info
//   legendHTML += `<p style="margin-bottom:0;"><strong>Weekly trip counts</strong>*</p>`;
//   legendHTML += `<p style="font-size: small; margin-top:2px; margin-bottom:5px;"><em>*Clickable items</em></p>`;

//   legendHTML += `<ul>`;
  
//   let shape_ids = [];
//   let i = 0;

//   // Iterate through layers to construct legend items
//   highlightRoute.eachLayer(function (layer) {
//     const feature = layer.feature;
//     shape_ids.push(feature.properties.shape_id);
//     legendHTML  += `<li onclick="bringShapetoFront(${feature.properties.shape_id})"
//                         onmouseover="highlightShapeHover(${feature.properties.shape_id})"
//                         onmouseout="resetHover()">
//                         <div class="grid-container">
//                             <span class="legend-color" style="background-color: ${colors[i]}" ></span>
//                             <label><strong>${feature.properties.trips_count}</strong> ${feature.properties.trips_count > 1 ? 'trips' : 'trip'}</label>
//                         </div>
//                     </li>`;
//     i++;
//   });
//   legendHTML  += `</ul>`;

//   // Display the legend and update map styles
//   document.querySelector('.legend').style.display = 'block';
//   document.querySelector('.legend').innerHTML = legendHTML;

//   // Update routeShapeLayer_base styles based for the clicked route
//   routeShapeLayer_base.eachLayer(function (layer) {
//     if (layer.feature.properties.route_id === route_id) {
//       let shape_id = layer.feature.properties.shape_id;
//       let color_style = getColorForEachShape(shape_id, shape_ids);
//       layer.setStyle({ weight: 6, opacity: 1, color: color_style }); // Adjust the style as needed
//       layer.bringToFront();

//       // Get coordinates for start and end points
//       let coordinates = layer.feature.geometry.coordinates;
//       let startLatLng = L.latLng(coordinates[0][1], coordinates[0][0])	;
//       let endLatLng = L.latLng(coordinates[coordinates.length - 1][1], coordinates[coordinates.length - 1][0]);
    
//       let endMarkerStyles = `
//           background: none;
//           color: #FFFFFF;
//           -webkit-text-stroke-width: 3px;
//           -webkit-text-stroke-color: ${color_style};
//           font-size: 1.5rem;
//           left: -0.6rem;
//           top: -1.5rem;
//           position: relative;`

//       const icon = L.divIcon({
//         iconAnchor: [0, 0],
//         labelAnchor: [0,0],
//         iconSize: [0,0],
//         tooltipAnchor: [0,0],
//         html: `<i class="fa-solid fa-location-dot" style="${endMarkerStyles}"></i>`
//       });

//       startMarker = L.circleMarker(startLatLng, {radius: 9, weight: 3, color: color_style, fillOpacity: 1, fillColor: 'white'});
//       endMarker = L.marker(endLatLng, {icon: icon});

//       // Store markers in the startEndMarkers with shape_id as key
//       startEndMarkers.set(shape_id, { start: startMarker, end: endMarker });
//     }
//   });

//   // Update the currently highlighted route ID
//   currentHighlightedRouteId = route_id; 
// }

// /**
//  * Highlight shape (of clicked route) on hover.
//  */
// function highlightShapeHover(shape_id) {
//   highlightedFeatures = routeShape.features.filter(feature => feature.properties.shape_id === shape_id);
//   highlightShape.clearLayers();
//   highlightShape.addData({ type: 'FeatureCollection', features: highlightedFeatures });
//   highlightShape.bringToBack();
// }

// /**
//  * Bring shape (of the clicked route) to front and toggle markers (start/end markers).
//  */
// function bringShapetoFront(shape_id) {
//   routeShapeLayer_base.eachLayer(function (layer) {
//     if (layer.feature.properties.shape_id === shape_id) {
//       layer.bringToFront();
   
//       let markers_shape = startEndMarkers.get(shape_id);

//       // Check if the decorator is currently on the map
//       const isMarkersShown = Lmap.map.hasLayer(markers_shape.start) && Lmap.map.hasLayer(markers_shape.end);

//       // If it's shown, remove it; otherwise, add it to the map
//       if (isMarkersShown) {
//         Lmap.map.removeLayer(markers_shape.start);
//         Lmap.map.removeLayer(markers_shape.end);
//       } else {
//         startEndMarkers.forEach(function(value, key) {
//           if (key !== shape_id) {
//             Lmap.map.removeLayer(value.start);
//             Lmap.map.removeLayer(value.end);
//           } else {
//             markers_shape.start.addTo(Lmap.map);
//             markers_shape.end.addTo(Lmap.map);
//           }
//         });
//       }  
//     }
//   });
//   routeStopLayer.bringToFront();
// }

// /**
//  * Reset the style for clicked route and clear the legend, as well as decorator
//  */
// function resetClick(route_id) {  
//   routeShapeLayer_base.eachLayer(function (layer) {
//     if (layer.feature.properties.route_id === route_id) {
//       routeShapeLayer_base.resetStyle(layer);

//       let shape_id = layer.feature.properties.shape_id;
//       let markers_shape = startEndMarkers.get(shape_id);

//       if (markers_shape) {
//         markers_shape.start.remove();
//         markers_shape.end.remove();
//       }
//     }
//   });

//   routeStopLayer.clearLayers();
//   currentHighlightedRouteId = null;

//   // Clear the legend display
//   document.querySelector('.legend').innerHTML = "";
//   document.querySelector('.legend').style.display = 'none';

//   // Clear the startEndMarkers
//   startEndMarkers.clear();
// }

// /* -------- TABS FUNCTIONS -------- */
// /**
//  * Activate the specified tab and update its visual representation.
//  * @param {number} n - The index of the tab to activate.
//  */

//   // Initial check when the page loads
//   window.onload = function() {
//     resize_tab();
//   };

//   // Handle resize events
//   window.onresize = function() {
//     resize_tab();
//   };

//   var previouslyActiveTab = null;

//   function resize_tab() {
//     // Check the screen height and width
//     var screenHeight = window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight;
//     var screenWidth = window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth;
//     var tabContent = document.querySelector('.map-panel-tabs .tab-content');
//     var totalTabs = 3; // Set the total number of tabs
  
//     // Check if the screen size is small
//     if (screenHeight <= 600 || screenWidth <= 800) {
//       // Remove 'active' class from active tabs
//       for (var i = 1; i <= totalTabs; i++) {
//         const tabClass = `tab-${i}`;
//         const tabElement = document.getElementsByClassName(tabClass)[0];
  
//         if (tabElement.classList.contains('active')) {
//           previouslyActiveTab = i;
//           tabElement.classList.remove('active');
//           tabContent.style.display = 'none';
//           document.getElementById(`tab-${previouslyActiveTab}`).style.display = 'none';
//         }
//       }
//     } else {
//       // Restore 'active' class for the previously active tab
//       if (previouslyActiveTab !== null) {
//         const tabClass = `tab-${previouslyActiveTab}`;
//         const tabElement = document.getElementsByClassName(tabClass)[0];
  
//         if (!tabElement.classList.contains('active')) {
//           tabElement.classList.add('active');
//           activate_tab(previouslyActiveTab);
//         }
//       }
//     }
//   }
  
//   function activate_tab(n) {
//     previouslyActiveTab = n;
//     // Check the screen height and width
//     var screenHeight = window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight;
//     var screenWidth = window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth;
//     var totalTabs = 3; // Set the total number of tabs
//     var tabContent = document.querySelector('.map-panel-tabs .tab-content');
  
//     if (screenHeight > 600 && screenWidth > 800) {
//       // Use the initial logic for screen heights greater than 600px
//       tabContent.style.display = 'block';
  
//       for (var i = 1; i <= totalTabs; i++) {
//         const tabId = `tab-${i}`;
//         const tabElement = document.getElementById(tabId);
//         const tabClass = `tab-${i}`;
  
//         tabElement.style.display = i === n ? "block" : "none";
//         document.getElementsByClassName(tabClass)[0].className = i === n ? `${tabClass} active` : tabClass;
//       }
//     } else {
//       // Toggle the display of the tab content for screen heights less than or equal to 600px
//       for (var i = 1; i <= totalTabs; i++) {
//         const tabId = `tab-${i}`;
//         const tabElement = document.getElementById(tabId);
//         const tabClass = `tab-${i}`;
  
//         if (i === n) {
//           // If tabElement is currently displayed and i equals n, hide it and remove "active" class
//           if (tabElement.style.display === 'block') {
//             tabContent.style.display = 'none';
//             tabElement.style.display = 'none';
//             document.getElementsByClassName(tabClass)[0].classList.remove('active');
//           } else {
//             // If tabElement is not currently displayed, show it and add "active" class
//             tabContent.style.display = 'block';
//             tabElement.style.display = 'block';
//             document.getElementsByClassName(tabClass)[0].className = `${tabClass} active`;
//           }
//         } else {
//           // For other tabs, set display and class accordingly
//           tabElement.style.display = 'none';
//           document.getElementsByClassName(tabClass)[0].className = tabClass;
//         }
//       }
//     }
//   }
  
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
  // Get the search input value
  let input = document.getElementById('searchbar').value.toLowerCase();

  // If the input is empty, clear the results and reset the map
  if (input.trim() === '') {
    clearResults();
    displayStopsOnMap(csvData); // Reset to show all stops if input is cleared
  } else {
    // Filter routes based on the input value (searching by `route_short_name`)
    let matchingItems = csvData.filter(d => d.from_route && d.from_route.toLowerCase().includes(input));
    
    // Display the matching items in a list (if applicable)
    displayMatchingItems(matchingItems);
    
    // Filter stops on the map based on the input route
    filterStopsOnMap(input);
  }
}

/**
 * Clear the previous search results.
 */
function clearResults() {
  let resultsElement = document.getElementById('results');
  resultsElement.innerHTML = '';
}

/**
 * Display matching items in the results list.
 * @param {Array} matchingItems - The array of matching items to display.
 */
function displayMatchingItems(matchingItems) {
  let resultsElement = document.getElementById('results');
  clearResults();

  // Use a Set to store unique combinations of `from_agency` and `from_route`
  const uniqueRoutes = new Set();

  // Display each unique matching route
  matchingItems.forEach(item => {
    const routeKey = `${item.from_agency}-${item.from_route}`; // Unique key for each combination

    // Check if the combination is already displayed
    if (!uniqueRoutes.has(routeKey)) {
      uniqueRoutes.add(routeKey); // Mark this combination as displayed

      let listItem = document.createElement('li');
      listItem.innerHTML = `
        <div class="grid-container">
          <span id="route-name">${item.from_route}</span>
          <label>${item.from_agency}</label>
        </div>`;
      resultsElement.appendChild(listItem);

      // Add click event to each list item to filter map stops by that route
      listItem.addEventListener('click', () => {
        filterStopsOnMap(item.from_route); // Filter the map by the clicked route
        document.getElementsByClassName("dropdown-list")[0].style.display = "none"; // Hide the dropdown list
      });
    }
  });
}

// /**
//  * Clear the previous search results.
//  */
// function clearResults() {
//     // Assuming you have an element with the id "results" to display the matching items
//     let resultsElement = document.getElementById('results');

//     // Clear previous results
//     resultsElement.innerHTML = '';
// }

// /**
//  * Display matching items in the results list.
//  * @param {Array} matchingItems - The array of matching items to display.
//  */
// function displayMatchingItems(matchingItems) {
//   let resultsElement = document.getElementById('results');

//   // Clear previous results
//   clearResults();

//   // Display the matching items
//   matchingItems.forEach(item => {
//       let listItem = document.createElement('li');
//       listItem.innerHTML = `
//         <div class="grid-container">
//           <span id="route-name">${item.route_short_name}</span>
//           <label>${item.route_long_name}</label>
//         </div>`;
//       resultsElement.appendChild(listItem);

//       listItem.addEventListener('mouseover', function () {
//         highlightRouteHover(item.route_id);
//       });

//       listItem.addEventListener('mouseout', function () {
//         resetHover();
//       });

//       // Add a click event listener to each list item
//       listItem.addEventListener('click', function () {
//           highlightRouteClick(item.route_id);
//           if (stops_checkbox.checked) {
//             addStopstoClickedLayer();
//           }
//           document.getElementsByClassName("dropdown-list")[0].style.display = "none"; // hide the drop-down content if one element is clicked
//       });

//   });
// }

/* Section: Side Bar ===================================================================== */ 
// Set the width of the sidebar to 250px (show it)
function openNav() {
  document.getElementById("mySidepanel").style.width = "300px";
}

// Set the width of the sidebar to 0 (hide it)
function closeNav() {
  document.getElementById("mySidepanel").style.width = "0";
}
