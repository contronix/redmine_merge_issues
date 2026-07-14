# Redmine Merge Issues

A Redmine plugin that **merges issues**: moves all content from a source issue (comments, time entries, attachments, sub-issues, relations, watchers) into a destination issue, then deletes the source issue.

## Features

| Element | Behavior |
|---|---|
| **Source description** | Converted into a journal note in the destination issue |
| **Comments / journals** | Moved to the destination issue |
| **Time entries** | Moved to the destination issue |
| **Attachments** | Moved to the destination issue |
| **Sub-issues** | Re-parented to the destination issue |
| **Issue relations** | Moved (duplicates ignored, self-references avoided) |
| **Watchers** | Merged into the destination issue |
| **Custom field values** | Source values are snapshotted into a *private* journal note on the destination (they would otherwise be deleted with the source) |
| **Priority** | Escalated to the highest of source and destination |
| **Destination fields** | Unchanged (description, assignee, status, etc.) |
| **Merge note** | Automatically added as a journal note in the destination issue |

## Installation

```bash
# 1. Copy the plugin into Redmine's plugins folder
cp -r redmine_merge_issues /path/to/redmine/plugins/

# 2. Install dependencies (if needed)
cd /path/to/redmine
bundle install
```

## Permission Setup

1. Go to **Administration → Roles and permissions**
2. For each role that should be able to merge issues, check **"Merge issues"** under the *Issue tracking* section

## Usage

### From an issue page

1. Open an issue and pick **Merge** from the **"..."** actions dropdown
2. Enter the other issue number and choose the merge direction (which issue is kept)
3. Click **Merge** — the source issue is deleted and all its content is moved to the destination issue

### From the issue list

1. Select one or more issues in the issue list and open the context menu (right click)
2. Pick **Merge**:
   - with a single issue selected, the regular per-issue merge screen opens
   - with several issues selected, a screen asks which issue to **keep**; all the other selected issues are merged into it and then deleted
3. Click **Merge** to confirm

The context-menu entry is enabled only when the user has the *Merge issues* permission on the projects of all selected issues.

## Compatibility

- Redmine ≥ 6.0
- Ruby ≥ 3.0

## Plugin Structure

```
redmine_merge_issues/
├── init.rb                                  # Plugin declaration
├── config/
│   ├── routes.rb                            # Routes: /issues/:issue_id/merge and /issues/merge (multi)
│   └── locales/
│       ├── fr.yml                           # French translations
│       └── en.yml                           # English translations
├── app/
│   ├── controllers/
│   │   └── merge_issues_controller.rb       # Merge logic (single and multi-selection)
│   ├── helpers/
│   │   └── merge_issues_helper.rb
│   └── views/
│       └── merge_issues/
│           ├── _action_item.html.erb        # "Merge" link for the issue "..." menu (injected via hook)
│           ├── _context_menu.html.erb       # "Merge" entry for the issue-list context menu (hook)
│           ├── new.html.erb                 # Per-issue merge screen
│           └── new_multiple.html.erb        # Destination picker for multi-selection merge
├── assets/
│   └── javascripts/
│       └── merge_issues.js                  # Moves the merge link into the "..." dropdown
└── lib/
    ├── redmine_merge_issues.rb
    └── redmine_merge_issues/
        └── hooks.rb                         # Redmine view hooks
```