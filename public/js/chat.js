/**
 * Chat JavaScript
 * Handles real-time updates via SSE, scroll behavior, and file uploads
 */

// =============================================================================
// File Upload Handling
// =============================================================================

// Pending files to upload with the message
var pendingFiles = [];

// Handle drag over the input container
function handleDragOver(event) {
  event.preventDefault();
  event.stopPropagation();
  var zone = document.getElementById('chat-input-drop-zone');
  if (zone) zone.classList.add('dragover');
}

// Handle drag leave
function handleDragLeave(event) {
  event.preventDefault();
  event.stopPropagation();
  var zone = document.getElementById('chat-input-drop-zone');
  // Only remove class if leaving the container entirely
  if (zone && !zone.contains(event.relatedTarget)) {
    zone.classList.remove('dragover');
  }
}

// Handle drop on input container
function handleInputDrop(event) {
  event.preventDefault();
  event.stopPropagation();
  var zone = document.getElementById('chat-input-drop-zone');
  if (zone) zone.classList.remove('dragover');
  var files = event.dataTransfer.files;
  handleFileSelect(files);
}

// Handle file selection from input
function handleFileSelect(files) {
  for (var i = 0; i < files.length; i++) {
    var file = files[i];
    // Validate file size (10MB limit)
    if (file.size > 10 * 1024 * 1024) {
      alert('File "' + file.name + '" is too large. Maximum size is 10MB.');
      continue;
    }
    // Validate file type
    var allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'application/pdf', 'text/plain'];
    if (!allowedTypes.some(function(t) { return file.type.startsWith(t.split('/')[0]) || file.type === t; })) {
      alert('File type "' + file.type + '" is not allowed.');
      continue;
    }
    pendingFiles.push(file);
  }
  updateUploadPreview();
}

// Update the preview area showing pending files
function updateUploadPreview() {
  var preview = document.getElementById('upload-preview');
  if (!preview) return;

  preview.innerHTML = '';
  pendingFiles.forEach(function(file, index) {
    var item = document.createElement('div');
    item.className = 'upload-preview-item';

    // Show thumbnail for images
    if (file.type.startsWith('image/')) {
      var img = document.createElement('img');
      img.className = 'upload-preview-thumb';
      var reader = new FileReader();
      reader.onload = function(e) { img.src = e.target.result; };
      reader.readAsDataURL(file);
      item.appendChild(img);
    } else {
      var icon = document.createElement('span');
      icon.className = 'upload-preview-icon';
      icon.textContent = '📄';
      item.appendChild(icon);
    }

    var name = document.createElement('span');
    name.className = 'upload-preview-name';
    name.textContent = file.name;
    item.appendChild(name);

    var size = document.createElement('span');
    size.className = 'upload-preview-size';
    size.textContent = formatFileSize(file.size);
    item.appendChild(size);

    var removeBtn = document.createElement('button');
    removeBtn.className = 'upload-preview-remove';
    removeBtn.textContent = '×';
    removeBtn.onclick = function() { removeFile(index); };
    item.appendChild(removeBtn);

    preview.appendChild(item);
  });
}

// Remove a file from pending list
function removeFile(index) {
  pendingFiles.splice(index, 1);
  updateUploadPreview();
}

// Format file size for display
function formatFileSize(bytes) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return Math.round(bytes / 1024) + ' KB';
  return Math.round(bytes / (1024 * 1024)) + ' MB';
}

// Upload pending files and return array of attachment IDs
async function uploadPendingFiles(threadId) {
  var attachmentIds = [];

  for (var i = 0; i < pendingFiles.length; i++) {
    var file = pendingFiles[i];
    var formData = new FormData();
    formData.append('file', file);

    try {
      var response = await fetch('/chat/thread/' + threadId + '/upload', {
        method: 'POST',
        body: formData
      });

      if (response.ok) {
        var result = await response.json();
        if (result.id) {
          attachmentIds.push(result.id);
        }
      } else {
        console.error('Failed to upload file:', file.name);
      }
    } catch (err) {
      console.error('Error uploading file:', file.name, err);
    }
  }

  return attachmentIds;
}

// Submit message with attachments
async function submitMessageWithAttachments() {
  var form = document.getElementById('message-form');
  var contentField = document.getElementById('message-content');
  var attachmentsField = document.getElementById('attachments-input');
  var fileInput = document.getElementById('file-input');

  if (!form || !contentField) return;

  // Get thread ID from file input data attribute
  var threadId = fileInput ? fileInput.getAttribute('data-thread-id') : null;

  // Upload any pending files first
  var attachmentIds = [];
  if (pendingFiles.length > 0 && threadId) {
    attachmentIds = await uploadPendingFiles(threadId);
  }

  // Set attachment IDs in hidden field
  if (attachmentsField) {
    attachmentsField.value = attachmentIds.join(',');
  }

  // Clear pending files and preview
  pendingFiles = [];
  updateUploadPreview();

  // Submit the form via HTMX
  htmx.trigger(form, 'submit');
}

// Clear message form after successful submit
function afterMessageSubmit(form) {
  var contentField = form.querySelector('#message-content');
  if (contentField) {
    contentField.value = '';
  }
  var attachmentsField = form.querySelector('#attachments-input');
  if (attachmentsField) {
    attachmentsField.value = '';
  }
  var fileInput = form.querySelector('#file-input');
  if (fileInput) {
    fileInput.value = '';
  }
  pendingFiles = [];
  updateUploadPreview();
}

// =============================================================================
// Server-Sent Events (SSE) for Real-time Updates
// =============================================================================

(function() {
  // Prevent multiple SSE connections across script re-executions
  if (window._chatSSEInitialized) {
    console.log('Chat SSE already initialized, skipping');
    return;
  }
  window._chatSSEInitialized = true;

  var eventSource = null;
  var refreshPending = false;
  var messagesRefreshPending = false;

  // Get the currently viewed thread ID from the URL or active thread element
  function getCurrentThreadId() {
    // Try URL first: /chat/thread/123
    var match = window.location.pathname.match(/\/chat\/thread\/(\d+)/);
    if (match) {
      return parseInt(match[1], 10);
    }
    // Fallback: look for active thread element
    var activeThread = document.querySelector('.chat-thread-active');
    if (activeThread && activeThread.id) {
      var idMatch = activeThread.id.match(/thread-(\d+)/);
      if (idMatch) {
        return parseInt(idMatch[1], 10);
      }
    }
    return null;
  }

  function refreshThreadList() {
    if (refreshPending) return;
    refreshPending = true;
    console.log('Refreshing chat thread list...');
    setTimeout(function() {
      htmx.ajax('GET', '/chat', {target: '#chat-threads', swap: 'outerHTML'});
      refreshPending = false;
    }, 100);
  }

  function refreshMessages(threadId) {
    if (messagesRefreshPending) return;
    messagesRefreshPending = true;
    console.log('Refreshing messages for thread', threadId);
    setTimeout(function() {
      htmx.ajax('GET', '/chat/thread/' + threadId, {target: '#chat-messages-area', swap: 'innerHTML'});
      messagesRefreshPending = false;
    }, 100);
  }

  function scrollToBottom() {
    var messagesList = document.getElementById('messages-list');
    if (messagesList) {
      messagesList.scrollTop = messagesList.scrollHeight;
    }
  }

  function connectSSE() {
    if (eventSource) {
      eventSource.close();
      eventSource = null;
    }

    console.log('Connecting to Chat SSE...');
    eventSource = new EventSource('/events/chat');

    eventSource.onopen = function() {
      console.log('Chat SSE connected');
    };

    eventSource.onerror = function(e) {
      console.log('Chat SSE error, reconnecting...', e);
    };

    // Thread events - just refresh thread list
    ['thread-created', 'thread-updated', 'thread-deleted'].forEach(function(eventType) {
      eventSource.addEventListener(eventType, function(e) {
        console.log('Chat SSE event:', eventType, e.data);
        refreshThreadList();
      });
    });

    // Message events - refresh messages if viewing that thread
    eventSource.addEventListener('message-added', function(e) {
      console.log('Chat SSE event: message-added', e.data);
      try {
        var data = JSON.parse(e.data);
        var currentThreadId = getCurrentThreadId();
        console.log('Current thread:', currentThreadId, 'Event thread:', data.threadId, 'Match:', currentThreadId === data.threadId);
        if (data.threadId && currentThreadId === data.threadId) {
          console.log('Refreshing messages for matching thread');
          refreshMessages(data.threadId);
        }
        // Refresh thread list after checking (so active class is still there)
        refreshThreadList();
      } catch (err) {
        console.log('Error parsing message-added event data:', err);
      }
    });
  }

  function disconnectSSE() {
    if (eventSource) {
      console.log('Closing Chat SSE connection...');
      eventSource.close();
      eventSource = null;
    }
  }

  // Close SSE on page unload/navigation
  window.addEventListener('beforeunload', function() {
    window._chatSSEInitialized = false;
    disconnectSSE();
  });
  window.addEventListener('pagehide', function() {
    window._chatSSEInitialized = false;
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

  // Auto-scroll to bottom when new messages are added
  document.body.addEventListener('htmx:afterSwap', function(evt) {
    if (evt.detail.target.id === 'messages-list') {
      scrollToBottom();
    }
  });

  // Scroll to bottom on initial page load
  document.addEventListener('DOMContentLoaded', function() {
    scrollToBottom();
  });
})();
