/**
 * Hot Reload Client
 *
 * Connects to the server's hot-reload SSE endpoint and automatically
 * refreshes the page when templates are modified, or hot-swaps CSS
 * without a full page reload.
 */
(function() {
  if (window._hotReloadInitialized) return;
  window._hotReloadInitialized = true;

  var eventSource = new EventSource('/events/hot-reload');

  // Template changes - full page reload
  eventSource.addEventListener('reload', function() {
    console.log('[hot-reload] Template changed, reloading...');
    window.location.reload();
  });

  // CSS changes - smart swap without page reload
  eventSource.addEventListener('css', function(e) {
    var path = e.data;
    console.log('[hot-reload] CSS changed:', path);

    var links = document.querySelectorAll('link[rel="stylesheet"]');
    var timestamp = Date.now();

    links.forEach(function(link) {
      // Check if this stylesheet matches the changed file
      if (link.href.includes(path.replace(/^\//, ''))) {
        // Update href with cache-buster to force reload
        var url = new URL(link.href);
        url.searchParams.set('v', timestamp);
        link.href = url.toString();
        console.log('[hot-reload] Reloaded stylesheet:', path);
      }
    });
  });

  eventSource.onerror = function() {
    console.log('[hot-reload] Connection lost, will retry...');
  };

  window.addEventListener('beforeunload', function() {
    window._hotReloadInitialized = false;
    eventSource.close();
  });

  console.log('[hot-reload] Connected to /events/hot-reload');
})();
