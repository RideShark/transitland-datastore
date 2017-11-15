# ActiveRecord::Base.logger = Logger.new(STDOUT)
# ActiveRecord::Base.logger.level = Logger::DEBUG

load 'lib/proto/tile_set.rb'

IMPORT_LEVEL = 4
LEVEL = 2

# kTransitEgress = 4,           // Transit egress
# kTransitStation = 5,          // Transit station
# kMultiUseTransitPlatform = 6, // Multi-use transit platform (rail and bus)
NODE_TYPES = {
  StopEgress: 4,
  Stop: 5,
  StopPlatform: 6
}

VT = Valhalla::Mjolnir::Transit::VehicleType
VEHICLE_TYPES = {
  tram: VT::Tram,
  tram_service: VT::Tram,
  metro: VT::Metro,
  rail: VT::Rail,
  suburban_railway: VT::Rail,
  bus: VT::Bus,
  trolleybys_service: VT::Bus,
  express_bus_service: VT::Bus,
  local_bus_service: VT::Bus,
  bus_service: VT::Bus,
  shuttle_bus: VT::Bus,
  demand_and_response_bus_service: VT::Bus,
  regional_bus_service: VT::Bus,
  ferry: VT::Ferry,
  cablecar: VT::CableCar,
  gondola: VT::Gondola,
  funicalr: VT::Funicular
}

def seconds_from_midnight(value)
  h,m,s = value.split(':').map(&:to_i)
  h * 3600 + m * 60 + s
end

def color_to_int(value)
  match = /(\h{6})/.match(value.to_s)
  match ? match[0].to_i(16) : nil
end

class TileBuilder
  attr_accessor :tile
  def initialize(tile)
    @tile = tile
    @bbox = tile.bbox
    # globally unique indexes
    @@stop_graphid ||= {}
    @@graphid_stop ||= {}
    @@trip_index ||= UniqueIndex.new
    @@block_index ||= UniqueIndex.new(start: 1)
    # tile unique indexes
    @node_index = UniqueIndex.new
    @route_index = UniqueIndex.new
    @shape_index = UniqueIndex.new(start: 1)
  end

  def build_stops
    # TODO:
    #    max graph_ids in a tile
    puts "Building stops: #{@tile.tile}"
    Stop.where(parent_stop: nil).geometry_within_bbox(bbox_padded).order(id: :asc).includes(:stop_platforms, :stop_egresses).each do |stop|
      # Check if stop is inside tile
      next if GraphID.new(level: LEVEL, lon: stop.coordinates[0], lat: stop.coordinates[1]).tile != @tile.tile
      puts "\tstop: #{stop.onestop_id}"

      # Station references
      prev_type_graphid = nil

      # Egresses
      stop_egresses = stop.stop_egresses.to_a
      stop_egresses << StopEgress.new(stop.attributes) if stop_egresses.empty? # generated egress
      stop_egresses.each do |stop_egress|
        node = make_node(stop_egress)
        node.graphid = GraphID.new(level: LEVEL, tile: @tile.tile, index: @node_index.next(stop.id)).value
        node.prev_type_graphid = prev_type_graphid if prev_type_graphid
        prev_type_graphid = node.graphid
        @tile.message.nodes << node
      end

      # Station
      node = make_node(stop)
      node.graphid = GraphID.new(level: LEVEL, tile: @tile.tile, index: @node_index.next(stop.id)).value
      node.prev_type_graphid = prev_type_graphid if prev_type_graphid
      prev_type_graphid = node.graphid
      @tile.message.nodes << node

      # Platforms
      stop_platforms = stop.stop_platforms.to_a
      stop_platforms << StopPlatform.new(stop.attributes) # station ssps
      stop_platforms.each do |stop_platform|
        node = make_node(stop_platform)
        node.graphid = GraphID.new(level: LEVEL, tile: @tile.tile, index: @node_index.next(stop.id)).value
        node.prev_type_graphid = prev_type_graphid if prev_type_graphid
        prev_type_graphid = node.graphid
        @@stop_graphid[stop.id] = node.graphid
        @@graphid_stop[node.graphid] = stop.id
        @tile.message.nodes << node
      end
    end
  end

  def build_schedule
    puts "Building schedule: #{@tile.tile}"
    stop_ids = @tile.message.nodes.map { |node| @@graphid_stop[node.graphid] }.compact

    # Routes
    route_ids = ScheduleStopPair.where(origin_id: stop_ids).select(:route_id).distinct(:route_id).pluck(:route_id)
    Route.where(id: route_ids).order(id: :asc).includes(:operator).each do |route|
      puts "\troute: #{route.onestop_id}"
      @route_index.next(route.id)
      @tile.message.routes << make_route(route)
    end

    # Shapes
    rsp_ids = ScheduleStopPair.where(origin_id: stop_ids).select(:route_stop_pattern_id).distinct(:route_stop_pattern_id).pluck(:route_stop_pattern_id)
    RouteStopPattern.where(id: rsp_ids).order(id: :asc).each do |rsp|
      puts "\trsp: #{rsp.onestop_id}"
      shape = make_shape(rsp)
      shape.shape_id = @shape_index.next(rsp.id)
      @tile.message.shapes << shape
    end

    # StopPairs - do per stop
    stop_ids.each do |stop_id|
      ScheduleStopPair.where(origin_id: stop_id).includes(:origin, :destination, :operator).find_each do |ssp|
        @tile.message.stop_pairs << make_stop_pair(ssp)
      end
    end
    puts "\tssp: total #{@tile.message.stop_pairs.size}"
  end

  private

  # bbox padding
  def bbox_padded
    ymin, xmin, ymax, xmax = @tile.bbox
    padding = 0.0
    [ymin-padding, xmin, ymax+padding, xmax]
  end

  # make entity methods
  def make_stop_pair(ssp)
    # TODO:
    #   skip if origin == destination_id
    #   skip unless route
    #   skip if origin_departure_time < frequency_start_time
    #   skip if bad time information
    #   skip if no trip
    #   add < and > to onestop_ids
    #   line_id?
    params = {}
    # bool bikes_allowed = 1;
    # uint32 block_id = 2;
    # params[:block_id] = @@block_index.check(ssp.block_id)
    # uint32 destination_arrival_time = 3;
    params[:destination_arrival_time] = seconds_from_midnight(ssp.destination_arrival_time)
    # uint64 destination_graphid = 4;
    params[:destination_graphid] = @@stop_graphid.fetch(ssp.destination_id)
    # string destination_onestop_id = 5;
    params[:destination_onestop_id] = ssp.destination.onestop_id
    # string operated_by_onestop_id = 6;
    params[:operated_by_onestop_id] = ssp.operator.onestop_id
    # uint32 origin_departure_time = 7;
    params[:origin_departure_time] = seconds_from_midnight(ssp.origin_departure_time)
    # uint64 origin_graphid = 8;
    params[:origin_graphid] = @@stop_graphid.fetch(ssp.origin_id)
    # string origin_onestop_id = 9;
    params[:origin_onestop_id] = ssp.origin.onestop_id
    # uint32 route_index = 10;
    params[:route_index] = @route_index.fetch(ssp.route_id)
    # repeated uint32 service_added_dates = 11;
    params[:service_added_dates] = ssp.service_added_dates.map(&:jd)
    # repeated bool service_days_of_week = 12;
    params[:service_days_of_week] = ssp.service_days_of_week
    # uint32 service_end_date = 13;
    params[:service_end_date] = ssp.service_end_date.jd
    # repeated uint32 service_except_dates = 14;
    params[:service_except_dates] = ssp.service_except_dates.map(&:jd)
    # uint32 service_start_date = 15;
    params[:service_start_date] = ssp.service_start_date.jd
    # string trip_headsign = 16;
    params[:trip_headsign] = ssp.trip_headsign
    # uint32 trip_id = 17;
    params[:trip_id] = @@trip_index.check(ssp.trip)
    # bool wheelchair_accessible = 18;
    params[:wheelchair_accessible] = true # !!(ssp.wheelchair_accessible)
    # uint32 shape_id = 20;
    params[:shape_id] = @shape_index.fetch(ssp.route_stop_pattern_id)
    # float origin_dist_traveled = 21;
    params[:origin_dist_traveled] = ssp.origin_dist_traveled
    # float destination_dist_traveled = 22;
    params[:destination_dist_traveled] = ssp.destination_dist_traveled
    if ssp.frequency_headway_seconds
      # protobuf doesn't define frequency_start_time
      # uint32 frequency_end_time = 23;
      params[:frequency_end_time] = seconds_from_midnight(ssp.frequency_end_time)
      # uint32 frequency_headway_seconds = 24;
      params[:frequency_headway_seconds] = ssp.frequency_headway_seconds
    end
    Valhalla::Mjolnir::Transit::StopPair.new(params)
  end

  def make_shape(rsp)
    params = {}
    # uint32 shape_id = 1;
    # bytes encoded_shape = 2;
    # reverse coordinates
    reversed = rsp.geometry[:coordinates].map { |a,b| [b,a] }
    params[:encoded_shape] = Shape7.encode(reversed)
    Valhalla::Mjolnir::Transit::Shape.new(params)
  end

  def make_route(route)
    # TODO:
    #   skip if unknown vehicle_type
    params = {}
    # string name = 1;
    params[:name] = route.name
    # string onestop_id = 2;
    params[:onestop_id] = route.onestop_id
    # string operated_by_name = 3;
    params[:operated_by_name] = route.operator.name
    # string operated_by_onestop_id = 4;
    params[:operated_by_onestop_id] = route.operator.onestop_id
    # string operated_by_website = 5;
    params[:operated_by_website] = route.operator.website
    # uint32 route_color = 6;
    params[:route_color] = color_to_int(route.color || 'FFFFFF')
    # string route_desc = 7;
    params[:route_desc] = route.tags["route_desc"]
    # string route_long_name = 8;
    params[:route_long_name] = route.tags["route_long_name"] || route.name
    # uint32 route_text_color = 9;
    params[:route_text_color] = color_to_int(route.tags["route_text_color"])
    # VehicleType vehicle_type = 10;
    params[:vehicle_type] = VEHICLE_TYPES[route.vehicle_type.to_sym] || VT::Bus
    Valhalla::Mjolnir::Transit::Route.new(params.compact)
  end

  def make_node(stop)
    params = {}
    # float lon = 1;
    params[:lon] = stop.coordinates[0]
    # float lat = 2;
    params[:lat] = stop.coordinates[1]
    # uint32 type = 3;
    params[:type] = NODE_TYPES[stop.class.name.to_sym]
    # uint64 graphid = 4;
    # set in build_stops
    # uint64 prev_type_graphid = 5;
    # set in build_stops
    # string name = 6;
    params[:name] = stop.name
    # string onestop_id = 7;
    params[:onestop_id] = stop.onestop_id
    # uint64 osm_way_id = 8;
    params[:osm_way_id] = stop.osm_way_id
    # string timezone = 9;
    params[:timezone] = stop.timezone
    # bool wheelchair_boarding = 10;
    params[:wheelchair_boarding] = true
    # bool generated = 11;
    if stop.instance_of?(StopEgress) && !stop.persisted?
      params[:onestop_id] = "#{stop.onestop_id}>"
      params[:generated] = true
    end
    if stop.instance_of?(StopPlatform) && !stop.persisted?
      params[:onestop_id] = "#{stop.onestop_id}<"
      # params[:generated] = true # not set for platforms
    end
    # uint32 traversability = 12;
    if stop.instance_of?(StopEgress)
      params[:traversability] = 3
    end
    Valhalla::Mjolnir::Transit::Node.new(params.compact)
  end
end

# Tileset
tileset = TileSet.new(ARGV[0])

puts "Feeds"
build_tiles = Set.new
Feed.where_active_feed_version_import_level(IMPORT_LEVEL).find_each do |feed|
  puts "feed: #{feed.onestop_id}"
  bbox = feed.geometry_bbox
  b = bbox.min_x, bbox.min_y, bbox.max_x, bbox.max_y
  puts "bbox: #{b.join(',')}"
  GraphID.bbox_to_level_tiles(*b).select { |a,b| a == 2}.each { |a,b| build_tiles << tileset.get_tile(a,b) }
end

puts "Tiles to build: #{build_tiles.size}"

builders = build_tiles.map { |tile| TileBuilder.new(tile) }
# Build stops for each tile.
builders.each { |builder| builder.build_stops }
# Build schedule, routes, shapes for each tile.
builders.each { |builder| builder.build_schedule }
# Write out result
builders.each { |builder| tileset.write_tile(builder.tile) }





#
