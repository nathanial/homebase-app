/**
 * News JavaScript
 * Handles real-time updates via SSE for cross-tab synchronization
 */

(function() {
  // Prevent multiple SSE connections
  if (window._newsSSEInitialized) {
    console.log('News SSE already initialized, skipping');
    return;
  }
  window._newsSSEInitialized = true;

  var eventSource = null;
  var refreshPending = false;

  function refreshPage() {
    if (refreshPending) return;
    refreshPending = true;
    console.log('Refreshing news page...');
    setTimeout(function() {
      window.location.reload();
      refreshPending = false;
    }, 100);
  }

  function connectSSE() {
    if (eventSource) {
      eventSource.close();
      eventSource = null;
    }

    console.log('Connecting to News SSE...');
    eventSource = new EventSource('/events/news');

    eventSource.onopen = function() {
      console.log('News SSE connected');
    };

    eventSource.onerror = function(e) {
      console.log('News SSE error, reconnecting...', e);
    };

    // News item events
    eventSource.addEventListener('item-added', function(e) {
      console.log('News SSE event: item-added', e.data);
      refreshPage();
    });

    eventSource.addEventListener('item-updated', function(e) {
      console.log('News SSE event: item-updated', e.data);
      refreshPage();
    });

    eventSource.addEventListener('item-deleted', function(e) {
      console.log('News SSE event: item-deleted', e.data);
      refreshPage();
    });
  }

  function disconnectSSE() {
    if (eventSource) {
      console.log('Closing News SSE connection...');
      eventSource.close();
      eventSource = null;
    }
  }

  // Cleanup on page unload
  window.addEventListener('beforeunload', function() {
    window._newsSSEInitialized = false;
    disconnectSSE();
  });
  window.addEventListener('pagehide', function() {
    window._newsSSEInitialized = false;
    disconnectSSE();
  });

  // Handle visibility changes
  document.addEventListener('visibilitychange', function() {
    if (document.hidden) {
      disconnectSSE();
    } else {
      connectSSE();
    }
  });

  // Connect on load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', connectSSE);
  } else {
    connectSSE();
  }
})();
