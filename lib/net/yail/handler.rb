module Net
class YAIL

  # Represents a method and meta-data for handling an event
  class Handler
    def initialize(method, conditions = {})
      @method = method

      # Make sure even an explicit nil is turned into an empty hash
      @conditions = conditions || {}
    end

    # Calls the handler with the given arguments if the conditions are met
    def call(event)
      # Get out if :if/:unless aren't met
      return if @conditions[:if] && !condition_check(@conditions[:if], event)
      return if @conditions[:unless] && condition_check(@conditions[:unless], event)

      return @method.call(event)
    end

    # Checks the condition.  Procs are simply run and returned, while Hash-based conditions return
    # true if value === event.send(key)
    def condition_check(condition, event)
      # Procs are the easiest to evaluate
      return condition.call(event) if condition.is_a?(Proc)

      # If not a proc, condition must be a hash - iterate over values.  All must be true to
      # return true.
      for (key, value) in condition
        return false unless value === event.send(key)
      end
      return true
    end
  end

end
end
