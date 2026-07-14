// Injects the "Merge" link into the "..." dropdown of the Redmine issue page.
// Runs immediately if the DOM is already parsed, otherwise waits for
// DOMContentLoaded. The plain `addEventListener('DOMContentLoaded', …)` form
// used previously silently lost its callback when the script tag was evaluated
// after the event had already fired.
(function () {
  function injectMergeLink() {
    var template = document.getElementById('merge-drdn-item');
    if (!template) return;

    var dropdown = document.querySelector('.contextual .drdn .drdn-items');
    if (!dropdown) return;

    dropdown.appendChild(template.content.cloneNode(true));
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', injectMergeLink);
  } else {
    injectMergeLink();
  }
})();
