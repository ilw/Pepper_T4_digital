// Trigger WaveDrom to process all diagrams after page load
window.addEventListener("load", function() {
    if (typeof WaveDrom !== 'undefined') {
        WaveDrom.ProcessAll();
    } else {
        console.error('WaveDrom library not loaded');
    }
});
