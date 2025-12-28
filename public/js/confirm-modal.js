/**
 * Confirmation Modal
 * Replaces browser's native confirm() dialogs with styled modals
 * Automatically intercepts HTMX hx-confirm attributes
 */

(function() {
  // Create and show modal
  function showConfirmModal(message, onConfirm, onCancel) {
    // Remove any existing modal
    var existing = document.getElementById('confirm-modal-overlay');
    if (existing) existing.remove();

    var overlay = document.createElement('div');
    overlay.className = 'modal-overlay';
    overlay.id = 'confirm-modal-overlay';

    overlay.innerHTML =
      '<div class="modal-container modal-sm">' +
        '<h3 class="modal-title">Confirm Delete</h3>' +
        '<p class="confirm-message">' + escapeHtml(message) + '</p>' +
        '<div class="modal-actions">' +
          '<button type="button" class="btn btn-secondary" id="confirm-cancel">Cancel</button>' +
          '<button type="button" class="btn btn-danger" id="confirm-delete">Delete</button>' +
        '</div>' +
      '</div>';

    document.body.appendChild(overlay);

    // Focus the cancel button (safer default)
    document.getElementById('confirm-cancel').focus();

    function cleanup() {
      overlay.remove();
      document.removeEventListener('keydown', handleKeydown);
    }

    // Handle clicks
    overlay.addEventListener('click', function(e) {
      if (e.target === overlay || e.target.id === 'confirm-cancel') {
        cleanup();
        if (onCancel) onCancel();
      } else if (e.target.id === 'confirm-delete') {
        cleanup();
        if (onConfirm) onConfirm();
      }
    });

    // Handle keyboard
    function handleKeydown(e) {
      if (e.key === 'Escape') {
        cleanup();
        if (onCancel) onCancel();
      } else if (e.key === 'Enter' && document.activeElement.id === 'confirm-delete') {
        cleanup();
        if (onConfirm) onConfirm();
      }
    }
    document.addEventListener('keydown', handleKeydown);
  }

  function escapeHtml(text) {
    var div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // Export for direct use
  window.showConfirmModal = showConfirmModal;

  // Intercept HTMX confirm events (use document, not body, since script loads in head)
  document.addEventListener('htmx:confirm', function(e) {
    // Only intercept if there's a confirm message
    if (!e.detail.question) return;

    e.preventDefault();
    showConfirmModal(e.detail.question, function() {
      e.detail.issueRequest(true);
    });
  });
})();
