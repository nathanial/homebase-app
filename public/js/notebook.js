/**
 * Notebook JavaScript
 * Handles real-time updates via SSE for cross-tab synchronization
 */

(function() {
  // Prevent multiple SSE connections
  if (window._notebookSSEInitialized) {
    console.log('Notebook SSE already initialized, skipping');
    return;
  }
  window._notebookSSEInitialized = true;

  var eventSource = null;
  var refreshPending = false;

  function refreshPage() {
    if (refreshPending) return;
    refreshPending = true;
    console.log('Refreshing notebook page...');
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

    console.log('Connecting to Notebook SSE...');
    eventSource = new EventSource('/events/notebook');

    eventSource.onopen = function() {
      console.log('Notebook SSE connected');
    };

    eventSource.onerror = function(e) {
      console.log('Notebook SSE error, reconnecting...', e);
    };

    // Notebook events
    eventSource.addEventListener('notebook-created', function(e) {
      console.log('Notebook SSE event: notebook-created', e.data);
      refreshPage();
    });

    eventSource.addEventListener('notebook-updated', function(e) {
      console.log('Notebook SSE event: notebook-updated', e.data);
      refreshPage();
    });

    eventSource.addEventListener('notebook-deleted', function(e) {
      console.log('Notebook SSE event: notebook-deleted', e.data);
      refreshPage();
    });

    // Note events
    eventSource.addEventListener('note-created', function(e) {
      console.log('Notebook SSE event: note-created', e.data);
      refreshPage();
    });

    eventSource.addEventListener('note-updated', function(e) {
      console.log('Notebook SSE event: note-updated', e.data);
      refreshPage();
    });

    eventSource.addEventListener('note-deleted', function(e) {
      console.log('Notebook SSE event: note-deleted', e.data);
      refreshPage();
    });
  }

  function disconnectSSE() {
    if (eventSource) {
      console.log('Closing Notebook SSE connection...');
      eventSource.close();
      eventSource = null;
    }
  }

  // Cleanup on page unload
  window.addEventListener('beforeunload', function() {
    window._notebookSSEInitialized = false;
    disconnectSSE();
  });
  window.addEventListener('pagehide', function() {
    window._notebookSSEInitialized = false;
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
