# frozen_string_literal: true

class MergeIssuesController < ApplicationController
  # `helper :custom_fields` makes `show_value` available on view_context, which
  # is used by snapshot_source_custom_values below. Redmine's ApplicationController
  # does NOT do `helper :all`, so each controller must include the helpers it needs.
  helper :custom_fields

  before_action :find_issue, only: [:new, :create]
  before_action :authorize, only: [:new, :create]
  before_action :find_selected_issues, only: [:new_multiple, :create_multiple]
  before_action :authorize_selected_issues, only: [:new_multiple, :create_multiple]

  # GET /issues/:issue_id/merge/new
  # Renders the merge modal (used via Turbo or plain AJAX)
  def new
    respond_to do |format|
      format.html
      format.js
    end
  end

  # POST /issues/:issue_id/merge
  def create
    other_id = params[:other_issue_id].to_s.gsub(/\A#/, '').strip.to_i

    if other_id == 0 || other_id == @issue.id
      return redirect_back_with_error(l(:error_merge_same_issue))
    end

    other = Issue.visible.find_by(id: other_id)

    unless other
      return redirect_back_with_error(l(:error_merge_other_not_found))
    end

    # Détermine source (supprimée) et destination (conservée) selon le sens choisi.
    # 'from_other' : la demande saisie est la source, la demande courante la destination.
    # Sinon (défaut) : la demande courante est la source, la demande saisie la destination.
    if params[:merge_direction].to_s == 'from_other'
      source = other
      destination = @issue
    else
      source = @issue
      destination = other
    end

    # Les deux projets sont impactés : on exige la permission sur chacun.
    unless User.current.allowed_to?(:merge_issues, source.project) &&
           User.current.allowed_to?(:merge_issues, destination.project)
      return redirect_back_with_error(l(:error_merge_not_allowed_on_destination))
    end

    begin
      ActiveRecord::Base.transaction do
        merge_issues!(source, destination)
      end
      flash[:notice] = l(:notice_merge_success, source: source.id, destination: destination.id)
      redirect_to issue_path(destination)
    rescue StandardError => e
      Rails.logger.error("[MergeIssues] Merge failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      redirect_back_with_error(l(:error_merge_failed))
    end
  end

  # GET /issues/merge/new?ids[]=1&ids[]=2
  # Lets the user pick which of the selected issues to keep (destination)
  def new_multiple
  end

  # POST /issues/merge
  # Merges every selected issue except the destination into the destination,
  # deleting each source issue.
  def create_multiple
    destination = @issues.detect { |issue| issue.id == params[:destination_id].to_i }

    unless destination
      flash[:error] = l(:error_merge_destination_not_found)
      return redirect_to new_merge_issues_path(ids: @issues.map(&:id))
    end

    sources = @issues - [destination]

    begin
      ActiveRecord::Base.transaction do
        sources.each { |source| merge_issues!(source, destination) }
      end
      flash[:notice] = l(:notice_merge_multiple_success,
                         sources: sources.map { |s| "##{s.id}" }.join(', '),
                         destination: destination.id)
      redirect_to issue_path(destination)
    rescue StandardError => e
      Rails.logger.error("[MergeIssues] Multiple merge failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      flash[:error] = l(:error_merge_failed)
      redirect_to new_merge_issues_path(ids: @issues.map(&:id))
    end
  end

  private

  def find_issue
    @issue = Issue.find(params[:issue_id])
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def authorize
    unless User.current.allowed_to?(:merge_issues, @issue.project)
      deny_access
    end
  end

  # Loads the issues selected from the issue list (ids[] param).
  # 404 if fewer than two are requested or any of them is missing/not visible.
  def find_selected_issues
    ids = Array(params[:ids]).map(&:to_i).uniq.reject(&:zero?)
    @issues = Issue.visible.where(id: ids).sort_by(&:id)

    render_404 if @issues.size < 2 || @issues.size != ids.size
  end

  # All impacted projects require the merge permission.
  def authorize_selected_issues
    unless @issues.map(&:project).uniq.all? { |project| User.current.allowed_to?(:merge_issues, project) }
      deny_access
    end
  end

  def redirect_back_with_error(message)
    flash[:error] = message
    redirect_to issue_path(@issue)
  end

  # ---------------------------------------------------------------
  # Core merge logic
  # ---------------------------------------------------------------
  def merge_issues!(source, destination)
    # 1. Convert source description to a journal note in destination
    if source.description.present?
      author = source.author || User.current
      note_text = <<~NOTE
        #{l(:label_merge_original_description, id: source.id, subject: source.subject)}

        #{source.description}
      NOTE
      journal = Journal.new(journalized: destination, user: author, notes: note_text)
      journal.notify = false
      journal.save!
      journal.update_column(:created_on, source.created_on)
    end

    # 2. Move journals (comments) from source → destination
    source.journals.each do |journal|
      journal.update_columns(journalized_id: destination.id)
    end

    # 3. Move time entries
    source.time_entries.each do |entry|
      entry.update_columns(issue_id: destination.id)
    end

    # 4. Move attachments
    source.attachments.each do |attachment|
      attachment.update_columns(container_id: destination.id)
    end

    # 5. Move child issues (sub-tickets)
    source.children.each do |child|
      child.update_columns(parent_id: destination.id)
    end

    # 6. Move issue relations (avoid duplicates and self-relations)
    source.relations.each do |relation|
      other_id   = (relation.issue_from_id == source.id) ? relation.issue_to_id   : relation.issue_from_id
      other_side = (relation.issue_from_id == source.id) ? :issue_from_id          : :issue_to_id

      # Skip if the relation would become self-referential or already exists
      next if other_id == destination.id
      existing = IssueRelation.where(
        issue_from_id: [destination.id, other_id],
        issue_to_id:   [destination.id, other_id]
      ).where(relation_type: relation.relation_type).exists?
      next if existing

      relation.update_columns(other_side => destination.id)
    end

    # 7. Update any relations that still reference source (from_id or to_id)
    IssueRelation.where(issue_from_id: source.id).update_all(issue_from_id: destination.id)
    IssueRelation.where(issue_to_id:   source.id).update_all(issue_to_id:   destination.id)

    # 8. Move changesets (repository revisions)
    new_changesets = source.changesets - destination.changesets
    destination.changesets << new_changesets if new_changesets.any?
    source.changesets.clear

    # 9. Move watchers
    # On crée les Watcher directement (au lieu de add_watcher qui utilise
    # Watcher.create sans bang et avale les erreurs de validation silencieusement).
    # Toute copie échouée est tracée dans les logs au lieu de disparaître.
    existing_watcher_ids = destination.watcher_user_ids
    source.watcher_users.each do |user|
      next if existing_watcher_ids.include?(user.id)

      watcher = Watcher.new(watchable: destination, user: user)
      if watcher.save
        existing_watcher_ids << user.id
      else
        Rails.logger.warn(
          "[MergeIssues] Watcher non copié (issue ##{source.id} -> ##{destination.id}) " \
          "user ##{user.id} (#{user.login}) : #{watcher.errors.full_messages.join(', ')}"
        )
      end
    end
    destination.watchers.reload

    # 10. Escalate priority to the highest of source and destination
    if source.priority.position > destination.priority.position
      destination.priority = source.priority
    end

    # 11. Add a journal note to destination referencing the merge
    merge_note = l(:label_merge_note, source_id: source.id, source_subject: source.subject,
                                      user: User.current.name, date: format_date(Date.today))
    journal = destination.init_journal(User.current, merge_note)
    journal.notify = false
    destination.save!

    # 11bis. Snapshot the source's custom field values as a *private* journal note
    # on the destination. acts_as_customizable declares custom_values with
    # `dependent: :delete_all`, so step 12 hard-deletes them — without this
    # snapshot the values would be lost. The note is private so the data is
    # available to users with `view_private_notes` permission only.
    snapshot_source_custom_values(source, destination)

    # 12. Destroy source issue (skips callbacks that might be slow; adjust if needed)
    source.destroy
  end

  # Builds a private journal note on `destination` containing each non-blank
  # custom field value from `source`, formatted with the same helper Redmine
  # uses on the issue page (so enumeration / user / version values are shown by
  # name, not by id). Skipped when the source has no non-blank values.
  def snapshot_source_custom_values(source, destination)
    cfvs = source.visible_custom_field_values.reject { |cfv| cfv.value.blank? }
    return if cfvs.empty?

    body_lines = cfvs.map do |cfv|
      "**#{cfv.custom_field.name}**\n#{view_context.show_value(cfv, false)}"
    end

    note_body = "#{l(:label_merge_source_custom_fields_heading, id: source.id)}\n\n" \
                "#{body_lines.join("\n\n")}"

    journal = Journal.new(
      journalized: destination,
      user: User.current,
      notes: note_body,
      private_notes: true
    )
    journal.notify = false
    journal.save!
  end
end
