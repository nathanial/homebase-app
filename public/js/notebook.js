/**
 * Notebook JavaScript
 * Handles real-time updates via SSE for cross-tab synchronization
 * and autosave functionality for the note editor
 */

(function() {
  console.log('Notebook JavaScript started');
  console.log('Notebook JavaScript loaded');
  // Prevent multiple SSE connections
  if (window._notebookSSEInitialized) {
    console.log('Notebook SSE already initialized, skipping');
    return;
  }
  window._notebookSSEInitialized = true;

  var eventSource = null;
  var refreshPending = false;
  var lastSaveId = null;
  var quillInstance = null;

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

  // Upload image to server and return URL
  function uploadImage(file, callback) {
    var formData = new FormData();
    formData.append('image', file);

    fetch('/notebook/upload-image', {
      method: 'POST',
      body: formData
    })
    .then(function(response) { return response.json(); })
    .then(function(data) {
      if (data.url) {
        callback(data.url);
      } else {
        console.error('Upload failed:', data.error);
        alert('Image upload failed: ' + (data.error || 'Unknown error'));
      }
    })
    .catch(function(err) {
      console.error('Upload error:', err);
      alert('Image upload failed');
    });
  }

  // Custom image handler for Quill
  function imageHandler() {
    var input = document.createElement('input');
    input.setAttribute('type', 'file');
    input.setAttribute('accept', 'image/*');
    input.click();

    input.onchange = function() {
      var file = input.files[0];
      if (file) {
        uploadImage(file, function(url) {
          var range = quillInstance.getSelection(true);
          quillInstance.insertEmbed(range.index, 'image', url);
          quillInstance.setSelection(range.index + 1);
        });
      }
    };
  }

  // Initialize Quill rich text editor
  function initQuillEditor(onTextChange) {
    var contentInput = document.getElementById('note-content');
    if (!contentInput) return null;

    // Clean up previous instance if exists
    if (quillInstance) {
      var oldContainer = document.getElementById('quill-editor');
      if (oldContainer) oldContainer.remove();
      quillInstance = null;
    }

    // Create container for Quill
    var editorContainer = document.createElement('div');
    editorContainer.id = 'quill-editor';
    contentInput.parentNode.insertBefore(editorContainer, contentInput);

    // Initialize Quill with toolbar and custom image handler
    quillInstance = new Quill('#quill-editor', {
      theme: 'snow',
      modules: {
        toolbar: {
          container: [
            [{ 'header': [1, 2, 3, false] }],
            ['bold', 'italic', 'underline', 'strike'],
            [{ 'list': 'ordered'}, { 'list': 'bullet' }],
            ['blockquote', 'code-block'],
            ['link', 'image'],
            ['clean']
          ],
          handlers: {
            image: imageHandler
          }
        }
      },
      placeholder: 'Write your note...'
    });

    // Set initial content from hidden textarea
    if (contentInput.value) {
      quillInstance.root.innerHTML = contentInput.value;
    }

    // Handle paste events to intercept base64 images
    quillInstance.root.addEventListener('paste', function(e) {
      var clipboardData = e.clipboardData || window.clipboardData;
      if (clipboardData && clipboardData.items) {
        for (var i = 0; i < clipboardData.items.length; i++) {
          var item = clipboardData.items[i];
          if (item.type.indexOf('image') !== -1) {
            e.preventDefault();
            var file = item.getAsFile();
            if (file) {
              uploadImage(file, function(url) {
                var range = quillInstance.getSelection(true);
                quillInstance.insertEmbed(range.index, 'image', url);
                quillInstance.setSelection(range.index + 1);
              });
            }
            return;
          }
        }
      }
    });

    // Sync changes to hidden textarea and trigger autosave
    quillInstance.on('text-change', function() {
      contentInput.value = quillInstance.root.innerHTML;
      if (onTextChange) onTextChange();
    });

    return quillInstance;
  }

  // Context menu for notebooks
  var contextMenu = null;

  window.showNotebookContextMenu = function(e, nbId) {
    e.preventDefault();
    e.stopPropagation();
    hideContextMenu();

    contextMenu = document.createElement('div');
    contextMenu.className = 'notebook-context-menu';
    contextMenu.innerHTML =
      '<button onclick="editNotebook(' + nbId + ')">Edit</button>' +
      '<button onclick="deleteNotebook(' + nbId + ')" class="danger">Delete</button>';
    contextMenu.style.left = e.pageX + 'px';
    contextMenu.style.top = e.pageY + 'px';
    document.body.appendChild(contextMenu);
  };

  function hideContextMenu() {
    if (contextMenu) {
      contextMenu.remove();
      contextMenu = null;
    }
  }

  window.editNotebook = function(nbId) {
    hideContextMenu();
    htmx.ajax('GET', '/notebook/' + nbId + '/edit', {target: '#modal-container', swap: 'innerHTML'});
  };

  window.deleteNotebook = function(nbId) {
    hideContextMenu();
    showConfirmModal('Delete this notebook and all its notes?', function() {
      htmx.ajax('DELETE', '/notebook/' + nbId, {swap: 'none'});
    });
  };

  // Context menu for notes
  window.showNoteContextMenu = function(e, noteId) {
    e.preventDefault();
    e.stopPropagation();
    hideContextMenu();

    contextMenu = document.createElement('div');
    contextMenu.className = 'notebook-context-menu';
    contextMenu.innerHTML =
      '<button onclick="deleteNote(' + noteId + ')" class="danger">Delete</button>';
    contextMenu.style.left = e.pageX + 'px';
    contextMenu.style.top = e.pageY + 'px';
    document.body.appendChild(contextMenu);
  };

  window.deleteNote = function(noteId) {
    hideContextMenu();
    showConfirmModal('Delete this note?', function() {
      htmx.ajax('DELETE', '/notebook/note/' + noteId, {swap: 'none'});
    });
  };

  document.addEventListener('click', hideContextMenu);

  // Toggle notebook expand/collapse
  window.toggleNotebook = function(nbId) {
    var notes = document.getElementById('notebook-' + nbId + '-notes');
    if (!notes) return;

    var item = notes.previousElementSibling;
    var toggle = item ? item.querySelector('.notebook-tree-toggle') : null;

    if (notes.classList.contains('collapsed')) {
      notes.classList.remove('collapsed');
      if (toggle) toggle.textContent = '▼';
      localStorage.setItem('notebook-' + nbId + '-expanded', 'true');
    } else {
      notes.classList.add('collapsed');
      if (toggle) toggle.textContent = '▶';
      localStorage.setItem('notebook-' + nbId + '-expanded', 'false');
    }
  };

  // Restore expanded state from localStorage
  function restoreExpandedState() {
    var items = document.querySelectorAll('.notebook-tree-item');
    items.forEach(function(item) {
      var notes = item.nextElementSibling;
      if (!notes || !notes.id) return;

      var match = notes.id.match(/notebook-(\d+)-notes/);
      if (!match) return;

      var nbId = match[1];
      var expanded = localStorage.getItem('notebook-' + nbId + '-expanded');
      var toggle = item.querySelector('.notebook-tree-toggle');

      if (expanded === 'true') {
        notes.classList.remove('collapsed');
        if (toggle) toggle.textContent = '▼';
      } else if (expanded === 'false') {
        notes.classList.add('collapsed');
        if (toggle) toggle.textContent = '▶';
      }
      // If no stored value, use server-rendered state
    });
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
    var versionInput = document.getElementById('note-version');
    var statusEl = document.getElementById('save-status');

    if (!titleInput || !contentInput || !statusEl || !versionInput) return;

    var lastSavedTitle = titleInput.value;
    var lastSavedContent = contentInput.value;
    var fadeTimeout = null;

    var saveNote = debounce(function() {
      var title = titleInput.value.trim();
      // Get content from Quill if available, otherwise from textarea
      var content = quillInstance ? quillInstance.root.innerHTML : contentInput.value;

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

      // Sync Quill content to hidden textarea for FormData
      if (quillInstance) {
        contentInput.value = quillInstance.root.innerHTML;
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
      })
      .then(function(response) { return response.json(); })
      .then(function(data) {
        if (data.conflict) {
          // Version conflict detected
          statusEl.textContent = 'Conflict!';
          statusEl.className = 'notebook-save-status status-error';

          var msg = 'This note was modified in another tab/window.\n\n' +
                    'Your changes cannot be saved without overwriting the other changes.\n\n' +
                    'Click OK to reload with the latest version (your changes will be lost), ' +
                    'or Cancel to continue editing (you can copy your changes first).';

          if (confirm(msg)) {
            window.location.reload();
          }
        } else if (data.version) {
          // Success - update version
          versionInput.value = data.version;
          lastSavedTitle = title;
          lastSavedContent = content;
          statusEl.textContent = 'Saved';
          statusEl.className = 'notebook-save-status status-saved';

          // Update the note title in the sidebar tree
          var selectedNote = document.querySelector('.notebook-tree-note.selected');
          if (selectedNote) {
            var titleEl = selectedNote.querySelector('.notebook-tree-note-title');
            if (titleEl) titleEl.textContent = title;
          }

          // Fade out after 2 seconds
          fadeTimeout = setTimeout(function() {
            if (statusEl.textContent === 'Saved') {
              statusEl.textContent = '';
              statusEl.className = 'notebook-save-status';
            }
          }, 2000);
        } else {
          throw new Error('Unexpected response');
        }
      }).catch(function(e) {
        console.error('Autosave error:', e);
        statusEl.textContent = 'Save failed';
        statusEl.className = 'notebook-save-status status-error';
      });
    }, 1000);

    titleInput.addEventListener('input', saveNote);

    // Initialize Quill rich text editor (passes saveNote as callback for text changes)
    initQuillEditor(saveNote);

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

  // Connect SSE and initialize on load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      connectSSE();
      initAutosave();
      restoreExpandedState();
    });
  } else {
    connectSSE();
    initAutosave();
    restoreExpandedState();
  }

  // Reinitialize after HTMX swaps
  document.body.addEventListener('htmx:afterSwap', function() {
    initAutosave();
    restoreExpandedState();
  });
})();
