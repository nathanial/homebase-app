/**
 * Chat JavaScript
 * Handles real-time updates via SSE and scroll behavior
 */

// =============================================================================
// Server-Sent Events (SSE) for Real-time Updates
// =============================================================================

(function() {
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
