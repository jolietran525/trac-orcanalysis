/* =====================================================================================
 * DESCRIPTION: Sidebar Controls
 * 
 * README: 
 * ---- Functions for managing the sidebar can be isolated into a file for easier future
 *      maintenance.
 * 
 * ===================================================================================== */

// Set the width of the sidebar to 250px (show it)
function openNav() {
    document.getElementById("mySidepanel").style.width = "450px";
  }
  
  // Set the width of the sidebar to 0 (hide it)
  function closeNav() {
    document.getElementById("mySidepanel").style.width = "0";
  }
  