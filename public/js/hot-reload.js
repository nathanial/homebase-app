/**
 * Hot Reload Client
 *
 * Connects to the server's hot-reload SSE endpoint and automatically
 * refreshes the page when templates are modified.
 */
(function() {
  if (window._hotReloadInitialized) return;
  window._hotReloadInitialized = true;

  var eventSource = new EventSource('/events/hot-reload');

  eventSource.addEventListener('reload', function() {
    console.log('[hot-reload] Template changed, reloading...');
    window.location.reload();
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
