require 'gtfsgraph'

class FeedEaterScheduleWorker < FeedEaterWorker
  def perform(feed_onestop_id, trip_ids, agency_map, route_map, stop_map)
    feed = Feed.find_by(onestop_id: feed_onestop_id)

    logger.info "FeedEaterScheduleWorker #{feed_onestop_id}: Importing #{trip_ids.size} trips"
    # feed_import = FeedImport.create(feed: feed)
    graph = nil
    begin
      graph = GTFSGraph.new(feed.file_path, feed)
      graph.ssp_perform_async(
        trip_ids,
        agency_map,
        route_map,
        stop_map
      )
    rescue Exception => e
      exception_log = "\n#{e}\n#{e.backtrace}\n"
      logger.error exception_log
      # feed_import.update(success: false, exception_log: exception_log)
      # Raven.capture_exception(e) if defined?(Raven)
    else
      logger.info "FeedEaterScheduleWorker #{feed_onestop_id}: Saving successful import"
      # feed.has_been_fetched_and_imported!(on_feed_import: feed_import)
    ensure
      logger.info "FeedEaterScheduleWorker #{feed_onestop_id}: Saving log & report"
      # feed_import.update(import_log: graph.try(:import_log))
    end

  end
end
