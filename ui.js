document.addEventListener('DOMContentLoaded', () => {
  // Download PDF functionality
  const downloadBtn = document.querySelector('.download-btn');
  if (downloadBtn) {
    downloadBtn.addEventListener('click', () => {
      const element = document.querySelector('.container');
      
      // Clone the element to avoid messing with the visible resume
      const clone = element.cloneNode(true);
      
      // Reset any transforms on the clone so it prints at full size
      clone.style.transform = 'none';
      clone.style.margin = '0';
      
      const wrapper = document.createElement('div');
      wrapper.style.position = 'absolute';
      wrapper.style.top = '-9999px';
      wrapper.style.left = '-9999px';
      wrapper.style.width = '8.5in'; // Ensure correct width context
      wrapper.appendChild(clone);
      document.body.appendChild(wrapper);

      // Calculate dynamic height based on content
      // 96px is the standard conversion for 1 CSS inch
      const heightPx = clone.scrollHeight;
      const heightIn = heightPx / 96;
      
      // Use the calculated height for the PDF page size
      const opt = {
        margin: 0,
        filename: 'GitanElyon_Resume.pdf',
        image: { type: 'jpeg', quality: 0.98 },
        html2canvas: { scale: 2, useCORS: true, scrollY: 0 },
        jsPDF: { unit: 'in', format: [8.5, heightIn], orientation: 'portrait' }
      };

      html2pdf().set(opt).from(clone).save().then(() => {
        document.body.removeChild(wrapper);
      });
    });
  }

  // Scroll visibility
  const buttons = document.querySelectorAll('.download-btn, .website-btn');
  let isScrolling;

  window.addEventListener('scroll', () => {
    buttons.forEach(btn => btn.classList.add('hidden'));
    
    window.clearTimeout(isScrolling);
    isScrolling = setTimeout(() => {
      buttons.forEach(btn => btn.classList.remove('hidden'));
    }, 200);
  });
});
