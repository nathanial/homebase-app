/**
 * Time Tracker JavaScript
 * Handles real-time updates via SSE for cross-tab synchronization
 */

(function() {
  // Prevent multiple SSE connections across script re-executions
  if (window._timeSSEInitialized) {
    console.log('Time SSE already initialized, skipping');
    return;
  }
  window._timeSSEInitialized = true;

  var eventSource = null;
  var refreshPending = false;

  function refreshTimePage() {
    if (refreshPending) return;
    refreshPending = true;
    console.log('Refreshing time page...');
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

    console.log('Connecting to Time SSE...');
    eventSource = new EventSource('/events/time');

    eventSource.onopen = function() {
      console.log('Time SSE connected');
    };

    eventSource.onerror = function(e) {
      console.log('Time SSE error, reconnecting...', e);
    };

    // Timer events - reload page to show updated timer state
    eventSource.addEventListener('timer-started', function(e) {
      console.log('Time SSE event: timer-started', e.data);
      refreshTimePage();
    });

    eventSource.addEventListener('timer-stopped', function(e) {
      console.log('Time SSE event: timer-stopped', e.data);
      refreshTimePage();
    });

    // Entry events - reload to show updated entries
    eventSource.addEventListener('entry-created', function(e) {
      console.log('Time SSE event: entry-created', e.data);
      refreshTimePage();
    });

    eventSource.addEventListener('entry-updated', function(e) {
      console.log('Time SSE event: entry-updated', e.data);
      refreshTimePage();
    });

    eventSource.addEventListener('entry-deleted', function(e) {
      console.log('Time SSE event: entry-deleted', e.data);
      refreshTimePage();
    });
  }

  function disconnectSSE() {
    if (eventSource) {
      console.log('Closing Time SSE connection...');
      eventSource.close();
      eventSource = null;
    }
  }

  // Close SSE on page unload/navigation
  window.addEventListener('beforeunload', function() {
    window._timeSSEInitialized = false;
    disconnectSSE();
  });
  window.addEventListener('pagehide', function() {
    window._timeSSEInitialized = false;
    disconnectSSE();
  });

  // Handle visibility changes (tab switch, minimize)
  document.addEventListener('visibilitychange', function() {
    if (document.hidden) {
      disconnectSSE();
    } else {
      connectSSE();
    }
  });

  // Connect on page load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', connectSSE);
  } else {
    connectSSE();
  }
})();
