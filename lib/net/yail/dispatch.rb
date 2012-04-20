module Net
class YAIL

module Dispatch
  # Given an event, calls pre-callback filters, callback, and post-callback filters.  Uses
  # *_any event, where * is the event's event_class value
  def dispatch(event)
    # We always have an "any" filter option, so we build the symbol first
    any_filter_sym = (event.event_class + "_any").to_sym

    before_any = @before_filters[any_filter_sym]
    run_chain(event, :allow_halt => true, :handlers => [before_any, @before_filters[event.type]])

    # Have to break here if before filters said so
    return if event.handled?

    # Legacy handler - return if true, since that's how the old system works - EXCEPTION for outgoing events, since
    # the old system didn't allow the outgoing "core" code to be skipped!
    if true == legacy_process_event(event)
      return unless Net::YAIL::OutgoingEvent === event
    end

    # Add new callback and all after-callback stuff to a new chain
    after_any = @after_filters[any_filter_sym]
    run_chain(event, :allow_halt => false, :handlers => [@callback[event.type], @after_filters[event.type], after_any])
  end

  # Consolidates all handlers passed in, flattening into a single array of handlers and
  # removing any nils, then runs the methods on each event
  def run_chain(event, opts = {})
    handlers = opts[:handlers]
    handlers.flatten!
    handlers.compact!

    allow_halt = opts[:allow_halt]

    # Run each filter in the chain, exiting early if event was handled
    for handler in handlers
      handler.call(event)
      return if event.handled? && true == allow_halt
    end

  end
end

end
end
