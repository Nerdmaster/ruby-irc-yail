module Net
class YAIL

module Dispatch
  # Given an event, calls pre-callback filters, callback, and post-callback filters.  Uses hacky
  # :incoming_any event if event object is of IncomingEvent type.
  def dispatch(event)
    # Add all before-callback stuff to our chain
    chain = []
    chain.push @before_filters[:incoming_any] if Net::YAIL::IncomingEvent === event
    chain.push @before_filters[:outgoing_any] if Net::YAIL::OutgoingEvent === event
    chain.push @before_filters[event.type]
    chain.flatten!
    chain.compact!

    # Run each filter in the chain, exiting early if event was handled
    for filter in chain
      filter.call(event)
      return if event.handled?
    end

    # Legacy handler - return if true, since that's how the old system works - EXCEPTION for outgoing events, since
    # the old system didn't allow the outgoing "core" code to be skipped!
    if true == legacy_process_event(event)
      return unless Net::YAIL::OutgoingEvent === event
    end

    # Add new callback and all after-callback stuff to a new chain
    chain = []
    chain.push @callback[event.type]
    chain.push @after_filters[event.type]
    chain.push @after_filters[:incoming_any] if Net::YAIL::IncomingEvent === event
    chain.push @after_filters[:outgoing_any] if Net::YAIL::OutgoingEvent === event
    chain.flatten!
    chain.compact!

    # Run all after-filters blindly - none can affect callback, so after-filters can't set handled to true
    chain.each {|filter| filter.call(event)}
  end
end

end
end
