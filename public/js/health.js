/**
 * Health JavaScript
 * Handles real-time updates via SSE for cross-tab synchronization
 */

(function() {
  // Prevent multiple SSE connections
  if (window._healthSSEInitialized) {
    console.log('Health SSE already initialized, skipping');
    return;
  }
  window._healthSSEInitialized = true;

  var eventSource = null;
  var refreshPending = false;

  function refreshPage() {
    if (refreshPending) return;
    refreshPending = true;
    console.log('Refreshing health page...');
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

    console.log('Connecting to Health SSE...');
    eventSource = new EventSource('/events/health');

    eventSource.onopen = function() {
      console.log('Health SSE connected');
    };

    eventSource.onerror = function(e) {
      console.log('Health SSE error, reconnecting...', e);
    };

    // Health entry events
    eventSource.addEventListener('entry-created', function(e) {
      console.log('Health SSE event: entry-created', e.data);
      refreshPage();
    });

    eventSource.addEventListener('entry-updated', function(e) {
      console.log('Health SSE event: entry-updated', e.data);
      refreshPage();
    });

    eventSource.addEventListener('entry-deleted', function(e) {
      console.log('Health SSE event: entry-deleted', e.data);
      refreshPage();
    });
  }

  function disconnectSSE() {
    if (eventSource) {
      console.log('Closing Health SSE connection...');
      eventSource.close();
      eventSource = null;
    }
  }

  // Cleanup on page unload
  window.addEventListener('beforeunload', function() {
    window._healthSSEInitialized = false;
    disconnectSSE();
  });
  window.addEventListener('pagehide', function() {
    window._healthSSEInitialized = false;
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
