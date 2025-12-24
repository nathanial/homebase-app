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
  var status = document.getElementById('sse-status');
  var eventSource = null;
  var refreshPending = false;

  function updateStatus(text, className) {
    if (status) {
      status.textContent = text;
      status.className = className;
    }
  }

  function refreshBoard() {
    if (refreshPending) return;
    refreshPending = true;
    console.log('Refreshing kanban board...');
    setTimeout(function() {
      // Only refresh the columns container, not the whole page
      // This preserves the SSE connection
      htmx.ajax('GET', '/kanban/columns', {target: '#board-columns', swap: 'innerHTML'});
      refreshPending = false;
    }, 100);
  }

  function connectSSE() {
    if (eventSource) {
      eventSource.close();
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
                      'card-moved', 'card-reordered'];

    eventTypes.forEach(function(eventType) {
      eventSource.addEventListener(eventType, function(e) {
        console.log('SSE event:', eventType, e.data);
        refreshBoard();
      });
    });
  }

  // Connect on page load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', connectSSE);
  } else {
    connectSSE();
  }
})();
