// const passengerCountValueMin = document.getElementById('passenger_count_value_min');
// const passengerCountValueMax = document.getElementById('passenger_count_value_max');


function updateSliderRange() {
  passengerCounts = d3.rollup(
    filteredData,
    v => d3.sum(v, d => +d.passenger_count),
    d => d.stop_code
  );

  // Calculate min and max passenger counts
  minPassengerCount = d3.min(
    Array.from(passengerCounts.values()) // Extract the values from the Map
  );
  maxPassengerCount = d3.max(
    Array.from(passengerCounts.values()) // Extract the values from the Map
  );

  passengerCountSlider.noUiSlider.updateOptions({
    start: [minPassengerCount, maxPassengerCount],
    range: {
      'min': minPassengerCount,
      'max': maxPassengerCount
    }
  });

  // Ensure the slider values are within the new range
  if (passengerSlider.passengerCountMin < minPassengerCount || passengerSlider.passengerCountMin > maxPassengerCount) {
    passengerSlider.passengerCountMin = minPassengerCount;
    passengerCountSlider.noUiSlider.set([minPassengerCount, null]);
  }
  if (passengerSlider.passengerCountMax < minPassengerCount || passengerSlider.passengerCountMax > maxPassengerCount) {
    passengerSlider.passengerCountMax = maxPassengerCount;
    passengerCountSlider.noUiSlider.set([null, maxPassengerCount]);
  }
}
