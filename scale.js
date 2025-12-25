(function() {
  function scaleResume() {
    const container = document.querySelector('.container');
    const wrapper = document.querySelector('.resume-wrapper');
    if (!container || !wrapper) return;

    // 8.5in * 96dpi = 816px
    const originalWidth = 816; 
    // Body padding is 20px on each side, so 40px total
    const padding = 40; 
    const availableWidth = window.innerWidth - padding;

    if (availableWidth < originalWidth) {
      const scale = availableWidth / originalWidth;
      
      container.style.transform = `scale(${scale})`;
      container.style.transformOrigin = 'top left';
      
      // Set wrapper size to match the scaled content
      wrapper.style.width = `${originalWidth * scale}px`;
      wrapper.style.height = `${container.offsetHeight * scale}px`;
      
      // Remove margin adjustments from previous version if any
      container.style.marginBottom = '0';
    } else {
      container.style.transform = 'none';
      wrapper.style.width = '';
      wrapper.style.height = '';
    }
  }

  window.addEventListener('resize', scaleResume);
  window.addEventListener('load', scaleResume);
  // Also run immediately in case load already fired
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    scaleResume();
  }
})();
