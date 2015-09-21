# == Schema Information
#
# Table name: current_routes
#
#  id                                 :integer          not null, primary key
#  onestop_id                         :string
#  name                               :string
#  tags                               :hstore
#  operator_id                        :integer
#  created_or_updated_in_changeset_id :integer
#  version                            :integer
#  created_at                         :datetime
#  updated_at                         :datetime
#  geometry                           :geography({:srid geometry, 4326
#  identifiers                        :string           default([]), is an Array
#
# Indexes
#
#  c_route_cu_in_changeset              (created_or_updated_in_changeset_id)
#  index_current_routes_on_identifiers  (identifiers)
#  index_current_routes_on_operator_id  (operator_id)
#  index_current_routes_on_tags         (tags)
#  index_current_routes_on_updated_at   (updated_at)
#

class RouteSerializer < CurrentEntitySerializer
  attributes :onestop_id,
             :name,
             :geometry,
             :tags,
             :operated_by_onestop_id,
             :operated_by_name,
             :created_at,
             :updated_at

  def operated_by_onestop_id
    object.operator.try(:onestop_id)
  end

  def operated_by_name
    object.operator.try(:name)
  end
end
