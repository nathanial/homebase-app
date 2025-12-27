/**
 * Gallery JavaScript
 * Handles real-time updates via SSE for cross-tab synchronization
 */

(function() {
  // Prevent multiple SSE connections across script re-executions
  if (window._gallerySSEInitialized) {
    console.log('Gallery SSE already initialized, skipping');
    return;
  }
  window._gallerySSEInitialized = true;

  var eventSource = null;
  var refreshPending = false;

  function refreshGalleryPage() {
    if (refreshPending) return;
    refreshPending = true;
    console.log('Refreshing gallery page...');
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

    console.log('Connecting to Gallery SSE...');
    eventSource = new EventSource('/events/gallery');

    eventSource.onopen = function() {
      console.log('Gallery SSE connected');
    };

    eventSource.onerror = function(e) {
      console.log('Gallery SSE error, reconnecting...', e);
    };

    // Item events - reload page to show updated gallery
    eventSource.addEventListener('item-uploaded', function(e) {
      console.log('Gallery SSE event: item-uploaded', e.data);
      refreshGalleryPage();
    });

    eventSource.addEventListener('item-updated', function(e) {
      console.log('Gallery SSE event: item-updated', e.data);
      refreshGalleryPage();
    });

    eventSource.addEventListener('item-deleted', function(e) {
      console.log('Gallery SSE event: item-deleted', e.data);
      refreshGalleryPage();
    });
  }

  function disconnectSSE() {
    if (eventSource) {
      console.log('Closing Gallery SSE connection...');
      eventSource.close();
      eventSource = null;
    }
  }

  // Close SSE on page unload/navigation
  window.addEventListener('beforeunload', function() {
    window._gallerySSEInitialized = false;
    disconnectSSE();
  });
  window.addEventListener('pagehide', function() {
    window._gallerySSEInitialized = false;
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
