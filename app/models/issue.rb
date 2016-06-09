# == Schema Information
#
# Table name: issues
#
#  id                       :integer          not null, primary key
#  created_by_changeset_id  :integer          not null
#  resolved_by_changeset_id :integer
#  details                  :string
#  issue_type               :string
#  open                     :boolean          default(TRUE)
#  block_changeset_apply    :boolean          default(FALSE)
#  created_at               :datetime
#  updated_at               :datetime
#

class Issue < ActiveRecord::Base
  has_many :entities_with_issues
  belongs_to :feed_version
  belongs_to :created_by_changeset, class_name: 'Changeset'
  belongs_to :resolved_by_changeset, class_name: 'Changeset'

  before_save :description

  def set_entity_with_issues_params(ewi_params)
    ewi_params[:entity] = OnestopId.find!(ewi_params.delete(:onestop_id))
    self.entities_with_issues << EntityWithIssues.find_or_initialize_by(ewi_params)
  end

  private

  # TODO: remove. Probably not necessary
  def description
    case self.issue_type
    when 'stop_rsp_distance_gap'
      self.details = 'Distance gap between RouteStopPattern and Stop. ' + self.details
    when 'distance'
      self.details = 'Inaccuracy in distance calculation. ' + self.details
    end
  end
end
