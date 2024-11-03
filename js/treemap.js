/* =====================================================================================
 * DESCRIPTION: Treemap and Visualization
 * 
 * README: 
 * ---- All functions related to treemap creation and updating could be consolidated 
 *      here, as well as helper functions for managing hierarchy data and color schemes.
 * 
 * ===================================================================================== */

let hierarchyData, filteredStop;
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
resizeObserver.observe(document.querySelector('#popup-container'));

function createTreemapForStop(stopCode) {
  // Step 1: Filter the stop_code based on the filteredData
  filteredStop = filteredData.filter(d => d.stop_code === stopCode);

  // Group by to_agency and to_route, then sum passenger_count
  const nestedData = d3.group(filteredStop, d => d.to_agency, d => d.to_route);

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
  adjustLayoutBasedOnPopupContent();
}


function createTreemap(hierarchyData) {
  const container = d3.select("#popup-container").node();
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
  d3.select("#popup-container").selectAll("svg").remove(); // Clear any existing treemap
  const svg = d3.select("#popup-container")
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

