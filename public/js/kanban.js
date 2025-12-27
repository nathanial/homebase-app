/**
 * Kanban Board JavaScript
 * Handles drag-and-drop with SortableJS and real-time updates via SSE
 */

// =============================================================================
// SortableJS Initialization
// =============================================================================

function initSortable() {
  document.querySelectorAll('.sortable-cards').forEach(function(el) {
    if (el.sortableInstance) return;
    el.sortableInstance = new Sortable(el, {
      group: 'kanban-cards',
      animation: 150,
      ghostClass: 'sortable-ghost',
      dragClass: 'sortable-drag',
      chosenClass: 'sortable-chosen',
      onEnd: function(evt) {
        var cardId = evt.item.dataset.cardId;
        var newColumnId = evt.to.dataset.columnId;
        var newIndex = evt.newIndex;
        console.log('Reorder:', cardId, 'to column', newColumnId, 'at position', newIndex);
        fetch('/kanban/card/' + cardId + '/reorder', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: 'column_id=' + newColumnId + '&position=' + newIndex
        }).then(function(response) {
          console.log('Response status:', response.status);
          if (!response.ok) {
            console.error('Reorder failed with status:', response.status);
            window.location.reload();
          }
        }).catch(function(err) {
          console.error('Reorder failed:', err);
          window.location.reload();
        });
      }
    });
  });
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
  initSortable();
});

// Re-initialize after HTMX swaps
document.body.addEventListener('htmx:afterSwap', function(evt) {
  initSortable();
});

// =============================================================================
// Server-Sent Events (SSE) for Real-time Updates
// =============================================================================

(function() {
  // Prevent multiple SSE connections across script re-executions
  if (window._kanbanSSEInitialized) {
    console.log('Kanban SSE already initialized, skipping');
    return;
  }
  window._kanbanSSEInitialized = true;

  var status = document.getElementById('sse-status');
  var eventSource = null;
  var refreshPending = false;

  function updateStatus(text, className) {
    if (status) {
      status.textContent = text;
      status.className = className;
    }
  }

  function getBoardId() {
    // Extract board ID from URL: /kanban/board/123
    var match = window.location.pathname.match(/\/kanban\/board\/(\d+)/);
    return match ? match[1] : null;
  }

  function refreshBoard() {
    if (refreshPending) return;
    var boardId = getBoardId();
    if (!boardId) {
      console.log('No board ID found, skipping refresh');
      return;
    }
    refreshPending = true;
    console.log('Refreshing kanban board', boardId);
    setTimeout(function() {
      // Only refresh the columns container, not the whole page
      // This preserves the SSE connection
      htmx.ajax('GET', '/kanban/board/' + boardId + '/columns', {target: '#board-columns', swap: 'innerHTML'});
      refreshPending = false;
    }, 100);
  }

  function connectSSE() {
    if (eventSource) {
      eventSource.close();
      eventSource = null;
    }

    console.log('Connecting to SSE...');
    eventSource = new EventSource('/events/kanban');

    eventSource.onopen = function() {
      console.log('SSE connected');
      updateStatus('● Live', 'text-xs text-green-500');
    };

    eventSource.onerror = function(e) {
      console.log('SSE error, reconnecting...', e);
      updateStatus('○ Reconnecting...', 'text-xs text-yellow-500');
    };

    // Listen for specific event types
    var eventTypes = ['column-created', 'column-updated', 'column-deleted',
                      'card-created', 'card-updated', 'card-deleted',
                      'card-moved', 'card-reordered',
                      'board-created', 'board-updated', 'board-deleted'];

    eventTypes.forEach(function(eventType) {
      eventSource.addEventListener(eventType, function(e) {
        console.log('SSE event:', eventType, e.data);
        refreshBoard();
      });
    });
  }

  function disconnectSSE() {
    if (eventSource) {
      console.log('Closing SSE connection...');
      eventSource.close();
      eventSource = null;
    }
  }

  // Close SSE on page unload/navigation
  window.addEventListener('beforeunload', function() {
    window._kanbanSSEInitialized = false;
    disconnectSSE();
  });
  window.addEventListener('pagehide', function() {
    window._kanbanSSEInitialized = false;
    disconnectSSE();
  });

  // Handle visibility changes (tab switch, minimize)
  document.addEventListener('visibilitychange', function() {
    if (document.hidden) {
      // Page is hidden - disconnect to free up connection slot
      disconnectSSE();
    } else {
      // Page is visible again - reconnect
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
