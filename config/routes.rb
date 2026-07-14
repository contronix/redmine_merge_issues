# config/routes.rb

RedmineApp::Application.routes.draw do
  # Nested under /issues/:issue_id/merge
  resources :issues, only: [] do
    resource :merge,
             controller: 'merge_issues',
             only: [:new, :create],
             as: :merge

    # Collection-level merge of several issues selected from the issue list:
    # GET  /issues/merge/new?ids[]=1&ids[]=2  -> pick the destination issue
    # POST /issues/merge                      -> merge all others into it
    collection do
      get 'merge/new', to: 'merge_issues#new_multiple', as: :new_merge
      post 'merge', to: 'merge_issues#create_multiple', as: :merge
    end
  end
end
