/**
 * Recipes JavaScript
 * Handles real-time updates via SSE for cross-tab synchronization
 */

(function() {
  // Prevent multiple SSE connections
  if (window._recipesSSEInitialized) {
    console.log('Recipes SSE already initialized, skipping');
    return;
  }
  window._recipesSSEInitialized = true;

  var eventSource = null;
  var refreshPending = false;

  function refreshPage() {
    if (refreshPending) return;
    refreshPending = true;
    console.log('Refreshing recipes page...');
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

    console.log('Connecting to Recipes SSE...');
    eventSource = new EventSource('/events/recipes');

    eventSource.onopen = function() {
      console.log('Recipes SSE connected');
    };

    eventSource.onerror = function(e) {
      console.log('Recipes SSE error, reconnecting...', e);
    };

    // Recipe events
    eventSource.addEventListener('recipe-created', function(e) {
      console.log('Recipes SSE event: recipe-created', e.data);
      refreshPage();
    });

    eventSource.addEventListener('recipe-updated', function(e) {
      console.log('Recipes SSE event: recipe-updated', e.data);
      refreshPage();
    });

    eventSource.addEventListener('recipe-deleted', function(e) {
      console.log('Recipes SSE event: recipe-deleted', e.data);
      refreshPage();
    });
  }

  function disconnectSSE() {
    if (eventSource) {
      console.log('Closing Recipes SSE connection...');
      eventSource.close();
      eventSource = null;
    }
  }

  // Cleanup on page unload
  window.addEventListener('beforeunload', function() {
    window._recipesSSEInitialized = false;
    disconnectSSE();
  });
  window.addEventListener('pagehide', function() {
    window._recipesSSEInitialized = false;
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
