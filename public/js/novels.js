// Novels SSE handler
(function() {
  if (window._novelsSSEInitialized) return;
  window._novelsSSEInitialized = true;

  var eventSource = new EventSource('/events/novels');

  eventSource.addEventListener('novel-created', function(e) {
    // Refresh the novel list
    if (window.location.pathname === '/novels') {
      window.location.reload();
    }
  });

  eventSource.addEventListener('novel-updated', function(e) {
    // Refresh if on the updated novel's page
    var data = JSON.parse(e.data);
    if (window.location.pathname.startsWith('/novels/' + data.novelId)) {
      // Just refresh the title if needed
    }
  });

  eventSource.addEventListener('novel-deleted', function(e) {
    var data = JSON.parse(e.data);
    if (window.location.pathname.startsWith('/novels/' + data.novelId)) {
      window.location.href = '/novels';
    }
  });

  eventSource.addEventListener('page-added', function(e) {
    var data = JSON.parse(e.data);
    if (window.location.pathname.startsWith('/novels/' + data.novelId)) {
      window.location.reload();
    }
  });

  eventSource.addEventListener('page-deleted', function(e) {
    var data = JSON.parse(e.data);
    if (window.location.pathname.startsWith('/novels/' + data.novelId)) {
      window.location.reload();
    }
  });

  eventSource.addEventListener('page-layout-changed', function(e) {
    var data = JSON.parse(e.data);
    if (window.location.pathname === '/novels/' + data.novelId + '/page/' + data.pageNum) {
      window.location.reload();
    }
  });

  eventSource.addEventListener('panel-generating', function(e) {
    // Panel generation started - the HTMX polling will handle updates
  });

  eventSource.addEventListener('panel-generated', function(e) {
    var data = JSON.parse(e.data);
    // Refresh the specific panel via HTMX if we're on the right page
    var panelEl = document.getElementById('panel-' + data.panelIndex);
    if (panelEl) {
      htmx.ajax('GET', '/novels/' + data.novelId + '/page/' + data.pageNum + '/panel/' + data.panelIndex + '/status',
        {target: panelEl, swap: 'innerHTML'});
    }
  });

  eventSource.onerror = function(e) {
    console.log('Novels SSE connection error, will reconnect...');
  };

  window.addEventListener('beforeunload', function() {
    window._novelsSSEInitialized = false;
    eventSource.close();
  });
})();
