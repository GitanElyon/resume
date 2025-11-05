// Dynamically adjust print page size to fit all content
(function() {
  'use strict';

  function adjustPrintPageSize() {
    // Get the full height of the content
    const body = document.body;
    const html = document.documentElement;
    
    // Calculate the actual content height
    const contentHeight = Math.max(
      body.scrollHeight,
      body.offsetHeight,
      html.clientHeight,
      html.scrollHeight,
      html.offsetHeight
    );
    
    // Convert pixels to inches (96 DPI is standard for web)
    const heightInInches = contentHeight / 96;
    
    // Set the total height for the print page
    const totalHeightInInches = heightInInches;
    
    // Find or create the style element for print media
    let printStyle = document.getElementById('dynamic-print-style');
    if (!printStyle) {
      printStyle = document.createElement('style');
      printStyle.id = 'dynamic-print-style';
      document.head.appendChild(printStyle);
    }
    
    // Set the dynamic page size
    printStyle.textContent = `
      @media print {
        @page {
          size: 8.5in ${totalHeightInInches}in;
          margin: 0.0in;
        }
        
        html, body {
          height: auto;
          margin: 0;
          padding: 0;
        }
        
        body {
          page-break-after: avoid;
          page-break-inside: avoid;
        }
        
        * {
          page-break-inside: avoid;
        }
      }
    `;
    
    console.log(`Print page size set to: 8.5in × ${totalHeightInInches.toFixed(2)}in`);
  }

  // Run when DOM is fully loaded
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', adjustPrintPageSize);
  } else {
    adjustPrintPageSize();
  }

  // Also adjust before printing (catches Ctrl+P)
  window.addEventListener('beforeprint', adjustPrintPageSize);

  // Adjust on window resize (in case content reflows)
  let resizeTimeout;
  window.addEventListener('resize', function() {
    clearTimeout(resizeTimeout);
    resizeTimeout = setTimeout(adjustPrintPageSize, 250);
  });
})();
