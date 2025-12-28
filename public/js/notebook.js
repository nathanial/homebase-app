/**
 * Notebook JavaScript
 * Handles real-time updates via SSE for cross-tab synchronization
 * and autosave functionality for the note editor
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
  var lastSaveId = null;

  // Debounce helper
  function debounce(fn, delay) {
    var timeout;
    return function() {
      var context = this;
      var args = arguments;
      clearTimeout(timeout);
      timeout = setTimeout(function() {
        fn.apply(context, args);
      }, delay);
    };
  }

  // Generate unique save ID
  function generateSaveId() {
    return Date.now().toString(36) + Math.random().toString(36).substr(2, 9);
  }

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
      try {
        var data = JSON.parse(e.data);
        // Skip refresh if this is our own save
        if (data.saveId && data.saveId === lastSaveId) {
          console.log('Ignoring own save event');
          return;
        }
      } catch (err) {
        console.log('Could not parse note-updated event data');
      }
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

  // Autosave functionality
  function initAutosave() {
    var form = document.querySelector('.notebook-editor form');
    if (!form) return;

    var titleInput = document.getElementById('note-title');
    var contentInput = document.getElementById('note-content');
    var statusEl = document.getElementById('save-status');

    if (!titleInput || !contentInput || !statusEl) return;

    var lastSavedTitle = titleInput.value;
    var lastSavedContent = contentInput.value;
    var fadeTimeout = null;

    var saveNote = debounce(function() {
      var title = titleInput.value.trim();
      var content = contentInput.value;

      // Skip if nothing changed
      if (title === lastSavedTitle && content === lastSavedContent) return;
      if (!title) return; // Title required

      statusEl.textContent = 'Saving...';
      statusEl.className = 'notebook-save-status status-saving';

      // Clear any pending fade
      if (fadeTimeout) {
        clearTimeout(fadeTimeout);
        fadeTimeout = null;
      }

      var formData = new FormData(form);
      var saveId = generateSaveId();
      formData.append('saveId', saveId);
      lastSaveId = saveId;  // Set BEFORE fetch to win race with SSE

      // Get the action URL from the form
      var actionUrl = form.getAttribute('action');

      fetch(actionUrl, {
        method: 'PUT',
        body: formData
      }).then(function(response) {
        if (response.ok || response.redirected) {
          lastSavedTitle = title;
          lastSavedContent = content;
          statusEl.textContent = 'Saved';
          statusEl.className = 'notebook-save-status status-saved';

          // Update the note title in the sidebar list
          var selectedNote = document.querySelector('.notebook-note-item.selected');
          if (selectedNote) {
            var titleEl = selectedNote.querySelector('.notebook-note-title');
            if (titleEl) titleEl.textContent = title;
            var previewEl = selectedNote.querySelector('.notebook-note-preview');
            if (previewEl) previewEl.textContent = content.substring(0, 100);
          }

          // Fade out after 2 seconds
          fadeTimeout = setTimeout(function() {
            if (statusEl.textContent === 'Saved') {
              statusEl.textContent = '';
              statusEl.className = 'notebook-save-status';
            }
          }, 2000);
        } else {
          throw new Error('Save failed');
        }
      }).catch(function(e) {
        console.error('Autosave error:', e);
        statusEl.textContent = 'Save failed';
        statusEl.className = 'notebook-save-status status-error';
      });
    }, 1000);

    titleInput.addEventListener('input', saveNote);
    contentInput.addEventListener('input', saveNote);

    console.log('Notebook autosave initialized');
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

  // Connect SSE and initialize autosave on load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      connectSSE();
      initAutosave();
    });
  } else {
    connectSSE();
    initAutosave();
  }

  // Reinitialize autosave after HTMX swaps
  document.body.addEventListener('htmx:afterSwap', initAutosave);
})();
