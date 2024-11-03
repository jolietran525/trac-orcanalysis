/* =====================================================================================
 * DESCRIPTION: Layout Adjustments and Resizing
 * 
 * README: 
 * ---- This file can handle layout updates for both the map and popup, managing the 
 *      resizing of elements based on user interaction and window size.
 * 
 * ===================================================================================== */

const popupContainer = document.querySelector('#popup-container');
const mapContainer = document.querySelector('#map');
const mapArea = document.querySelector('#map-area');
let isResized = false;
var startX, startWidth, totalWidth;

function adjustLayoutBasedOnPopupContent() {
    // Check if popupContainer contains a popup-table
    const popupContent = popupContainer.querySelector('.popup-table');

    if (popupContent) {
      // If popupContent exists, set the popupContainer to occupy 30% and mapContainer 70%
      if (isResized) {
        totalWidth = mapArea.getBoundingClientRect().width;
        // Apply the new widths as flex-basis values
        popupContainer.style.flex = `0 0 ${startWidth}px`;
        mapContainer.style.flex = `0 0 ${totalWidth - startWidth}px`;
      } else {
        popupContainer.style.flex = '1';
        popupContainer.style.flexBasis = '30%';
        mapContainer.style.flex = '1';
        mapContainer.style.flexBasis = '70%';
      }
    } else {
      // If popupContent does not exist, reset popupContainer to 0% and expand mapContainer
      popupContainer.style.flex = '0';
      popupContainer.style.flexBasis = '0';
      mapContainer.style.flex = '1';
      mapContainer.style.flexBasis = '100%';
    }  

    // Also trigger Leaflet to update the map size after adjustment
    Lmap.map.invalidateSize();
}

// Call the function initially and whenever the popup data changes
adjustLayoutBasedOnPopupContent();

// Resize handler
function updateLayoutOnResize() {
  // Update flex-basis values based on current layout
  const totalWidth = mapArea.getBoundingClientRect().width;
  const popupWidth = parseInt(window.getComputedStyle(popupContainer).flexBasis) || 0;
  const mapWidth = totalWidth - popupWidth;
  popupContainer.style.flexBasis = `${popupWidth}px`;
  mapContainer.style.flexBasis = `${mapWidth}px`;
}

// Add resize event listener
window.addEventListener('resize', () => {
  updateLayoutOnResize();
  adjustLayoutBasedOnPopupContent();
}); 

// Add a mousemove event to adjust the cursor only when near the edge
popupContainer.addEventListener('mousemove', function(e) {
    const offsetX = e.clientX - popupContainer.getBoundingClientRect().left;

    // Check if the mouse is within 10px of the left edge
    popupContainer.style.cursor = offsetX < 10 ? 'ew-resize' : 'default';
});

// Add event listener for mousedown to initiate the resize
popupContainer.addEventListener('mousedown', function(e) {
    const offsetX = e.clientX - popupContainer.getBoundingClientRect().left;

    // Only start resizing if the click is within 10px of the left edge
    if (offsetX < 10) {
        startX = e.clientX;
        startWidth = popupContainer.getBoundingClientRect().width;
        totalWidth = mapArea.getBoundingClientRect().width;  // Get the total width of #map-area
        document.documentElement.addEventListener('mousemove', doDrag, false);
        document.documentElement.addEventListener('mouseup', stopDrag, false);
    }
}, false);


function doDrag(e) {
    // Calculate how far the mouse has moved from the starting position
    let deltaX = startX - e.clientX; // Change the calculation to be relative to the mouse movement

    // Calculate the new width of the popup container
    let newPopupWidth = startWidth + deltaX;

    // Ensure the new width doesn't exceed container limits
    if (newPopupWidth < 150) newPopupWidth = 150;
    
    // Calculate the maximum allowed width for the popup
    const maxPopupWidth = totalWidth - 150; // leaving 50px for the map

    if (newPopupWidth > maxPopupWidth) newPopupWidth = maxPopupWidth;

    // Apply the new widths as flex-basis values
    popupContainer.style.flex = `0 0 ${newPopupWidth}px`;
    mapContainer.style.flex = `0 0 ${totalWidth - newPopupWidth}px`;

    // Update the starting width and position for the next drag event
    startWidth = newPopupWidth; 
    startX = e.clientX; // Update startX to the current mouse position
}


function stopDrag(e) {
  isResized = true; 
  // Trigger Leaflet to update its size
  document.documentElement.removeEventListener('mousemove', doDrag, false);
  document.documentElement.removeEventListener('mouseup', stopDrag, false);
  Lmap.map.invalidateSize();
  Lmap.map.setView(Lmap.map.getCenter());  
}
