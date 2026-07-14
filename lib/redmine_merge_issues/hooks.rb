# lib/redmine_merge_issues/hooks.rb
# frozen_string_literal: true

module RedmineMergeIssues
  class Hooks < Redmine::Hook::ViewListener
    # Injecte un <template> caché avec le lien Merge (vérif permission serveur).
    # Le JS merge_issues.js le déplace ensuite dans le menu "..." (.drdn-items).
    render_on :view_issues_show_description_bottom,
              partial: 'merge_issues/action_item'

    # Adds a "Merge" entry to the issue-list context menu (right click /
    # actions on selected rows). With one issue selected it opens the regular
    # merge screen; with several it opens the destination-picker screen.
    render_on :view_issues_context_menu_end,
              partial: 'merge_issues/context_menu'
  end
end
